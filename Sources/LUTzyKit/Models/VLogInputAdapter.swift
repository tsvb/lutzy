import CoreImage

/// Feeds a display-referred image into a V-Log LUT correctly.
///
/// A LUMIX camera-look LUT expects **V-Log / V-Gamut** — scene-referred log —
/// but an ordinary photo, and the image CIRAWFilter develops, is a finished
/// Rec.709/sRGB picture. Applying the LUT straight to that is the classic
/// mistake: the picture is already rendered, so the LUT lifts and desaturates
/// it into a flat, wrong look.
///
/// This adapter runs *before* the LUT and does the missing conversion:
///
/// ```
///   linear Rec.709  → V-Gamut linear  → V-Log encode
/// ```
///
/// The result is a **code value**, and it is handed to `CIColorCube` — the
/// variant with *no* colour space — precisely so nothing converts it on the way
/// in. `CIColorCubeWithColorSpace` converts its input into its own space before
/// indexing, which sRGB-encoded these codes and indexed far too high: measured,
/// input 0.10 landed on 0.436 where 0.181 was wanted. Two implicit conversions
/// (in and out) cannot be cancelled by guessing at one of them, so this path
/// removes both and owns the encoding at each end.
///
/// Core Image hands a colour kernel its sample already in the working space's
/// **linear** form, so there is no sRGB decode to do here — the render context
/// has done it. Doing it again was a measured slope error of up to 0.039.
///
/// The result is exactly what the camera would have recorded, so the LUT then
/// receives the input it was built for. When the source is *already* V-Log
/// (a clip shot on the S9), this adapter is skipped and the LUT is applied
/// directly — that decision lives in `RenderPipeline`, not here.
///
/// The maths matches `lutcraft` (the LUT generator) so a preview here agrees
/// with what the camera and the offline tools produce: the same V-Log transfer
/// constants and the same V-Gamut→Rec.709 matrix, inverted.
enum VLogInputAdapter {

    // V-Log transfer function (Panasonic V-Log/V-Gamut reference).
    private static let cut1: Float = 0.01
    private static let b: Float = 0.00873
    private static let c: Float = 0.241514
    private static let d: Float = 0.598206

    // Rec.709 (linear) → V-Gamut (linear), the inverse of lutcraft's published
    // V-Gamut→Rec.709 matrix. Stored flat and row-major — nine numbers in the
    // order the kernel reads them (m00,m01,m02, m10,...) — rather than a
    // `matrix_float3x3`, whose subscript is column-major and silently fed the
    // transpose before this was caught.
    private static let rec709ToVGamut: [Float] = [
        0.58519614652135366, 0.32264162246936384, 0.092162231009282308,
        0.078588567446848251, 0.81962711468982441, 0.10178431786332748,
        0.022794237910300354, 0.11421702369120433, 0.8629887383984951,
    ]

    // Compiled on demand. `CIColorKernel` is not `Sendable`, so it cannot be a
    // shared `static let` under Swift 6's data-race checking; compiling one per
    // call is cheap (Core Image caches the compiled program by source string).
    // The scene ceiling and the display value the render makes of it. Past that
    // there is no finite inverse — the soft limit only approaches its limit —
    // so the target is clamped before `1 - u^k` is ever formed.
    private static let sceneCeiling: Float = 46.085527956740343
    private static let displayCeiling: Float = 0.957058850166707

