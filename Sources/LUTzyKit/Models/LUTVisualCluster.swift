import Foundation

/// One explainable, mutually-exclusive visual family for Library discovery.
///
/// This is deliberately a Collection seed rather than Brand, Source, Folder,
/// or an ordinary Tag: it groups transforms by measured appearance across all
/// of those authored dimensions without changing where a LUT came from.
enum LUTVisualCluster: String, Codable, CaseIterable, Sendable {
    case nearNeutral = "近中性"
    case warmBrown = "暖褐／咖啡"
    case yellowGreen = "黃綠"
    case cyanGreen = "青綠"
    case coolBlue = "藍冷"
    case purpleMagenta = "紫洋紅"
    case warmRed = "紅暖"
    case monochrome = "黑白"

    static let seedVersion = 1

    var collectionName: String { "色調 · \(rawValue)" }

    static func classify(_ metrics: LUTMetrics) -> LUTVisualCluster {
        if metrics.monoSpread < 1e-6 { return .monochrome }

        let chroma: Double
        let hue: Double
        if metrics.highlightChroma >= metrics.shadowChroma {
            chroma = metrics.highlightChroma
            hue = metrics.highlightHue
        } else {
            chroma = metrics.shadowChroma
            hue = metrics.shadowHue
        }
        guard chroma >= 0.006 else { return .nearNeutral }

        let normalizedHue = hue.truncatingRemainder(dividingBy: 360) + (hue < 0 ? 360 : 0)
        switch normalizedHue {
        case 20..<80: return .warmBrown
        case 80..<160: return .yellowGreen
        case 160..<220: return .cyanGreen
        case 220..<290: return .coolBlue
        case 290..<350: return .purpleMagenta
        default: return .warmRed
        }
    }
}
