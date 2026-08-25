import Foundation

/// A set of adjustments on top of an existing LUT, and the machinery to bake
/// the result into a new one.
///
/// The editor edits *a LUT*, never nothing. A LUT for this camera maps V-Log to
/// a finished picture, and the second half of that — the rendering of scene
/// light into a displayable image — is a whole transform the app does not carry
/// its own copy of. Starting from an existing look means the editor only has to
/// do the part it is actually good at: pushing an existing rendering around.
///
/// **Order matters and is fixed**, because these operations do not commute:
///
/// 1. sample the base LUT (V-Log in, display code out)
/// 2. decode to linear — exposure and white balance are ratios of light
/// 3. exposure, then contrast about mid grey
/// 4. temperature and tint
/// 5. encode back to display code
/// 6. black lift, in code values, where "lifted blacks" is a statement about
///    the picture rather than about the light
/// 7. saturation, as a chroma scale in OKLab, so hue survives it
struct LookEdit: Codable, Equatable, Sendable {
    /// Stops. Applied in linear light.
    var exposure: Float = 0
    /// −1…+1. Positive steepens about mid grey.
    var contrast: Float = 0
    /// Chroma multiplier. 1 leaves the base alone.
    var saturation: Float = 1
    /// −1 (cool) … +1 (warm).
    var temperature: Float = 0
    /// −1 (green) … +1 (magenta).
    var tint: Float = 0
    /// Code values added to black, rolled off so white does not move.
    var blackLift: Float = 0

    static let neutral = LookEdit()

    var isNeutral: Bool { self == .neutral }

    /// 18% grey in display code, the pivot contrast turns about. The same
    /// number the LUT generator anchors its curve to.
    private static let pivot: Float = 0.42

    /// Apply the edit to one display-referred colour.
    func apply(to code: SIMD3<Float>) -> SIMD3<Float> {
        var linear = SIMD3<Float>(
            OKLab.srgbToLinear(min(max(code.x, 0), 1)),
            OKLab.srgbToLinear(min(max(code.y, 0), 1)),
            OKLab.srgbToLinear(min(max(code.z, 0), 1))
        )

        if exposure != 0 {
            linear *= pow(2, exposure)
        }

        if contrast != 0 {
            // A power about mid grey. Expressed in linear light so it steepens
            // the whole picture rather than only the part a code-value curve
            // would reach.
            let pivotLinear = OKLab.srgbToLinear(Self.pivot)
            let gamma = pow(2, -contrast)          // contrast > 0 → gamma < 1 → steeper
            linear = SIMD3<Float>(
                Self.powerAbout(linear.x, pivot: pivotLinear, gamma: gamma),
                Self.powerAbout(linear.y, pivot: pivotLinear, gamma: gamma),
                Self.powerAbout(linear.z, pivot: pivotLinear, gamma: gamma)
            )
        }

        if temperature != 0 || tint != 0 {
            // A gain per channel, kept close to luminance-neutral so warming a
            // picture does not also brighten it.
            let warm = 1 + 0.30 * temperature
            let cool = 1 - 0.30 * temperature
            let green = 1 - 0.20 * tint
            linear *= SIMD3<Float>(warm, green, cool)
        }

        var out = SIMD3<Float>(
            OKLab.linearToSRGB(max(linear.x, 0)),
            OKLab.linearToSRGB(max(linear.y, 0)),
            OKLab.linearToSRGB(max(linear.z, 0))
        )

        if blackLift != 0 {
            // Rolled off rather than added flat: adding a constant would push
            // white past 1 and clip it, turning a shadow adjustment into a
            // highlight one.
            out = SIMD3<Float>(
                Self.lift(out.x, by: blackLift),
                Self.lift(out.y, by: blackLift),
                Self.lift(out.z, by: blackLift)
            )
        }

        if saturation != 1 {
            let lab = OKLab.fromLinear(SIMD3<Float>(
                OKLab.srgbToLinear(min(max(out.x, 0), 1)),
                OKLab.srgbToLinear(min(max(out.y, 0), 1)),
                OKLab.srgbToLinear(min(max(out.z, 0), 1))
            ))
            let scaled = SIMD3<Float>(lab.x, lab.y * saturation, lab.z * saturation)
            let linearOut = OKLab.toLinear(scaled)
            out = SIMD3<Float>(
                OKLab.linearToSRGB(max(linearOut.x, 0)),
                OKLab.linearToSRGB(max(linearOut.y, 0)),
                OKLab.linearToSRGB(max(linearOut.z, 0))
            )
        }

        return SIMD3<Float>(min(max(out.x, 0), 1), min(max(out.y, 0), 1), min(max(out.z, 0), 1))
    }

    private static func powerAbout(_ value: Float, pivot: Float, gamma: Float) -> Float {
        guard value > 0 else { return 0 }
        return pivot * pow(value / pivot, gamma)
    }

    /// Raise black by `amount` while leaving white where it is.
    private static func lift(_ value: Float, by amount: Float) -> Float {
        amount + value * (1 - amount)
    }
}

/// Bakes an edited look into a new cube.
enum LookBaker {

    /// The grid the DC-S9 accepts. Also what every LUT in this library uses, so
    /// an edit neither gains nor loses resolution against its base.
    static let size = 33

    /// Sample `base` across the grid and apply `edit` to each result.
    ///
    /// `stacked` is applied *after* the edit and must be a display-input LUT:
    /// a second V-Log LUT would be fed a finished picture and read it as scene
    /// light, which is the same mistake as applying a camera LUT to a JPEG.
    /// The caller cannot express that mistake — the type is checked here.
    static func bake(base: CubeLUT, edit: LookEdit, stacked: CubeLUT? = nil, stackAmount: Float = 1) -> [SIMD3<Float>] {
        let n = size
        let maxIndex = Float(n - 1)

        // Grid points, R fastest — the order both the format and CubeLUT use.
        var input = [Float](repeating: 0, count: n * n * n * 3)
        var offset = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    input[offset] = Float(r) / maxIndex
                    input[offset + 1] = Float(g) / maxIndex
                    input[offset + 2] = Float(b) / maxIndex
                    offset += 3
                }
            }
        }

        let sampled = base.sample(input)
        var out = [SIMD3<Float>]()
        out.reserveCapacity(n * n * n)
        for index in stride(from: 0, to: sampled.count, by: 3) {
            out.append(edit.apply(to: SIMD3<Float>(sampled[index], sampled[index + 1], sampled[index + 2])))
        }

        guard let stacked, stacked.inputSpace == .display, stackAmount > 0 else { return out }

        var flat = [Float](repeating: 0, count: out.count * 3)
        for (index, colour) in out.enumerated() {
            flat[index * 3] = colour.x
            flat[index * 3 + 1] = colour.y
            flat[index * 3 + 2] = colour.z
        }
        let through = stacked.sample(flat)
        let amount = min(max(stackAmount, 0), 1)
        for index in out.indices {
            let graded = SIMD3<Float>(through[index * 3], through[index * 3 + 1], through[index * 3 + 2])
            out[index] = out[index] * (1 - amount) + graded * amount
        }
        return out
    }
}