    private static let kernelSource = """
        // --- lutcraft's neutral render, forward ---------------------------
        float soft_limit(float v, float L, float k) {
            float z = abs(v) / L;
            return sign(v) * L * (z / pow(1.0 + pow(z, k), 1.0 / k));
        }
        float curve(float scene) {
            float x = max(scene, 0.0) + 0.0015;
            float drive = 0.2 * log2(x / 0.18);
            float lim = drive >= 0.0 ? (1.0 - 0.444930201789320) : 0.444930201789320;
            float knee = drive >= 0.0 ? 2.4 : 1.5;
            float raw = 0.444930201789320 + soft_limit(drive, lim, knee);
            return clamp((raw - 0.047111600034829) / (1.0 - 0.047111600034829), 0.0, 1.0);
        }
        float curve_linear(float scene) { return pow(curve(scene), 2.4); }

        // --- and its inverse, in closed form ------------------------------
        // Exact: soft_limit inverts algebraically, so the brightest channel —
        // which the forward transform leaves as the per-channel curve alone —
        // comes back exactly.
        float inverse_curve_linear(float y) {
            float t = clamp(y, 0.0, $DISPLAY$);
            float raw = pow(t, 1.0 / 2.4) * (1.0 - 0.047111600034829) + 0.047111600034829;
            float off = raw - 0.444930201789320;
            float lim = off >= 0.0 ? (1.0 - 0.444930201789320) : 0.444930201789320;
            float knee = off >= 0.0 ? 2.4 : 1.5;
            float u = min(abs(off) / lim, 1.0);
            float uk = pow(u, knee);
            if (uk >= 1.0) { return $SCENE$; }
            float z = pow(uk / (1.0 - uk), 1.0 / knee);
            float drive = sign(off) * lim * z;
            return clamp(0.18 * exp2(clamp(drive / 0.2, -60.0, 60.0)) - 0.0015, 0.0, $SCENE$);
        }

        vec3 scene_linear(vec3 target) {
            vec3 t = clamp(target, 0.0, $DISPLAY$);
            float outMax = max(t.r, max(t.g, t.b));
            if (outMax <= 1e-10) { return vec3(0.0); }
            float norm = inverse_curve_linear(outMax);
            if (norm <= 1e-10) { return vec3(0.0); }

            // Every channel bisected as one vector, then the brightest — and
            // anything tied with it — replaced by the exact answer, so a tie
            // cannot come back as two slightly different colours.
            float gain = 0.4 * outMax / norm;
            vec3 lo = vec3(0.0);
            vec3 hi = vec3(norm);
            for (int i = 0; i < 20; i = i + 1) {
                vec3 mid = 0.5 * (lo + hi);
                vec3 fwd = vec3(
                    0.6 * curve_linear(mid.r) + gain * mid.r,
                    0.6 * curve_linear(mid.g) + gain * mid.g,
                    0.6 * curve_linear(mid.b) + gain * mid.b);
                vec3 below = step(fwd, t);          // 1 where forward < target
                lo = mix(lo, mid, below);
                hi = mix(mid, hi, below);
            }
            vec3 scene = 0.5 * (lo + hi);
            vec3 atMax = step(vec3(outMax - 1e-9), t);
            return mix(scene, vec3(norm), atMax);
        }

        vec3 linear_to_vlog(vec3 x) {
            vec3 lo = 5.6 * x + 0.125;
            vec3 hi = 0.241514 * log(max(x + 0.00873, 1e-6)) / log(10.0) + 0.598206;
            return mix(lo, hi, step(vec3(0.01), x));
        }
        kernel vec4 adapt(__sample s, float m00, float m01, float m02,
                                       float m10, float m11, float m12,
                                       float m20, float m21, float m22) {
            // Core Image hands a colour kernel working-space *linear* samples,
            // so this is display linear: a picture that has already been
            // rendered. Undo that rendering before pretending it is scene light.
            vec3 disp = clamp(s.rgb, 0.0, 1.0);
            vec3 lin = scene_linear(disp);
            vec3 vg  = vec3(
                m00 * lin.r + m01 * lin.g + m02 * lin.b,
                m10 * lin.r + m11 * lin.g + m12 * lin.b,
                m20 * lin.r + m21 * lin.g + m22 * lin.b
            );
            vec3 v = clamp(linear_to_vlog(max(vg, 0.0)), 0.0, 1.0);
            return vec4(v, s.a);
        }
        """
        // Distinct, non-overlapping placeholders. "SCENE_CEILING" contains
        // "CEILING", so substituting the shorter one first mangled the longer
        // and the kernel silently failed to compile.
        .replacingOccurrences(of: "$DISPLAY$", with: String(displayCeiling))
        .replacingOccurrences(of: "$SCENE$", with: String(sceneCeiling))

    /// Recover the code values of a picture that is *already* V-Log.
    ///
    /// Core Image decodes an image into its linear working space before any
    /// kernel sees it, which is right for a display-referred picture and wrong
    /// for a V-Log one: those numbers are already code values and must reach
    /// the cube untouched. Re-encoding cancels that decode exactly. Measured
    /// without it, a V-Log 0.42 indexed 0.147 and came back 0.0027 instead of
    /// 0.3809 — the LUT's near-black end instead of its midtone.
    static func recoverCodeValues(_ image: CIImage) -> CIImage? {
        let source = """
        kernel vec4 recover(__sample s) {
            vec3 c = clamp(s.rgb, 0.0, 1.0);
            vec3 lo = c * 12.92;
            vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
            return vec4(mix(lo, hi, step(vec3(0.0031308), c)), s.a);
        }
        """
        guard let kernel = CIColorKernel(source: source) else { return nil }
        return kernel.apply(extent: image.extent, arguments: [image])
    }

    /// Bring a LUT's output code values back into the linear working space.
    ///
    /// The other half of owning the encoding: a LUT emits finished-picture code
    /// values, and `CIColorCube` returns them untouched, so they have to be
    /// decoded before the rest of the graph — which works in linear light —
    /// sees them.
    static func decodeOutput(_ image: CIImage) -> CIImage {
        let source = """
        kernel vec4 decodeOut(__sample s) {
            vec3 c = clamp(s.rgb, 0.0, 1.0);
            vec3 lo = c / 12.92;
            vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
            return vec4(mix(lo, hi, step(vec3(0.04045), c)), s.a);
        }
        """
        guard let kernel = CIColorKernel(source: source) else { return image }
        return kernel.apply(extent: image.extent, arguments: [image]) ?? image
    }

    /// Encode a display-referred image as V-Log/V-Gamut.
    ///
    /// Returns `nil` rather than the input if the kernel will not compile or
    /// apply. Handing the picture back unchanged looks like a graceful
    /// fallback and is the opposite: the V-Log cube would then be indexed with
    /// display values, which is precisely the bug this whole file exists to
    /// prevent, and it would do it silently.
    static func encode(_ image: CIImage) -> CIImage? {
        guard let kernel = CIColorKernel(source: kernelSource) else { return nil }
        let args: [Any] = [image] + rec709ToVGamut.map { $0 as Any }
        return kernel.apply(extent: image.extent, arguments: args)
    }
}
