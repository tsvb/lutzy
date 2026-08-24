import Foundation
import AppKit
import ImageIO

/// Filmstrip and file-browser thumbnails.
///
/// **Not part of the render stack, and deliberately not on `RenderEngine`.** These go through
/// `CGImageSource`, which reads a file's embedded preview — for a RAW that is the camera's own JPEG,
/// which is why a 30 MB DNG thumbnails in milliseconds without ever being demosaiced. There is no
/// `CIImage`, no filter graph and no `CIContext` anywhere in here, so routing them through the
/// engine would buy nothing and cost something: thumbnails for a folder would then queue behind
/// every preview render on the actor's single execution context.
///
/// What Step 7 *did* change is what they hang off. Both `ImageCollection` call sites captured
/// `ImageProcessor.shared` — a non-`Sendable` class — into a `Task.detached`, which is the hazard
/// `docs/PHASE2_SPEC.md` §2 flags and the thing that kept strict concurrency red. These are
/// stateless statics on a caseless `enum`, so nothing crosses the boundary but a `URL` or a `Data`.
///
/// `NSImage` is the return type because the filmstrip is AppKit and that is where these land. It is
/// not `Sendable`, so the *call* belongs off the main actor and the result is published on it —
/// which is exactly what `ImageCollection` does.
enum Thumbnails {

    /// The filmstrip's thumbnail size, in pixels on the long edge.
    static let defaultMaxPixelSize = 240

    /// Generate on the cooperative background executor and transfer the newly-created AppKit image
    /// to the caller. The `sending` result expresses the ownership transfer without claiming that
    /// `NSImage` itself is `Sendable`, which it explicitly is not.
    static func generateOffMain(
        from url: URL,
        maxPixelSize: Int = defaultMaxPixelSize
    ) async -> sending NSImage? {
        generate(from: url, maxPixelSize: maxPixelSize)
    }

    /// Generate a thumbnail from a file, using the embedded preview where there is one.
    static func generate(from url: URL, maxPixelSize: Int = defaultMaxPixelSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    /// Generate a thumbnail from in-memory data (Photos imports).
    static func generate(from data: Data, maxPixelSize: Int = defaultMaxPixelSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    private static func thumbnail(from source: CGImageSource, maxPixelSize: Int) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            // Bakes the EXIF orientation into the thumbnail, matching
            // `ImageDecoder.orientedLoadOptions` on the canvas side. Without it the filmstrip
            // contradicts the preview for every portrait JPEG.
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
