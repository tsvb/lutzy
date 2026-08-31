import Foundation
import CoreImage
import UniformTypeIdentifiers
import ImageIO

/// What LUTzy can open, and how to turn it into a `CIImage`.
///
/// **This is what is left of `ImageProcessor` after Step 7.** That type was a non-`Sendable` `final
/// class` singleton holding a `CIContext`, captured into `Task.detached` in half a dozen places —
/// the last strict-concurrency diagnostic in the module, and the second `CIContext` in the render
/// stack. Its GPU duties (`renderPreview`, `renderToNSImage`, `export`, `histogram`) moved to
/// `actor RenderEngine` across Steps 5–7; its thumbnail duties moved to `Thumbnails`, which never
/// needed a `CIContext` at all; its output vocabulary moved to `ExportFormat`.
///
/// What remains is value-level and stateless, so it is a caseless `enum` rather than an instance:
/// there is nothing left to own. `docs/PHASE2_SPEC.md` §4.5 named this as the shape to land on.
///
/// Note `RenderPipeline.developedSource` is the decoder the *render* stack uses — it re-develops
/// from the file at a chosen scale, because `CIRAWFilter` must be configured before it yields an
/// image (§4.2). `load(from:)` here is the eager, full-resolution decode the view model still does
/// once at open to learn the image's dimensions. Both read `orientedLoadOptions`, which is why that
/// lives here rather than in either of them.
enum ImageDecoder {

    // MARK: - Supported formats (single source of truth)

    /// Canonical RAW file extensions (lowercased). RAW files are demosaiced via CIRAWFilter.
    /// Add a new RAW format here and it flows to RAW detection and `supportedExtensions`.
    static let rawExtensions: Set<String> = [
        "dng", "cr2", "cr3", "nef", "arw", "orf",
        "raf", "rw2", "pef", "srw", "x3f", "raw",
    ]

    /// Canonical standard (non-RAW) image extensions (lowercased), loaded directly as a `CIImage`.
    /// Add a new standard format here and it flows to `supportedExtensions` and `supportedTypes`.
    private static let standardExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tiff", "tif", "bmp", "heic",
    ]

    /// Every extension LUTzy can open (RAW + standard, lowercased). The one definition
    /// shared by both the open panel and folder import — derive from it, never duplicate it.
    static let supportedExtensions: Set<String> = rawExtensions.union(standardExtensions)

    /// Image types for `NSOpenPanel`, derived from the canonical extension sets above.
    /// `.rawImage` covers every RAW format in a single type; standard extensions map to system UTTypes.
    static let supportedTypes: [UTType] = {
        let standardTypes = standardExtensions.compactMap { UTType(filenameExtension: $0) }
        return [.rawImage] + Set(standardTypes).sorted { $0.identifier < $1.identifier }
    }()

    // MARK: - Loading

    /// Load any supported image file as a CIImage, upright.
    static func load(from url: URL) throws -> CIImage {
        if rawExtensions.contains(url.pathExtension.lowercased()) {
            guard let output = developRAWNeutral(at: url) else {
                throw ImageError.cannotLoad(url.lastPathComponent)
            }
            return output
        }
        guard let image = CIImage(contentsOf: url, options: orientedLoadOptions) else {
            throw ImageError.cannotLoad(url.lastPathComponent)
        }
        return image
    }

    /// Load in-memory image data (Photos imports, drag-and-drop payloads) as an
    /// upright CIImage.
    static func load(from data: Data, name: String) throws -> CIImage {
        guard let image = CIImage(data: data, options: orientedLoadOptions) else {
            throw ImageError.cannotLoad(name)
        }
        return image
    }

    /// Decode options that bake a file's EXIF orientation into the returned
    /// image's geometry.
    ///
    /// `CIImage` does **not** honor the orientation tag by default, but
    /// `CIRAWFilter` does and so does the thumbnail path
    /// (`kCGImageSourceCreateThumbnailWithTransform`). Without this a portrait
    /// JPEG/HEIC previewed *and exported* on its side while its filmstrip
    /// thumbnail stood upright. Every non-RAW decode in the app goes through
    /// these options so all three paths agree.
    ///
    /// Computed rather than stored: a `static let` of `[CIImageOption: Any]` is shared mutable state
    /// as far as the compiler is concerned (`Any` is not `Sendable`), which is an error under Swift
    /// 6. Rebuilding a one-entry dictionary is free next to decoding an image.
    static var orientedLoadOptions: [CIImageOption: Any] { [.applyOrientationProperty: true] }

    /// Develop a RAW/DNG at **neutral / default `CIRAWFilter` settings** — no
    /// user develop adjustments are applied.
    ///
    /// This defines the "neutral baseline" RAW render for the two callers that
    /// take it: the eager decode in `AppViewModel.load`, and LUT derivation
    /// (`RecipeExtractor`). Sharing it is what keeps derive independent of any
    /// user-adjustable develop setting — derive fits its cube against exactly
    /// this render and cannot see a document.
    ///
    /// **It is not the only construction of a neutral RAW.** The render stack
    /// does not call this at all: `RenderPipeline.rawFilter(for:)` builds its
    /// own `CIRAWFilter`, because it must also handle a `.data` backing (a
    /// Photos import has no URL to pass, and this signature takes one). The two
    /// agree only because `RAWDevelopSettings.neutral` sets nothing — an
    /// agreement, not a structural guarantee, and pinned by a single test that
    /// skips without a local DNG and covers the URL backing only. Do not read
    /// this comment as saying the derive baseline *cannot* drift from the
    /// render path; it says the two callers here cannot drift from each other.
    ///
    /// Returns `nil` if the file can't be decoded.
    static func developRAWNeutral(at url: URL) -> CIImage? {
        return CIRAWFilter(imageURL: url)?.outputImage
    }
}

// MARK: - Extent

extension CGRect {
    /// Whether this extent can actually be turned into a pixel buffer.
    ///
    /// Rejects empty, null, and — the one that bites — **infinite** extents.
    /// `CGRect.infinite` is built from `greatestFiniteMagnitude`, not `inf`, so
    /// an `isFinite` check on its width passes while `Int(width)` traps at
    /// runtime. Generator-backed images (`CIImage(color:)` and friends) have
    /// exactly that extent, so any code path that might meet one has to test
    /// `isInfinite` explicitly.
    var isRasterizable: Bool {
        !isInfinite && !isNull && !isEmpty
            && width.isFinite && height.isFinite
            && width >= 1 && height >= 1
    }
}

// MARK: - Errors

enum ImageError: LocalizedError, Sendable {
    case cannotLoad(String)
    case processingFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .cannotLoad(let name): return "Cannot load \(name)"
        case .processingFailed: return "Image processing failed"
        case .exportFailed: return "Export failed"
        }
    }
}
