import Foundation
import CryptoKit
import AppKit
import UniformTypeIdentifiers

/// Projects: switching between them, filling them with images, and putting the
/// workspace back the way it was left.
@MainActor
extension AppViewModel {

    // MARK: - Switching

    /// Open a project: load its images and restore what was on screen.
    func openProject(_ project: Project) {
        captureSession()                 // don't lose the one being left
        projects.open(project)
        loadProjectImages()
        restoreSession(project.session)
        statusMessage = "Opened \(project.name)"
    }

    func createProject(named name: String) {
        captureSession()
        let project = projects.create(named: name)
        collection.clear()
        clearImage()
        loadProjectImages()
        statusMessage = "Created \(project.name)"
    }

    func deleteProject(_ project: Project) {
        let wasCurrent = projects.current?.id == project.id
        projects.delete(project)
        guard wasCurrent else { return }
        collection.clear()
        clearImage()
        if let next = projects.current {
            loadProjectImages()
            restoreSession(next.session)
        }
    }

    /// Point the filmstrip and browser at the open project's images.
    func loadProjectImages() {
        guard let folder = projects.currentImagesFolder else {
            collection.clear()
            return
        }
        collection.loadFromFolder(folder)
    }

    // MARK: - Importing images

    /// Copy images into the open project.
    ///
    /// Copied rather than referenced, for the same reason LUTs are: a project
    /// that points at files elsewhere breaks the day those files move, and the
    /// whole point of a project is that it still opens next year.
    func importImages() {
        guard projects.current != nil else {
            statusMessage = "Create a project first"
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Import Images"
        panel.message = "Choose images or folders of them."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, panel.urls.isEmpty == false else { return }
        importImages(from: panel.urls)
    }

    func importImages(from urls: [URL]) {
        guard let destination = projects.currentImagesFolder else {
            statusMessage = "Create a project first"
            return
        }
        statusMessage = "Importing images…"
        Task {
            let result = await Task.detached { Self.copyImages(urls, to: destination) }.value
            loadProjectImages()
            statusMessage = Self.importSummary(result)
        }
    }

    /// The copying half. Same duplicate rule as the LUT import — by content, so
    /// importing the same folder twice is a no-op rather than a second copy.
    nonisolated static func copyImages(_ urls: [URL], to destination: URL) -> LUTLibrary.ImportResult {
        func digest(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let fm = FileManager.default
        var result = LUTLibrary.ImportResult(imported: 0, duplicates: 0, failed: 0)

        var existing = Set<String>()
        if let walker = fm.enumerator(at: destination, includingPropertiesForKeys: nil) {
            while let url = walker.nextObject() as? URL {
                if let data = try? Data(contentsOf: url) { existing.insert(digest(data)) }
            }
        }

        func isImage(_ url: URL) -> Bool {
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image) || ImageDecoder.rawExtensions.contains(url.pathExtension.lowercased())
        }

        func copyOne(_ source: URL, into folder: URL) {
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

        for source in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
                result.failed += 1
                continue
            }
            if isDirectory.boolValue {
                // A folder keeps its name, so an imported shoot stays grouped in
                // the browser rather than merging into everything else.
                let group = destination.appendingPathComponent(source.lastPathComponent, isDirectory: true)
                guard let walker = fm.enumerator(at: source, includingPropertiesForKeys: nil) else {
                    result.failed += 1
                    continue
                }
                while let url = walker.nextObject() as? URL {
                    guard isImage(url) else { continue }
                    copyOne(url, into: group)
                }
            } else if isImage(source) {
                copyOne(source, into: destination)
            } else {
                result.failed += 1
            }
        }
        return result
    }

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

    // MARK: - Session

    /// What is on screen now, in the form a project stores.
    func currentSession() -> Project.Session {
        var session = Project.Session()
        session.section = section
        session.layout = comparisonLayout
        session.selectedLUT = document.lut.lutID?.raw
        session.cellLUTs = cellLUTIDs.map { $0?.raw }
        session.imageName = collection.selectedItem?.url?.lastPathComponent
        session.tagFilter = tagFilter.sorted()
        session.browsedCategory = browsedCategory
        session.showingFavouritesOnly = showingFavouritesOnly
        session.sourceSpace = document.sourceSpace
        return session
    }

    /// Save the workspace against the open project. Cheap and idempotent —
    /// `ProjectStore` writes only when something actually changed.
    func captureSession() {
        guard projects.current != nil else { return }
        projects.updateSession(currentSession())
    }

    /// Put a workspace back.
    ///
    /// The image is restored by name within the project rather than by path, so
    /// a project folder that moved still finds its picture; a name that is no
    /// longer there simply leaves nothing open, which is better than an error
    /// about a file the user never chose directly.
    func restoreSession(_ session: Project.Session) {
        restoreDepth += 1
        defer { restoreDepth -= 1 }
        section = session.section
        comparisonLayout = session.layout
        tagFilter = Set(session.tagFilter)
        browsedCategory = session.browsedCategory
        showingFavouritesOnly = session.showingFavouritesOnly
        cellLUTIDs = session.cellLUTs.map { $0.map { LUTID(raw: $0) } }
        cellImages = Array(repeating: nil, count: cellLUTIDs.count)

        updateDocument { $0.sourceSpace = session.sourceSpace }

        // Both scans are asynchronous and both are usually still running when a
        // project opens, so each restore waits for the one it depends on.
        // Restoring the LUT before the library lands silently selects nothing,
        // which looks exactly like a project saved without one.
        if let raw = session.selectedLUT {
            // Raised here, not inside the task: the synchronous pass releases
            // its own hold as soon as it returns, and a hold taken only once
            // the task starts would leave a gap where a save could fire.
            restoreDepth += 1
            Task {
                defer { restoreDepth -= 1 }
                await library.scanCompletion()
                // Only when it resolves. A LUT that has been deleted from the
                // library should leave the project's record alone rather than
                // clearing it — the file may come back.
                guard let lut = library.allLUTs.first(matching: LUTID(raw: raw)) else { return }
                selectLUT(lut)
                // The layout comes back with it: split and compare fall back to
                // a single view while there is nothing to compare against, so
                // restoring it before the LUT would land on the fallback.
                comparisonLayout = session.layout
            }
        }

        guard let name = session.imageName else { return }
        restoreDepth += 1
        Task {
            defer { restoreDepth -= 1 }
            await collection.scanCompletion()
            guard let index = collection.items.firstIndex(where: { $0.url?.lastPathComponent == name }) else { return }
            selectCollectionImage(at: index)
        }
    }
}
