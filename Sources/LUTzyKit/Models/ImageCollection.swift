import Foundation
import AppKit

/// Manages a collection of imported images with async thumbnail generation.
@MainActor
final class ImageCollection: ObservableObject {

    struct Item: Identifiable {
        let id: UUID
        let url: URL?               // nil for Photos-imported items
        let displayName: String
        var thumbnail: NSImage?
        let imageData: Data?         // for PhotosPicker items without a URL
        /// Relative directory from the source-folder root ("" for top level).
        /// Drives the grouped file browser; empty for Photos imports.
        var subfolder: String = ""

        init(
            id: UUID = UUID(), url: URL?, displayName: String, thumbnail: NSImage? = nil,
            imageData: Data?, subfolder: String = ""
        ) {
            self.id = id
            self.url = url
            self.displayName = displayName
            self.thumbnail = thumbnail
            self.imageData = imageData
            self.subfolder = subfolder
        }
    }

    @Published var items: [Item] = []
    @Published var selectedIndex: Int = 0
    @Published var isActive: Bool = false
    /// The persistent source folder, if one is set (nil for Photos imports or
    /// one-off single-image opens).
    @Published var sourceFolderURL: URL?

    private static let bookmarkKey = "imageSourceFolderBookmark"
    private var thumbnailTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    /// Folder whose security scope we hold open, released when we move on.
    private var scopedURL: URL?

    deinit {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    var selectedItem: Item? {
        guard isActive, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    // MARK: - Source folder

    /// Set (and persist) a folder as the image source: saves a security-scoped
    /// bookmark, records the URL, and scans it. Mirrors `LUTLibrary`'s folder
    /// persistence so the source survives relaunches and the App Sandbox.
    func setSourceFolder(_ url: URL) {
        saveBookmark(for: url)
        sourceFolderURL = url
        loadFromFolder(url)
    }

    /// Restore a previously-chosen source folder on launch. Returns true if a
    /// folder was resolved; the scan itself runs asynchronously.
    @discardableResult
    func restoreSourceFolder() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return false }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.startAccessingSecurityScopedResource() else { return false }

        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = url

        // A stale bookmark resolves this once but won't next launch; mint a
        // fresh one now that access is held.
        if isStale { saveBookmark(for: url) }

        sourceFolderURL = url
        loadFromFolder(url)
        return true
    }

