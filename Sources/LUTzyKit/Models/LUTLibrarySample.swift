import Foundation
import CoreGraphics
import ImageIO
import AppKit

struct LUTLibrarySample: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let note: String
    let filename: String
    let colorProfile: String
    let provenance: String
    let sourceSpace: SourceSpace

    var url: URL? {
        Bundle.module.url(
            forResource: (filename as NSString).deletingPathExtension,
            withExtension: (filename as NSString).pathExtension
        )
    }

    var imageSource: ImageSource? {
        guard let url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
        else { return nil }
        return ImageSource(url: url, nativeExtent: CGSize(width: width, height: height))
    }

    static let all: [LUTLibrarySample] = [
        LUTLibrarySample(
            id: "portrait", name: "Skin Tone", note: "Portrait and neutral fabric",
            filename: "portrait-skin.png", colorProfile: "Embedded sRGB IEC61966-2.1",
            provenance: "Generated specifically for LUTzy; bundled project asset",
            sourceSpace: .display
        ),
        LUTLibrarySample(
            id: "outdoor", name: "Sky & Foliage", note: "Blue, cyan, and varied greens",
            filename: "outdoor-foliage.png", colorProfile: "Embedded sRGB IEC61966-2.1",
            provenance: "Generated specifically for LUTzy; bundled project asset",
            sourceSpace: .display
        ),
        LUTLibrarySample(
            id: "mixed", name: "Mixed Light", note: "Daylight, tungsten, and skin",
            filename: "indoor-mixed-light.png", colorProfile: "Embedded sRGB IEC61966-2.1",
            provenance: "Generated specifically for LUTzy; bundled project asset",
            sourceSpace: .display
        ),
        LUTLibrarySample(
            id: "saturated", name: "Colour & Neutrals", note: "Full hues with white, grey, black",
            filename: "saturated-neutrals.png", colorProfile: "Embedded sRGB IEC61966-2.1",
            provenance: "Generated specifically for LUTzy; bundled project asset",
            sourceSpace: .display
        ),
    ]
}

enum LUTGalleryMetadata {
    /// Tags intended for people to browse. `input:*` is render-pipeline
    /// metadata and has its own dedicated Input field, so surfacing it as a
    /// discovery category would crowd out descriptive style tags.
    static func browsableTags(typed: [String], measured: [String]) -> [String] {
        let typed = typed.filter { $0.hasPrefix("input:") == false }.sorted()
        let measured = measured
            .filter { $0.hasPrefix("input:") == false && typed.contains($0) == false }
            .sorted()
        return typed + measured
    }

    static func visibleTags(typed: [String], measured: [String], limit: Int = 3) -> [String] {
        guard limit > 0 else { return [] }
        return Array(browsableTags(typed: typed, measured: measured).prefix(limit))
    }
}

struct LUTLibraryRenderPair {
    let original: NSImage
    let graded: NSImage
}
