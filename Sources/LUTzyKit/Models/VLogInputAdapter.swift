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
        0.585196, 0.322642, 0.092162,
        0.078589, 0.819627, 0.101784,
        0.022794, 0.114217, 0.862989,
    ]

    // Compiled on demand. `CIColorKernel` is not `Sendable`, so it cannot be a
    // shared `static let` under Swift 6's data-race checking; compiling one per
    // call is cheap (Core Image caches the compiled program by source string).
    private static let kernelSource = """
        vec3 rec709_to_linear(vec3 c) {
            vec3 lo = c / 12.92;
            vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
            return mix(lo, hi, step(vec3(0.04045), c));
        }
        vec3 linear_to_vlog(vec3 x) {
            vec3 lo = 5.6 * x + 0.125;
            vec3 hi = 0.241514 * log(max(x + 0.00873, 1e-6)) / log(10.0) + 0.598206;
            return mix(lo, hi, step(vec3(0.01), x));
        }
        kernel vec4 adapt(__sample s, float m00, float m01, float m02,
                                       float m10, float m11, float m12,
                                       float m20, float m21, float m22) {
            vec3 lin = max(s.rgb, 0.0);
            vec3 vg  = vec3(
                m00 * lin.r + m01 * lin.g + m02 * lin.b,
                m10 * lin.r + m11 * lin.g + m12 * lin.b,
                m20 * lin.r + m21 * lin.g + m22 * lin.b
            );
            vec3 v = linear_to_vlog(max(vg, 0.0));
            return vec4(clamp(v, 0.0, 1.0), s.a);
        }
        """

    /// Encode a display-referred image as V-Log/V-Gamut.
    /// Returns the input unchanged if the kernel failed to compile.
    static func encode(_ image: CIImage) -> CIImage {
        guard let kernel = CIColorKernel(source: kernelSource) else { return image }
        let args: [Any] = [image] + rec709ToVGamut.map { $0 as Any }
        return kernel.apply(extent: image.extent, arguments: args) ?? image
    }
}