    private func saveBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        } catch {
            print("Failed to save source bookmark: \(error)")
        }
    }

    /// Re-scan the current source folder (e.g. after files change on disk).
    func refresh() {
        guard let url = sourceFolderURL else { return }
        loadFromFolder(url)
    }

    /// Wait for the in-flight folder scan to finish, so callers that need to
    /// act on `items` (open the first image, say) can do so without racing it.
    func scanCompletion() async {
        await scanTask?.value
    }

    /// Scan a folder recursively for supported images, recording each file's
    /// relative subfolder so the browser can group them. Items are ordered by
    /// subfolder, then natural filename order.
    ///
    /// The enumeration runs off the main actor — a deep folder on a slow or
    /// network volume would otherwise stall the window, and this runs during
    /// app launch when a source folder is restored.
    func loadFromFolder(_ url: URL) {
        thumbnailTask?.cancel()
        scanTask?.cancel()
        items = []
        selectedIndex = 0
        isActive = false

        scanTask = Task {
            let scanned = await Self.scanFolder(url)
            guard !Task.isCancelled else { return }
            self.items = scanned
            self.isActive = !scanned.isEmpty
            self.generateThumbnails()
        }
    }

    /// The blocking half of `loadFromFolder`. `nonisolated` so it can run on a
    /// background executor — it touches no instance state.
    private nonisolated static func scanFolder(_ url: URL) async -> sending [Item] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Resolve symlinks on both sides so the prefix math holds even when the
        // root is itself a symlink (e.g. /tmp → /private/tmp).
        let rootPath = url.resolvingSymlinksInPath().path
        var newItems: [Item] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { return [] }
            let ext = fileURL.pathExtension.lowercased()
            guard ImageDecoder.supportedExtensions.contains(ext) else { continue }
            let name = fileURL.deletingPathExtension().lastPathComponent
            let dir = fileURL.deletingLastPathComponent().resolvingSymlinksInPath().path
            let subfolder = dir.hasPrefix(rootPath)
                ? String(dir.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : ""
            newItems.append(Item(url: fileURL, displayName: name, imageData: nil, subfolder: subfolder))
        }

        newItems.sort { a, b in
            if a.subfolder != b.subfolder {
                return a.subfolder.localizedStandardCompare(b.subfolder) == .orderedAscending
            }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
        return newItems
    }

    // MARK: - Data import (from Photos picker)

    /// Adopt a set of Photos-picker payloads as the collection.
    ///
    /// **The second thumbnail site.** `generateThumbnails` below is the obvious one; this one builds
    /// its thumbnails inline and is easy to miss when the thumbnail path moves — which is why
    /// `docs/PHASE2_SPEC.md` §6 names both explicitly. Step 7 pointed both at `Thumbnails`.
    func addFromData(_ dataItems: [(name: String, data: Data)]) {
        thumbnailTask?.cancel()
        items = []
        selectedIndex = 0

        var newItems: [Item] = []
        for item in dataItems {
            let thumb = Thumbnails.generate(from: item.data)
            newItems.append(Item(url: nil, displayName: item.name, thumbnail: thumb, imageData: item.data))
        }
        self.items = newItems
        self.isActive = !items.isEmpty
    }

    /// Present the image subset of the durable global Media Library in the
    /// existing filmstrip and comparison workflow. Record UUIDs make selection
    /// stable across refreshes; videos stay in Media Library but are not sent
    /// to the image decoder.
    func loadMediaRecords(_ records: [MediaRecord]) {
        thumbnailTask?.cancel()
        scanTask?.cancel()
        let previousID = selectedItem?.id
        items = records.filter { $0.kind == .image && $0.isAvailable }.map { record in
            Item(
                id: record.id.rawValue, url: record.url, displayName: record.displayName,
                imageData: nil, subfolder: record.logicalFolder
            )
        }
        if let previousID, let index = items.firstIndex(where: { $0.id == previousID }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }
        isActive = items.isEmpty == false
        sourceFolderURL = nil
        generateThumbnails()
    }

    // MARK: - Navigation

    func selectNext() {
        guard isActive, selectedIndex < items.count - 1 else { return }
        selectedIndex += 1
    }

    func selectPrevious() {
        guard isActive, selectedIndex > 0 else { return }
        selectedIndex -= 1
    }

    /// Clear the in-session collection (e.g. when opening a one-off single
    /// image). The persisted source-folder bookmark is left intact so it still
    /// restores on next launch; only the live browsing state is dropped.
    func clear() {
        thumbnailTask?.cancel()
        items = []
        selectedIndex = 0
        isActive = false
        sourceFolderURL = nil
    }

    // MARK: - Thumbnail generation

    /// Fill in each file-backed item's thumbnail, off the main actor.
    ///
    /// The detached task used to capture `ImageProcessor.shared` — a non-`Sendable` class crossing
    /// an isolation boundary, the hazard `docs/PHASE2_SPEC.md` §2 flags. `Thumbnails` is stateless,
    /// so only the `URL` crosses now.
    private func generateThumbnails() {
        thumbnailTask = Task {
            for i in items.indices {
                guard !Task.isCancelled else { return }
                guard items[i].thumbnail == nil, let url = items[i].url else { continue }

                // Remember which item this thumbnail belongs to: `items` can be
                // replaced by a refresh while the decode is in flight, and an
                // index alone would then point at a different file.
                let itemID = items[i].id

                let thumb = await Thumbnails.generateOffMain(from: url)

                guard !Task.isCancelled else { return }
                guard let current = items.firstIndex(where: { $0.id == itemID }) else { continue }
                items[current].thumbnail = thumb
            }
        }
    }
}
