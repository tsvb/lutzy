import Foundation

/// OKLab, for the places colour has to be moved perceptually rather than
/// numerically — saturation above all, where scaling RGB shifts hue and
/// scaling chroma does not.
///
/// Shared by the profiler (which measures looks) and the editor (which makes
/// them), so a saturation the editor applies and a saturation the profiler
/// reports are the same quantity.
enum OKLab {

    /// Linear Rec.709 → OKLab.
    static func fromLinear(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let l = cbrt(0.4122214708 * rgb.x + 0.5363325363 * rgb.y + 0.0514459929 * rgb.z)
        let m = cbrt(0.2119034982 * rgb.x + 0.6806995451 * rgb.y + 0.1073969566 * rgb.z)
        let s = cbrt(0.0883024619 * rgb.x + 0.2817188376 * rgb.y + 0.6299787005 * rgb.z)
        return SIMD3<Float>(
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    /// OKLab → linear Rec.709. May return negatives for colours outside the
    /// gamut; the caller decides what to do about them.
    static func toLinear(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        let l = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
        let m = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
        let s = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
        let l3 = l * l * l, m3 = m * m * m, s3 = s * s * s
        return SIMD3<Float>(
             4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
            -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
            -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        )
    }

    static func srgbToLinear(_ c: Float) -> Float {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func linearToSRGB(_ c: Float) -> Float {
        c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }
}
