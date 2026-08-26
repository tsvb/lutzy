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
        media.migrateLegacyProjects(projects)
        collection.loadMediaRecords(media.records)
    }

    // MARK: - Importing images

    /// Copy images into the open project.
    ///
    /// Copied rather than referenced, for the same reason LUTs are: a project
    /// that points at files elsewhere breaks the day those files move, and the
    /// whole point of a project is that it still opens next year.
    func importImages() {
        let panel = NSOpenPanel()
        panel.title = "Import Media"
        panel.message = "Choose images, videos, or folders of them."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, panel.urls.isEmpty == false else { return }
        importImages(from: panel.urls)
    }

    func importImages(from urls: [URL]) {
        statusMessage = "Importing media…"
        Task {
            let result = await media.importMedia(from: urls)
            loadProjectImages()
            statusMessage = Self.mediaImportSummary(result)
        }
    }

    func openMedia(_ record: MediaRecord) {
        media.selectedID = record.id
        guard record.isAvailable else {
            statusMessage = "\(record.displayName) is unavailable"
            return
        }
        guard record.canOpenInViewer else {
            statusMessage = "Video browsing is available; playback is not included yet"
            return
        }
        if let index = collection.items.firstIndex(where: { $0.id == record.id.rawValue }) {
            collection.selectedIndex = index
        }
        openImage(url: record.url)
        section = .viewer
        scheduleSessionSave()
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
        if let item = collection.selectedItem,
           media.records.contains(where: { $0.id.rawValue == item.id }) {
            session.mediaRecordID = item.id.uuidString.lowercased()
        }
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
        defer { finishSessionRestore() }
        section = session.section
        comparisonLayout = session.layout
        tagFilter = Set(session.tagFilter)
        browsedCategory = session.browsedCategory
        showingFavouritesOnly = session.showingFavouritesOnly
        cellLUTIDs = session.cellLUTs.map { $0.map { LUTID(raw: $0) } }
        cellImages = Array(repeating: nil, count: cellLUTIDs.count)
        if comparisonLayout.isGrid, cellLUTIDs.isEmpty == false {
            // Pointer focus is intentionally not project data, but the saved
            // LUT tells us which cell was last being judged. Reconnect the two
            // when possible; only fall back to Cell 1 when that LUT is absent.
            let restoredSelection = session.selectedLUT.map { LUTID(raw: $0) }
            activeGridCellIndex = restoredSelection.flatMap { selected in
                cellLUTIDs.firstIndex { $0 == .some(selected) }
            } ?? 0
        } else {
            activeGridCellIndex = nil
        }

        updateDocument { $0.sourceSpace = session.sourceSpace }

        // Both scans are asynchronous and both are usually still running when a
        // project opens, so each restore waits for the one it depends on.
        // Restoring the LUT before the library lands silently selects nothing,
        // which looks exactly like a project saved without one.
        //
        // Only the LUT and the image are deferred. Anything set synchronously
        // above is already applied; re-applying it once the scan lands would
        // undo whatever the user did in the meantime — measured: opening the
        // editor during startup switched the preview to its before/after
        // layout, and the late restore put the viewer's 3x3 back.
        let hasSavedLUTReferences = session.selectedLUT != nil
            || session.cellLUTs.contains(where: { $0 != nil })
        if hasSavedLUTReferences {
            // Raised here, not inside the task: the synchronous pass releases
            // its own hold as soon as it returns, and a hold taken only once
            // the task starts would leave a gap where a save could fire.
            let restoringProjectID = projects.current?.id
            restoreDepth += 1
            Task {
                defer { finishSessionRestore() }
                await library.scanCompletion()
                guard projects.current?.id == restoringProjectID else { return }
                migrateLegacyLUTReferences()
                // Only when it resolves. A LUT that has been deleted from the
                // library should leave the project's record alone rather than
                // clearing it — the file may come back.
                guard let raw = session.selectedLUT else { return }
                let migratedID = library.migratedRecordID(for: LUTID(raw: raw))
                guard let lut = resolvedLUT(migratedID) else { return }
                selectLUT(lut)
                if lut.lutID.raw != raw { scheduleMigratedSessionSave() }
            }
        }

        let directID = session.mediaRecordID.flatMap(UUID.init(uuidString:)).map(MediaRecordID.init)
        let migratedID: MediaRecordID? = directID ?? {
            guard let projectID = projects.current?.id, let name = session.imageName else { return nil }
            return media.legacySessionID(projectID: projectID, basename: name)
        }()
        guard let id = migratedID,
              let record = media.record(id), record.kind == .image,
              let index = collection.items.firstIndex(where: { $0.id == id.rawValue })
        else { return }
        selectCollectionImage(at: index)
        if directID == nil { scheduleMigratedSessionSave() }
    }
}
