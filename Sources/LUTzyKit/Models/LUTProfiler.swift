import Foundation

/// What a LUT *does*, in the terms someone would tag it by.
///
/// Folders stop scaling around a hundred files: a LUT is warm **and** contrasty
/// **and** wants V-Log, and it can only live in one folder. Most of what one
/// would type is measurable, and measuring it means a hundred files get
/// described consistently instead of according to whoever named them.
///
/// The maths here mirrors `lutcraft.tags` step for step, on probes exported
/// from it (`LUTProbes`), so the app and the offline tools agree about what a
/// file is. `lutcheck` compares the tags this produces against lutcraft's own
/// for every LUT on the machine.
struct LUTMetrics: Codable, Equatable, Sendable {
    var contrast: Double
    var saturation: Double
    var monoSpread: Double
    var blackLevel: Double
    var whiteLevel: Double
    var shadowChroma: Double
    var highlightChroma: Double
    var shadowHue: Double
    var highlightHue: Double
    var splitAngle: Double
    var skinRatio: Double
}

enum LUTProfiler {

    // MARK: - Measuring

    static func measure(_ lut: CubeLUT) -> LUTMetrics {
        let isVLog = lut.inputSpace == .vlog
        let ramp = isVLog ? LUTProbes.vlogRamp : LUTProbes.displayRamp
        let skin = isVLog ? LUTProbes.vlogSkin : LUTProbes.displaySkin
        let swatches = isVLog ? LUTProbes.vlogSwatches : LUTProbes.displaySwatches
        // For a display LUT the probes are their own reference: the input is
        // already a rendered picture, so "what would this look like ungraded"
        // is the input itself.
        let rampReference = isVLog ? LUTProbes.vlogRampReference : LUTProbes.displayRamp
        let skinReference = isVLog ? LUTProbes.vlogSkinReference : LUTProbes.displaySkin
        let swatchReference = isVLog ? LUTProbes.vlogSwatchReference : LUTProbes.displaySwatches

        let rampOut = lut.sample(ramp)
        let rampLab = oklab(ofSRGB: rampOut)
        let lightness = stride(from: 0, to: rampLab.count, by: 3).map { rampLab[$0] }

        // Contrast: how much lightness separates the middle of the ramp,
        // against a neutral rendering of the very same inputs.
        let plainLab = oklab(ofSRGB: rampReference)
        let plain = stride(from: 0, to: plainLab.count, by: 3).map { plainLab[$0] }
        let contrast = Double(lightness[47] - lightness[16]) / Swift.max(Double(plain[47] - plain[16]), 1e-6)

        let swatchLab = oklab(ofSRGB: lut.sample(swatches))
        let swatchInLab = oklab(ofSRGB: swatchReference)
        let saturation = median(chroma(swatchLab)) / Swift.max(median(chroma(swatchInLab)), 1e-6)

        // Neutrals: the reference render leaves grey grey, so any chroma left
        // on the ramp is the LUT's own tint.
        let shadow = Array(rampLab[(8 * 3)..<(8 * 3 + 3)])
        let highlight = Array(rampLab[((64 - 8) * 3)..<((64 - 8) * 3 + 3)])
        let shadowChroma = Double(hypot(shadow[1], shadow[2]))
        let highlightChroma = Double(hypot(highlight[1], highlight[2]))
        let shadowHue = degrees(shadow[2], shadow[1])
        let highlightHue = degrees(highlight[2], highlight[1])
        let split = abs((shadowHue - highlightHue + 180).truncatingRemainder(dividingBy: 360) - 180)

        // Black is asked for at the LUT's own black point: V-Log black sits at
        // 0.125, and asking below it says nothing about lifted shadows.
        let floor: Float = isVLog ? 0.125 : 0.0
        let black = mean(lut.sample([floor, floor, floor]))
        let white = mean(lut.sample([1, 1, 1]))

        let skinLab = oklab(ofSRGB: lut.sample(skin))
        let skinRefLab = oklab(ofSRGB: skinReference)
        let skinRatio = median(chroma(skinLab)) / Swift.max(median(chroma(skinRefLab)), 1e-6)

        return LUTMetrics(
            contrast: round(contrast, 3),
            saturation: round(saturation, 3),
            monoSpread: round(lut.monoSpread, 6),
            blackLevel: round(black, 4),
            whiteLevel: round(white, 4),
            shadowChroma: round(shadowChroma, 4),
            highlightChroma: round(highlightChroma, 4),
            shadowHue: round(shadowHue, 1),
            highlightHue: round(highlightHue, 1),
            splitAngle: round(split, 1),
            skinRatio: round(skinRatio, 3)
        )
    }

