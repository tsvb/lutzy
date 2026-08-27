import Foundation

/// Evidence-first classification for the user's multi-site download folder.
/// Brand, Source, and Input Profile stay independent so a maker's multi-camera
/// pack does not turn camera-log folders into LUT brands.
public enum DownloadedLUTClassifier {
    public struct Classification: Sendable, Equatable {
        public let sourceID: String
        public let sourceFolder: String
        public let brand: String
        public let destinationSubpath: String
        public let inputProfile: String
        public let tags: [String]
    }

    public static func classify(relativePath: String) -> Classification {
        let components = relativePath.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let top = components.first ?? "Downloaded LUTs"
        let fileName = normalizedCubeName(components.last ?? "Unnamed.cube")
        let lowerTop = top.localizedLowercase

        if lowerTop.hasPrefix("cinecolor_") || ["beauty", "interview"].contains(lowerTop) {
            let look = cinecolorLookName(top)
            return Classification(
                sourceID: "cinecolor",
                sourceFolder: "CINECOLOR",
                brand: "CINECOLOR",
                destinationSubpath: "\(look)/\(fileName)",
                inputProfile: "Unknown",
                tags: semanticTags(path: relativePath, base: ["創意風格"])
            )
        }

        if top == "SmallHD+LUT+Pack_Movie+Looks+2" {
            let camera = components.dropFirst().dropLast().first ?? "General"
            return Classification(
                sourceID: "smallhd-movie-looks-2",
                sourceFolder: "SmallHD Movie Looks 2",
                brand: "SmallHD",
                destinationSubpath: "\(cleanComponent(camera))/\(fileName)",
                inputProfile: LUTInputProfileInference.profile(relativePath: relativePath),
                tags: semanticTags(path: relativePath, base: ["完成色", "電影風格"])
            )
        }

        if top == "Print+Film+Emulation+LUTs" {
            let lowered = fileName.localizedLowercase
            let brand = lowered.contains("fujifilm") ? "Fujifilm"
                : lowered.contains("kodak") ? "Kodak" : "Film Emulation"
            return Classification(
                sourceID: "print-film-emulation",
                sourceFolder: "Print Film Emulation",
                brand: brand,
                destinationSubpath: fileName,
                inputProfile: "Display / Rec.709",
                tags: semanticTags(path: relativePath, base: ["底片模擬", "列印底片"])
            )
        }

        let package: (sourceID: String, sourceFolder: String, brand: String, baseTags: [String])
        switch top {
        case "FREE Film Tone LUTs from FilterGrade":
            package = ("filtergrade-film-tone", "FilterGrade Film Tone", "FilterGrade", ["底片模擬"])
        case "FG Free Cine LUTs Pack v2":
            package = ("filtergrade-free-cine-v2", "FilterGrade Free Cine v2", "FilterGrade", ["電影風格"])
        case "PB - 17 FREE LUTs":
            package = ("premiumbeat-wanderlust", "PremiumBeat Wanderlust", "PremiumBeat", ["創意風格"])
        case "Cine LUTs Free":
            package = ("cine-luts-free", "Cine LUTs Free", "Cine LUTs Free", ["電影風格"])
        case "LUTS (FREEMIUM 14)":
            package = ("freemium-14", "FREEMIUM 14", "FREEMIUM 14", ["創意風格"])
        case "FREE Warm Tone LUTs":
            package = ("free-warm-tone", "Warm Tone LUTs", "Warm Tone LUTs", ["暖調"])
        case "Free LUTs for Super 8 Footage":
            package = ("super8-footage", "Super 8 Footage", "Super 8 LUTs", ["底片模擬", "復古"])
        case "hollywood-lut-color-pack":
            package = ("hollywood-lut-color-pack", "Hollywood LUT Color Pack", "Hollywood LUT Color Pack", ["電影風格", "電影參考"])
        default:
            package = ("downloaded-unresolved", cleanComponent(top), cleanComponent(top), ["創意風格"])
        }
        return Classification(
            sourceID: package.sourceID,
            sourceFolder: package.sourceFolder,
            brand: package.brand,
            destinationSubpath: fileName,
            inputProfile: LUTInputProfileInference.profile(relativePath: relativePath),
            tags: semanticTags(path: relativePath, base: package.baseTags)
        )
    }

    private static func normalizedCubeName(_ value: String) -> String {
        let stem = (value as NSString).deletingPathExtension
        return "\(cleanComponent(stem)).cube"
    }

    private static func cleanComponent(_ value: String) -> String {
        value.replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cinecolorLookName(_ top: String) -> String {
        let raw: String
        if top.localizedLowercase.hasPrefix("cinecolor_") {
            raw = String(top.dropFirst("CINECOLOR_".count))
        } else {
            raw = top
        }
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "_ "))
            .replacingOccurrences(of: "_", with: " ")
        switch cleaned {
        case "DESTURATED": return "DESATURATED"
        case "DAY FOR NIGHT LUT": return "DAY FOR NIGHT"
        default: return cleaned.isEmpty ? "GENERAL" : cleaned
        }
    }

    private static func semanticTags(path: String, base: [String]) -> [String] {
        let value = path.localizedLowercase
        var tags = Set(base)
        if containsAny(value, ["monochrome", "black_white", "black-white", "bw ", "bw_", "classic_noir", "noir"]) {
            tags.insert("黑白")
        }
        if containsAny(value, ["film", "65mm", "35mm", "super 8", "kodak", "kodachrome", "ektachrome", "portra", "fujifilm", "velvia", "astia"]) {
            tags.insert("底片模擬")
        }
        if containsAny(value, ["1970", "1980", "1990", "vintage", "silent_film", "grindhouse"]) {
            tags.insert("復古")
        }
        if containsAny(value, ["a24", "art_house", "blockbuster", "documentary", "drama", "fight_club", "horror", "jaws", "mad_max", "royal_tenenbaums", "se7en", "social_network", "western", "hollywood"]) {
            tags.insert("電影風格")
        }
        if containsAny(value, ["beauty", "interview", "skin", "wedding"]) { tags.insert("人像") }
        if containsAny(value, ["warm", "gold", "golden_hour", "autumn"] ) { tags.insert("暖調") }
        if containsAny(value, ["cool", "cold", "winter", "faded blues"] ) { tags.insert("冷調") }
        if containsAny(value, ["teal_and_orange", "teal&orange", "tealorange", "orange teal"] ) { tags.insert("青橙") }
        if containsAny(value, ["bleach_bypass", "bleach-bypass"] ) { tags.insert("漂白旁路") }
        if containsAny(value, ["cross_process", "cross-process"] ) { tags.insert("交叉沖印") }
        if containsAny(value, ["low_con", "low contrast"] ) { tags.insert("低對比") }
        if containsAny(value, ["desaturated", "desturated", "dull", "faded"] ) { tags.insert("低飽和") }
        if containsAny(value, ["soft", "dream"] ) { tags.insert("柔和") }
        if containsAny(value, ["day_for_night", "day for night"] ) { tags.insert("日轉夜") }
        if containsAny(value, ["duotone"] ) { tags.insert("雙色調") }
        if containsAny(value, ["thermal", "chromatic"] ) { tags.insert("特效") }
        if containsAny(value, ["bright", "vibrant", "rich"] ) { tags.insert("鮮明") }
        if containsAny(value, ["finishing", "clean raw", "basic"] ) { tags.insert("中性") }
        if tags.isEmpty { tags.insert("創意風格") }
        return tags.sorted()
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains(where: value.contains)
    }
}
