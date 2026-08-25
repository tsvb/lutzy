import Foundation
import Combine
import CryptoKit

/// Manages a folder of .cube LUT files, scanning and grouping by subfolder.
@MainActor
final class LUTLibrary: ObservableObject {

    struct Category: Identifiable {
        let id: String      // category name
        let name: String
        let luts: [CubeLUT]
    }

    @Published var categories: [Category] = []
    @Published var allLUTs: [CubeLUT] = []
    @Published var folderURL: URL?
    @Published var scanError: String?
    /// True while a folder scan is running. Drives the sidebar's progress hint.
    @Published var isScanning: Bool = false

    /// Fired after every scan publishes its results, whatever started it.
    ///
    /// Exists so `AppViewModel` can drop the engine's cube-filter cache. A `LUTID` is a file path, so
    /// a `.cube` replaced in place keeps its identity and a cached filter would go on serving the old
    /// contents — reachable as of Step 9, when saving a second derive over the same path became a
    /// thing the UI can do.
    ///
    /// A closure rather than a call at each scan site because it covers *every* scan — `setFolder`,
    /// `restoreFolder`, and the rescan after a save — instead of relying on the next person to
    /// remember. The library stays ignorant of the renderer, which is why this is a closure the owner
    /// wires rather than an engine reference held here.
    var onScanned: (() -> Void)?

    private static let settingsKey = "lutFolderBookmark"

    /// The library the app owns, under Application Support.
    ///
    /// The reason the app has one at all: pointing at a folder somewhere on
    /// disk means re-granting access to it, and losing the whole library the
    /// day that folder moves. Files imported here belong to the app, need no
    /// security scope, and are simply there on the next launch.
    static var managedFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("LUTStudio/LUTs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Whether the library is currently the app's own folder — the only case
    /// in which removing a LUT means deleting a file, since everywhere else the
    /// files are the user's own and not ours to delete.
    var isManaged: Bool {
        folderURL?.standardizedFileURL == Self.managedFolder.standardizedFileURL
    }

    /// Folder whose security scope we hold open, so it can be released when we
    /// move to a different folder or the library goes away.
    private var scopedURL: URL?
    private var scanTask: Task<Void, Never>?

    deinit {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Folder management

    func setFolder(_ url: URL) {
        saveBookmark(for: url)
        self.folderURL = url
        scan(url)
    }

    func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: Self.settingsKey) else {
            // Nothing chosen: use the app's own library, which is always there
            // and never needs permission. A first launch therefore shows an
            // empty library to import into rather than a folder picker.
            useManagedFolder()
            return
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            useManagedFolder()
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            // The bookmark resolved but access was refused — the folder moved
            // to a volume that is not mounted, or permission was revoked.
            // Falling back beats showing an empty library with no explanation.
            useManagedFolder()
            return
        }
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = url

        // A stale bookmark still resolves once, but won't next launch unless we
        // mint a fresh one now that we hold access.
        if isStale { saveBookmark(for: url) }

        self.folderURL = url
        scan(url)
    }

