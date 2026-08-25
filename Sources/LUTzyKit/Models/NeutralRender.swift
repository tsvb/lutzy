import Foundation
import simd

/// Undoes a rendering, so a finished picture can be fed to a camera LUT.
///
/// A LUT for this camera expects V-Log — scene light. An ordinary photo is a
/// *rendered* picture: the camera already squeezed a 46:1 scene into 0…1 with a
/// tone curve. Handing those numbers to the LUT as though they were scene light
/// is the mistake this exists to undo, and it is a large one: measured, it
/// stretched the midtones over 1.5× the V-Log range they should occupy while
/// collapsing the brightest tenth of the picture into 8% of its proper span —
/// crushed blacks and fused highlights, which is what "the colours look
/// horrible" turned out to mean.
///
/// The rendering being undone is `lutcraft`'s neutral render, the transform its
/// looks were built on top of. That is **not** the Photo Style that actually
/// produced any given JPEG, which nothing here has, so this is an approximation
/// of a real camera — see `AppViewModel.conversionCaveat`. It is an exact
/// inverse of the transform the LUTs were authored against, which is the part
/// that can be made exact.
///
/// ## Why this is closed-form rather than iterative
///
/// The forward transform blends a per-channel curve with a ratio-preserving one:
///
/// ```
/// out = (1-h)·f(x) + h·f(max)·(x/max)        h = 0.40
/// ```
///
/// For the brightest channel `x == max`, and the two terms collapse:
///
/// ```
/// out_max = (1-h)·f(max) + h·f(max) = f(max)
/// ```
///
/// So the brightest channel is the per-channel curve alone, and `f` is
/// invertible in closed form — `softLimit` is, and everything around it is a
/// log and a gamma. That gives `max` exactly (verified against the Python
/// forward transform to 1.11e-16). Each remaining channel then satisfies a
/// scalar monotone equation with `max` already known, which bisection solves on
/// an exact forward evaluation.
///
/// `lutcraft` instead refines the whole triplet multiplicatively 12 times from
/// an interpolated table. That is approximate — measured residual up to
/// 1.9e-3 in display-linear below the ceiling — and this is not, so the two
/// deliberately disagree by that much. The LUTs are generated from the
/// *forward* transform, never from the inverse, so being exact against the
/// forward maths is the better of the two agreements to have.
enum NeutralRender {

    // Parameters of `lutcraft`'s BaseRender, at full precision. `pivot` and
    // `black` are the result of its 48-step fixed point solve, which is
    // per-parameter-set rather than per-pixel and so is precomputed here.
    static let midGrey: Float = 0.18
    static let flare: Float = 0.0015
    static let slope: Float = 0.2
    static let toeKnee: Float = 1.5
    static let shoulderKnee: Float = 2.4
    static let displayGamma: Float = 2.4
    static let huePreserve: Float = 0.4
    static let pivot: Float = 0.444930201789320
    static let black: Float = 0.047111600034829

    /// The brightest scene light the encoding can carry: V-Log code 1.0.
    static let sceneCeiling: Float = 46.085527956740343
    /// What the render makes of that — the brightest display value it can
    /// produce. Anything above it has no finite inverse, because the soft limit
    /// only approaches its limit asymptotically.
    static let displayCeiling: Float = 0.957058850166707

    // MARK: - Forward

    /// Monotone soft clip: linear near zero, asymptotic to `limit`.
    static func softLimit(_ value: Float, _ limit: Float, _ knee: Float) -> Float {
        let z = abs(value) / limit
        let compressed = z / pow(1 + pow(z, knee), 1 / knee)
        return (value < 0 ? -1 : 1) * limit * compressed
    }

    /// Scene linear → display code. 0 → 0 and 0.18 → the pivot code.
    static func curve(_ scene: Float) -> Float {
        // The flare keeps the slope finite at zero. Without it the toe has a
        // vertical tangent at V-Log black, which no 33-point grid can carry.
        let x = max(scene, 0) + flare
        let drive = slope * log2(x / midGrey)
        let raw = pivot + (drive >= 0
                           ? softLimit(drive, 1 - pivot, shoulderKnee)
                           : softLimit(drive, pivot, toeKnee))
        return min(max((raw - black) / (1 - black), 0), 1)
    }

