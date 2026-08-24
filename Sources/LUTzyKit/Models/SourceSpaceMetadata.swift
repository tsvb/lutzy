import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Asks the *file* what space it is in, before anything measures its pixels.
///
/// Measurement is a good fallback and a poor first answer: a foggy photograph
/// and a V-Log frame look alike by every statistic, and the file often simply
/// says which it is. So `.auto` reads here first and only falls through to
/// `SourceSpaceDetector` when nothing conclusive is written down.
///
/// **What is deliberately not used as evidence:** the colour-space tag. A DC-S9
/// shooting V-Log forces `[Color Space]` to sRGB, so "tagged sRGB" is exactly
/// as true of the target case as of an ordinary JPEG. Reading it as
/// display-referred would misfire on precisely the files this feature exists
/// for.
enum SourceSpaceMetadata {

    /// A conclusion together with the reason for it, so the UI can say *why* a
    /// picture was treated as V-Log rather than presenting a bare verdict.
    struct Finding: Sendable, Equatable {
        let space: SourceSpace
        let evidence: String
    }

    /// Names that mean "this file is V-Log", wherever they turn up.
    private static let vlogMarkers = ["v-log", "vlog", "v-gamut", "vgamut"]

    /// Other log formats. These are *not* V-Log, and they are not ordinary
    /// pictures either — converting one as though it were display-referred
    /// would be wrong in a different way — so they resolve to "ask", not to a
    /// verdict.
    private static let otherLogMarkers = [
        "s-log", "slog", "f-log", "flog", "logc", "log3g10", "n-log", "nlog",
        "cine-d", "c-log", "clog", "hlg"
    ]

    /// Read the file's own account of itself. `nil` means it did not say.
    static func read(_ source: ImageSource) -> Finding? {
        // A RAW is developed by CIRAWFilter into a rendered picture — it is
        // never handed to the pipeline as V-Log, whatever the sensor recorded.
        // This is a property of the decode path, so it holds regardless of tags.
        if source.kind == .raw {
            return Finding(space: .display, evidence: "RAW, developed to a rendered picture")
        }

        guard let properties = properties(of: source) else { return nil }
        let haystack = searchableText(properties)
        guard haystack.isEmpty == false else { return nil }

        if let marker = vlogMarkers.first(where: { haystack.contains($0) }) {
            return Finding(space: .vlog, evidence: "file says “\(marker)”")
        }
        if let marker = otherLogMarkers.first(where: { haystack.contains($0) }) {
            // Deliberately no verdict: a V-Log LUT cannot take this directly,
            // and the display path would be equally wrong.
            return Finding(space: .auto, evidence: "file says “\(marker)” — not V-Log; pick one")
        }
        return nil
    }

    // MARK: - Private

    private static func properties(of source: ImageSource) -> [String: Any]? {
        let imageSource: CGImageSource?
        switch source.backing {
        case .url(let url):
            imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
        case .data(let data):
            imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        }
        guard let imageSource,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any]
        else { return nil }
        return properties
    }

    /// The fields where a log format actually gets written down, lowercased and
    /// joined. Only text fields: a number cannot spell "V-Log", and sweeping
    /// every value in the dictionary would match on a coincidence sooner or
    /// later.
    private static func searchableText(_ properties: [String: Any]) -> String {
        var parts: [String] = []

        if let name = properties[kCGImagePropertyProfileName as String] as? String {
            parts.append(name)
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any]

        for (dictionary, keys) in [
            (tiff, [kCGImagePropertyTIFFImageDescription, kCGImagePropertyTIFFSoftware,
                    kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel]),
            (exif, [kCGImagePropertyExifUserComment, kCGImagePropertyExifCameraOwnerName,
                    kCGImagePropertyExifMakerNote]),
            (iptc, [kCGImagePropertyIPTCCaptionAbstract, kCGImagePropertyIPTCKeywords])
        ] as [([String: Any]?, [CFString])] {
            guard let dictionary else { continue }
            for key in keys {
                switch dictionary[key as String] {
                case let text as String: parts.append(text)
                case let list as [String]: parts.append(contentsOf: list)
                default: continue
                }
            }
        }

        return parts.joined(separator: " ").lowercased()
    }
}
