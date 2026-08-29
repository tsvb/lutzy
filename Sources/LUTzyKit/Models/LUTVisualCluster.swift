import Foundation

/// One explainable, mutually-exclusive visual family for Library discovery.
///
/// This is deliberately a Collection seed rather than Brand, Source, Folder,
/// or an ordinary Tag: it groups transforms by measured appearance across all
/// of those authored dimensions without changing where a LUT came from.
enum LUTVisualCluster: String, Codable, CaseIterable, Sendable {
    case neutralVivid = "中性濃豔"
    case neutralNatural = "中性自然"
    case neutralFlat = "中性平淡"
    case warmBrown = "暖褐／咖啡"
    case yellowGreen = "黃綠"
    case cyanGreen = "青綠"
    case coolBlue = "藍冷"
    case purpleMagenta = "紫洋紅"
    case warmRed = "紅暖"
    case monochrome = "黑白"

    /// Bumped when `classify` would move existing LUTs. `LUTCatalog` reseeds a
    /// Library whose stored seed predates this, so a rule change reaches an
    /// installed corpus instead of applying only to newly imported LUTs.
    static let seedVersion = 2

    /// Below this the neutral axis carries no tint a viewer would name.
    private static let tintFloor = 0.006

    /// The saturation classes `LUTProfiler.autoTags` already tags by, reused so
    /// a Collection and its members' Tags cannot disagree.
    private static let vividSaturation = 1.15
    private static let flatSaturation = 0.85

    /// Shared so a reseed can name the Collection an *earlier* rule version
    /// created, which no current case spells any more.
    static let collectionPrefix = "色調 · "

    static func collectionName(family: String) -> String { collectionPrefix + family }

    var collectionName: String { Self.collectionName(family: rawValue) }

    /// Parse a stored `visual-cluster-v<n>:<family>` seed marker.
    static func parseSeed(_ seed: String) -> (version: Int, family: String)? {
        let parts = seed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].hasPrefix("visual-cluster-v"),
              let version = Int(parts[0].dropFirst("visual-cluster-v".count))
        else { return nil }
        return (version, String(parts[1]))
    }

    static func seedMarker(_ cluster: LUTVisualCluster) -> String {
        "visual-cluster-v\(seedVersion):\(cluster.rawValue)"
    }

    static func classify(_ metrics: LUTMetrics) -> LUTVisualCluster {
        if metrics.monoSpread < 1e-6 { return .monochrome }

        // Strength stays the stronger end's chroma: it is what "this grey is
        // visibly tinted" means, and keeping it decides the untinted case the
        // same way it always has.
        let strength = Swift.max(metrics.shadowChroma, metrics.highlightChroma)
        guard strength >= tintFloor else {
            // An untinted neutral is not one family. The corpus spreads it
            // evenly over every saturation class, so name it by saturation,
            // which stays measurable when the neutral axis carries no chroma.
            if metrics.saturation >= vividSaturation { return .neutralVivid }
            if metrics.saturation <= flatSaturation { return .neutralFlat }
            return .neutralNatural
        }

        switch tintHue(metrics) {
        case 20..<80: return .warmBrown
        case 80..<160: return .yellowGreen
        case 160..<220: return .cyanGreen
        case 220..<290: return .coolBlue
        case 290..<350: return .purpleMagenta
        default: return .warmRed
        }
    }

    /// The hue of the cast, read from both ends of the ramp rather than from
    /// whichever end measured stronger.
    ///
    /// Shadows and highlights are two samples of one tint, so a single end
    /// carries a single end's noise — and deciding a family on which end won a
    /// chroma comparison puts a family boundary on a hairline: two LUTs whose
    /// ends differ by 0.0002 would land in different Collections. Adding the
    /// ends as vectors uses both measurements and weights each by how much
    /// tint it actually carries.
    ///
    /// Opposed ends are the exception. A teal-shadow/orange-highlight grade is
    /// split-toned, not untinted, and summing it would cancel a tint the
    /// viewer plainly sees; there the stronger end is the cast.
    private static func tintHue(_ metrics: LUTMetrics) -> Double {
        let shadow = vector(chroma: metrics.shadowChroma, hue: metrics.shadowHue)
        let highlight = vector(chroma: metrics.highlightChroma, hue: metrics.highlightHue)
        let agree = shadow.a * highlight.a + shadow.b * highlight.b > 0
        guard agree else {
            return metrics.highlightChroma >= metrics.shadowChroma
                ? normalizedHue(metrics.highlightHue)
                : normalizedHue(metrics.shadowHue)
        }
        return degrees(shadow.b + highlight.b, shadow.a + highlight.a)
    }

    private static func vector(chroma: Double, hue: Double) -> (a: Double, b: Double) {
        let radians = normalizedHue(hue) * .pi / 180
        return (chroma * cos(radians), chroma * sin(radians))
    }

    private static func normalizedHue(_ hue: Double) -> Double {
        let wrapped = hue.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    private static func degrees(_ y: Double, _ x: Double) -> Double {
        let angle = atan2(y, x) * 180 / .pi
        return angle < 0 ? angle + 360 : angle
    }
}
