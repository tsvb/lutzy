import AppKit
import UniformTypeIdentifiers

/// What a drag onto the preview canvas can carry, and how to get files out of it.
///
/// Three senders matter, and they put three different things on the pasteboard:
///
/// - **Finder** writes file URLs. The cheap case; the URLs are the files.
/// - **Photos** writes *file promises*. Nothing exists on disk until the receiver asks for it — Photos
///   exports the current version of each picture (its original if unedited) into a directory the
///   receiver names, and the filename and extension come from Photos, so extension-based RAW
///   detection sees the same `.dng` or `.arw` it would in a folder. This is why the old
///   `dropDestination(for: URL.self)` never fired for a Photos drag: there was no URL to hand over.
/// - **Browsers and image editors** often write only bitmap data (`public.tiff`, `public.png`). That
///   opens through the same bytes path a Photos-picker import uses.
///
/// `NSFilePromiseReceiver` is not `Sendable`, so a `.promises` payload is created and consumed on
/// the main actor; only the URLs it produces travel anywhere else.
@MainActor
enum ImageDrop {

    enum Payload {
        case urls([URL])
        case promises([NSFilePromiseReceiver])
        case image(data: Data, name: String)
    }

    /// The content types the drop modifier advertises. SwiftUI only offers a drop whose item
    /// providers carry one of these, so the file-promise identifiers have to be listed explicitly:
    /// they conform to nothing public.
    static let acceptedTypes: [UTType] = {
        let promise = NSFilePromiseReceiver.readableDraggedTypes.compactMap { UTType($0) }
        return [.fileURL, .image] + promise
    }()

    /// Bitmap types worth opening straight from the pasteboard, best first.
    private static let imageDataTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]

    static func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        payload(from: pasteboard) != nil
    }

    /// Classify a pasteboard. **Promises win over URLs**, measured rather than assumed: a Photos
    /// drag also writes a `public.file-url`, and it points at a small derivative inside the Photos
    /// library (`…_4_5005_c.jpeg`, sandbox-inaccessible from a bundled app) while the promise
    /// delivers the 8 MB original under its own name. Finder writes no promise, so its URLs are
    /// still read directly. Both win over bitmap data, which is usually a preview.
    static func payload(from pasteboard: NSPasteboard) -> Payload? {
        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            return .promises(receivers)
        }
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL],
           !urls.isEmpty {
            return .urls(urls)
        }
        for type in imageDataTypes {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                let ext = UTType(type.rawValue)?.preferredFilenameExtension ?? "img"
                return .image(data: data, name: "Dropped Image.\(ext)")
            }
        }
        return nil
    }

    // MARK: - File promises

    /// Ask every receiver for its files and wait for all of them. Files land in a fresh directory
    /// from `makeDropDirectory()`; the URLs come back in arrival order, failures dropped.
    ///
    /// Completion is counted against `fileTypes`, one entry per promised file. Not `fileNames`:
    /// Photos leaves that empty until the file has actually been written (observed on a real
    /// drag — `fileNames=[] fileTypes=["public.jpeg"]`), so counting names would wait for nothing
    /// and report nothing. A receiver that promised nothing contributes nothing and is not waited on.
    static func receive(_ receivers: [NSFilePromiseReceiver], into directory: URL) async -> [URL] {
        let expected = receivers.reduce(0) { $0 + max($1.fileTypes.count, $1.fileNames.count) }
        guard expected > 0 else { return [] }

        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        let stream = AsyncStream<URL?> { continuation in
            for receiver in receivers {
                receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: queue) { url, error in
                    continuation.yield(error == nil ? url : nil)
                }
            }
        }

        var urls: [URL] = []
        var received = 0
        for await url in stream {
            if let url { urls.append(url) }
            received += 1
            if received == expected { break }
        }
        return urls
    }

    // MARK: - Where promised files live

    /// Every drop gets its own directory under the app's temp folder; the name is the one Photos
    /// gave the file, so nothing is invented.
    private static var dropsRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LUTzy Drops", isDirectory: true)
    }

    static func makeDropDirectory() throws -> URL {
        let url = dropsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Delete every earlier drop directory. Called once the files of a new drop have been adopted,
    /// so the collection never points at a file this removes.
    static func purgeDropDirectories(except keep: URL?) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dropsRoot, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.standardizedFileURL != keep?.standardizedFileURL {
            try? fm.removeItem(at: entry)
        }
    }
}