    /// Scene linear → display **linear**. Note the pure 2.4 gamma: that is what
    /// the Python defines, and it is not the sRGB transfer function.
    static func curveLinear(_ scene: Float) -> Float {
        pow(curve(scene), displayGamma)
    }

    // MARK: - Inverse

    /// Display linear → scene linear, for one channel, in closed form.
    ///
    /// Inverts the soft limit algebraically: with `u = |s|/L`,
    /// `z = (uᵏ/(1-uᵏ))^(1/k)`. Exact wherever the forward transform can reach.
    static func inverseCurveLinear(_ displayLinear: Float) -> Float {
        // Clamped before `1 - uᵏ` is formed. At the ceiling `u` is 1 and the
        // expression is singular; near it, Float cancellation reaches infinity
        // early. Both produce NaN downstream if left alone.
        let y = min(max(displayLinear.isFinite ? displayLinear : 0, 0), displayCeiling)
        let code = pow(y, 1 / displayGamma)
        let raw = code * (1 - black) + black
        let offset = raw - pivot
        // The branch is on the sign of the drive, which is the sign of the soft
        // limit's output — not on a display code. (The code at the pivot is
        // 0.4175, not 0.42, so branching on 0.42 would be subtly wrong.)
        let limit = offset >= 0 ? 1 - pivot : pivot
        let knee = offset >= 0 ? shoulderKnee : toeKnee
        let u = min(abs(offset) / limit, 1)
        let uk = pow(u, knee)
        guard uk < 1 else { return sceneCeiling }
        let z = pow(uk / (1 - uk), 1 / knee)
        let drive = (offset < 0 ? -1 : 1) * limit * z
        let scene = midGrey * exp2(min(max(drive / slope, -60), 60)) - flare
        return min(max(scene, 0), sceneCeiling)
    }

    /// How many times the subordinate channels are bisected.
    ///
    /// Measured in Double against the forward transform: 12 iterations leave
    /// 3.9e-3, 16 leave 2.5e-4, 20 leave 1.6e-5, 24 leave 9.8e-7. Twenty is
    /// past the point where a Float kernel can tell the difference.
    static let bisectionSteps = 20

    /// Display linear → scene linear.
    ///
    /// Exact for the brightest channel and for neutrals; bisected for the other
    /// two. Non-finite input, black, and values past the ceiling are all
    /// handled rather than left to produce NaN — a NaN here reaches the LUT as
    /// an index and takes the whole pixel with it.
    static func sceneLinear(_ displayLinear: SIMD3<Float>) -> SIMD3<Float> {
        var target = displayLinear
        for lane in 0..<3 where !target[lane].isFinite { target[lane] = 0 }
        target = simd_clamp(target, .zero, SIMD3<Float>(repeating: displayCeiling))

        let outMax = max(target.x, max(target.y, target.z))
        // Black has no ratio to preserve, and would divide by zero looking for
        // one.
        guard outMax > 1e-10 else { return .zero }

        let norm = inverseCurveLinear(outMax)
        guard norm > 1e-10 else { return .zero }

        // The ratio-preserving term's coefficient, with `f(max)` known exactly.
        let ratioGain = huePreserve * outMax / norm

        var scene = SIMD3<Float>(repeating: 0)
        for lane in 0..<3 {
            // A channel at the maximum is the maximum — including ties, which
            // must not be bisected to a slightly different answer than the
            // channel they are tied with.
            if target[lane] >= outMax - 1e-9 {
                scene[lane] = norm
                continue
            }
            var low: Float = 0
            var high = norm
            for _ in 0..<bisectionSteps {
                let mid = 0.5 * (low + high)
                let forward = (1 - huePreserve) * curveLinear(mid) + ratioGain * mid
                if forward < target[lane] { low = mid } else { high = mid }
            }
            scene[lane] = 0.5 * (low + high)
        }
        return scene
    }
}
