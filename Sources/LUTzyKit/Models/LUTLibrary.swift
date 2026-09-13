import Foundation
import Observation

/// Manages a folder of .cube LUT files, scanning and grouping by subfolder.
@Observable
@MainActor
final class LUTLibrary {

    struct Category: Identifiable {
        let id: String      // category name
        let name: String
        let luts: [CubeLUT]
    }

    var categories: [Category] = []
    var allLUTs: [CubeLUT] = []
    var folderURL: URL?
    var scanError: String?
    /// True while a folder scan is running. Drives the sidebar's progress hint.
    var isScanning: Bool = false

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
    @ObservationIgnored var onScanned: (() -> Void)?

    private static let settingsKey = "lutFolderBookmark"

    /// Folder whose security scope we hold open, so it can be released when we
    /// move to a different folder or the library goes away.
    ///
    /// `@ObservationIgnored` for the same reason as `ImageCollection.scopedURL`: `deinit` is
    /// `nonisolated` and reads it, which a tracked (`@MainActor`-accessed) property would forbid.
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var scanTask: Task<Void, Never>?

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
        guard let data = UserDefaults.standard.data(forKey: Self.settingsKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        guard url.startAccessingSecurityScopedResource() else { return }
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