    private func saveBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.settingsKey)
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }

    /// Point the library at the app's own folder. No bookmark: the path is
    /// derived, so there is nothing to go stale.
    func useManagedFolder() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        UserDefaults.standard.removeObject(forKey: Self.settingsKey)
        let folder = Self.managedFolder
        self.folderURL = folder
        scan(folder)
    }

    // MARK: - Importing

    struct ImportResult: Sendable, Equatable {
        var imported: Int
        var duplicates: Int
        var failed: Int
    }

    /// Copy LUTs into the app's own library.
    ///
    /// Accepts files and folders alike; a folder is walked for `.cube` files
    /// and its own name becomes the category, so importing a folder of Fuji
    /// looks lands them together rather than loose among everything else.
    ///
    /// A file whose *contents* are already in the library is a duplicate and is
    /// skipped — importing the same folder twice should be a no-op, not a
    /// second copy of everything under "name 2.cube". A different file that
    /// merely shares a name is kept, under a numbered name.
    ///
    /// Importing always switches the library to the managed folder: copying
    /// files somewhere the user is not looking would be indistinguishable from
    /// doing nothing.
    func importLUTs(from urls: [URL]) async -> ImportResult {
        let destination = Self.managedFolder
        let result = await Task.detached { Self.copyIn(urls, to: destination) }.value
        if isManaged {
            scan(destination)
        } else {
            useManagedFolder()
        }
        return result
    }

    /// The copying half of `importLUTs`. Pure — takes URLs, writes files,
    /// returns a tally — and internal so `lutcheck` can exercise the rules that
    /// matter (duplicates by content, name clashes, folders as categories)
    /// without a library, a scan, or a main actor.
    nonisolated static func copyIn(_ urls: [URL], to destination: URL) -> ImportResult {
        let fm = FileManager.default
        var result = ImportResult(imported: 0, duplicates: 0, failed: 0)

        // Hash what is already there once, rather than per candidate file.
        var existing = Set<String>()
        if let walker = fm.enumerator(at: destination, includingPropertiesForKeys: nil) {
            while let url = walker.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "cube" else { continue }
                if let data = try? Data(contentsOf: url) { existing.insert(digest(data)) }
            }
        }

        for source in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
                result.failed += 1
                continue
            }

            if isDirectory.boolValue {
                let category = source.lastPathComponent
                guard let walker = fm.enumerator(at: source, includingPropertiesForKeys: nil) else {
                    result.failed += 1
                    continue
                }
                while let url = walker.nextObject() as? URL {
                    guard url.pathExtension.lowercased() == "cube" else { continue }
                    copyOne(url, into: destination.appendingPathComponent(category, isDirectory: true),
                            existing: &existing, result: &result)
                }
            } else if source.pathExtension.lowercased() == "cube" {
                copyOne(source, into: destination, existing: &existing, result: &result)
            } else {
                result.failed += 1
            }
        }
        return result
    }

    private nonisolated static func copyOne(_ source: URL, into folder: URL,
                                            existing: inout Set<String>, result: inout ImportResult) {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: source) else {
            result.failed += 1
            return
        }
        let hash = digest(data)
        guard existing.contains(hash) == false else {
            result.duplicates += 1
            return
        }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: uniqueURL(in: folder, named: source.lastPathComponent), options: .atomic)
            existing.insert(hash)
            result.imported += 1
        } catch {
            result.failed += 1
        }
    }

    /// A free filename in `folder`. Only reached when two *different* LUTs
    /// share a name — identical ones were already skipped as duplicates.
    private nonisolated static func uniqueURL(in folder: URL, named name: String) -> URL {
        let fm = FileManager.default
        let candidate = folder.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for suffix in 2...999 {
            let next = folder.appendingPathComponent("\(stem) \(suffix).\(ext)")
            if fm.fileExists(atPath: next.path) == false { return next }
        }
        return candidate
    }

    private nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The folders in the managed library, as the browser lists them.
    var categoryNames: [String] {
        categories.map(\.name).sorted()
    }

    /// Move a LUT into another folder of the app's own library.
    ///
    /// A folder is the file's own location, so this is a file move — which is
    /// why it is refused outside the managed library, for the same reason
    /// removing is. Tags are keyed by content and follow the file across.
    /// An empty category name means the top level.
    @discardableResult
    func move(_ lut: CubeLUT, toCategory category: String) -> Bool {
        let managed = Self.managedFolder.standardizedFileURL
        guard lut.url.standardizedFileURL.path.hasPrefix(managed.path + "/") else { return false }

        let folder = category.isEmpty ? managed : managed.appendingPathComponent(category, isDirectory: true)
        let destination = Self.uniqueURL(in: folder, named: lut.url.lastPathComponent)
        guard destination.standardizedFileURL != lut.url.standardizedFileURL else { return true }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: lut.url, to: destination)
        } catch {
            return false
        }
        scan(managed)
        return true
    }

    /// Delete a LUT from the app's own library.
    ///
    /// Refuses anything outside the managed folder: everywhere else the files
    /// are the user's own, and "remove from my library" must never mean
    /// "delete the file you were keeping over there".
    @discardableResult
    func removeFromLibrary(_ lut: CubeLUT) -> Bool {
        let managed = Self.managedFolder.standardizedFileURL.path
        let target = lut.url.standardizedFileURL.path
        guard target.hasPrefix(managed + "/") else { return false }
        do {
            try FileManager.default.trashItem(at: lut.url, resultingItemURL: nil)
        } catch {
            return false
        }
        if let folder = folderURL { scan(folder) }
        return true
    }

    // MARK: - Scanning

    /// Scan `folder` for .cube files **off the main actor**, then publish the
    /// finished categories. A 33³ LUT is ~36k lines of text to parse, so a
    /// folder of a few dozen looks would otherwise stall the window at launch.
    func scan(_ folder: URL) {
        scanTask?.cancel()
        scanError = nil
        isScanning = true

        scanTask = Task {
            let outcome = await Task.detached { Self.scanSync(folder) }.value
            guard !Task.isCancelled else { return }

            self.isScanning = false
            switch outcome {
            case .failure(let message):
                self.scanError = message
                self.categories = []
                self.allLUTs = []
            case .success(let cats):
                self.scanError = nil
                self.categories = cats
                self.allLUTs = cats.flatMap(\.luts)
            }
            // After publishing, and on the failure path too: a scan that found nothing still means
            // the folder changed under whatever the engine has cached.
            self.onScanned?()
        }
    }

    /// Wait for the running scan, if any.
    ///
    /// Restoring a project's LUT needs the library to exist first: the scan is
    /// asynchronous, and asking for a LUT by ID before it lands quietly returns
    /// nothing, which looks exactly like a project that was saved without one.
    func scanCompletion() async {
        await scanTask?.value
    }

    private enum ScanOutcome {
        case success([Category])
        case failure(String)
    }

    /// The blocking half of `scan`. Pure: takes a folder, returns categories.
    /// `nonisolated` so it can run on a background executor.
    private nonisolated static func scanSync(_ folder: URL) -> ScanOutcome {
        var categoryMap: [String: [CubeLUT]] = [:]

        // `enumerator(at:)` hands back a live-but-empty enumerator for a folder
        // that has been moved or deleted, so a nil check alone would report
        // "no LUTs" for what is really a missing folder — the most likely
        // failure, since the folder is restored from a bookmark each launch.
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure("Can't find “\(folder.lastPathComponent)” — it may have been moved or renamed.")
        }
        guard fm.isReadableFile(atPath: folder.path) else {
            return .failure("No permission to read “\(folder.lastPathComponent)”.")
        }
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .failure("Can't read “\(folder.lastPathComponent)”.")
        }

        // Resolve symlinks on both sides so the category math holds even when
        // the root is itself a symlink (matches ImageCollection.loadFromFolder).
        let rootPath = folder.resolvingSymlinksInPath().path
        var skipped = 0

        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { return .success([]) }
            guard fileURL.pathExtension.lowercased() == "cube" else { continue }

            // Determine category from the path relative to the root.
            let path = fileURL.resolvingSymlinksInPath().path
            let relativePath = path.hasPrefix(rootPath)
                ? String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : fileURL.lastPathComponent
            let components = relativePath.split(separator: "/")
            let category = components.count > 1 ? String(components[0]) : "General"

            do {
                let lut = try CubeLUT(url: fileURL, category: category)
                categoryMap[category, default: []].append(lut)
            } catch {
                skipped += 1
                print("Skipping \(fileURL.lastPathComponent): \(error)")
            }
        }

        var cats: [Category] = []
        for key in categoryMap.keys.sorted() {
            let sorted = categoryMap[key]!.sorted { $0.name < $1.name }
            cats.append(Category(id: key, name: key, luts: sorted))
        }

        if cats.isEmpty {
            return .failure(skipped > 0
                ? "No readable .cube files in “\(folder.lastPathComponent)” (\(skipped) could not be parsed)."
                : "No .cube files in “\(folder.lastPathComponent)”.")
        }
        return .success(cats)
    }
}