    // MARK: - Naming what was measured

    /// Turn the measurements into the words one would have typed.
    ///
    /// The vocabulary is `lutcraft`'s, in Chinese, because that is what the
    /// user tags by and a translated second vocabulary would just mean two
    /// words for one thing.
    static func autoTags(_ m: LUTMetrics, inputSpace: LUTInputSpace) -> [String] {
        var tags: Set<String> = ["input:\(inputSpace == .vlog ? "vlog" : "display")"]

        if m.monoSpread < 1e-6 {
            tags.insert("黑白")
        } else {
            if m.saturation >= 1.15 { tags.insert("高飽和") }
            else if m.saturation <= 0.85 { tags.insert("低飽和") }
            if m.saturation <= 0.5 { tags.insert("接近去彩") }
            if m.skinRatio <= 0.9 { tags.insert("膚色收斂") }
            else if m.skinRatio >= 1.2 { tags.insert("膚色濃") }
            // A tint that survives on neutrals is what warm and cool mean.
            if m.shadowChroma > 0.01 || m.highlightChroma > 0.01 {
                let hue = m.highlightChroma >= m.shadowChroma ? m.highlightHue : m.shadowHue
                if (20.0...110.0).contains(hue) { tags.insert("暖調") }
                else if (170.0...290.0).contains(hue) { tags.insert("冷調") }
            }
            if m.splitAngle >= 40.0 && min(m.shadowChroma, m.highlightChroma) > 0.004 {
                tags.insert("分離調色")
            }
        }

        if m.contrast >= 1.15 { tags.insert("高對比") }
        else if m.contrast <= 0.9 { tags.insert("低對比") }
        if m.blackLevel >= 0.04 { tags.insert("霧面") }
        if m.whiteLevel <= 0.93 { tags.insert("高光收斂") }
        return tags.sorted()
    }

    // MARK: - Small numerics

    /// OKLab of sRGB **code values** — the LUT's output is a finished picture,
    /// so it is decoded before being measured perceptually.
    private static func oklab(ofSRGB codes: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: codes.count)
        for i in stride(from: 0, to: codes.count, by: 3) {
            let r = srgbToLinear(min(max(codes[i], 0), 1))
            let g = srgbToLinear(min(max(codes[i + 1], 0), 1))
            let b = srgbToLinear(min(max(codes[i + 2], 0), 1))
            let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            out[i]     = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
            out[i + 1] = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
            out[i + 2] = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        }
        return out
    }

    private static func srgbToLinear(_ c: Float) -> Float {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func chroma(_ lab: [Float]) -> [Double] {
        stride(from: 0, to: lab.count, by: 3).map { Double(hypot(lab[$0 + 1], lab[$0 + 2])) }
    }

    private static func median(_ values: [Double]) -> Double {
        guard values.isEmpty == false else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        // NumPy's median averages the two middle values on an even count, and
        // these probe sets are even-sized.
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func mean(_ values: [Float]) -> Double {
        values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func degrees(_ y: Float, _ x: Float) -> Double {
        let angle = Double(atan2(y, x)) * 180 / .pi
        return angle < 0 ? angle + 360 : angle
    }

    private static func round(_ value: Double, _ places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (value * factor).rounded() / factor
    }
}
