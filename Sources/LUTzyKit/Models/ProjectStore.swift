import Foundation
import Combine

/// Where projects live, and which one is open.
///
/// One folder per project under Application Support, holding a `project.json`
/// and an `Images` folder. A folder rather than a single document because the
/// images are *in* the project — copying them in is what makes a project
/// self-contained, and what stops it breaking the day the originals are moved.
@MainActor
final class ProjectStore: ObservableObject {

    @Published private(set) var projects: [Project] = []
    @Published private(set) var current: Project?

    private let root: URL
    private static let lastOpenKey = "lutzy.lastProject"

    /// Files this app writes alongside the images; excluded when listing what
    /// the project contains.
    private static let projectFile = "project.json"

    init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot()
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        reload()
    }

    private static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LUTStudio/Projects", isDirectory: true)
    }

    // MARK: - Locations

    func folder(for project: Project) -> URL {
        root.appendingPathComponent(project.id.uuidString, isDirectory: true)
    }

    func imagesFolder(for project: Project) -> URL {
        let folder = self.folder(for: project).appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The open project's images, or `nil` when nothing is open.
    var currentImagesFolder: URL? {
        current.map { imagesFolder(for: $0) }
    }

    // MARK: - Listing

    func reload() {
        let contents = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        projects = contents.compactMap { folder in
            let file = folder.appendingPathComponent(Self.projectFile)
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? Self.decoder.decode(Project.self, from: data)
        }
        .sorted { $0.lastOpenedAt > $1.lastOpenedAt }

        // Reopen whatever was open, or the most recent, or nothing — a fresh
        // install has no projects and must not invent one silently.
        if let stored = UserDefaults.standard.string(forKey: Self.lastOpenKey),
           let id = UUID(uuidString: stored),
           let match = projects.first(where: { $0.id == id }) {
            current = match
        } else {
            current = projects.first
        }
    }

    // MARK: - Editing

    @discardableResult
    func create(named name: String) -> Project {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(name: cleaned.isEmpty ? "Untitled" : cleaned)
        try? FileManager.default.createDirectory(at: imagesFolder(for: project), withIntermediateDirectories: true)
        write(project)
        projects.insert(project, at: 0)
        current = project
        rememberCurrent()
        return project
    }

    func open(_ project: Project) {
        var opened = project
        opened.lastOpenedAt = Date()
        write(opened)
        replace(opened)
        current = opened
        rememberCurrent()
    }

    func rename(_ project: Project, to name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return }
        var renamed = project
        renamed.name = cleaned
        write(renamed)
        replace(renamed)
        if current?.id == project.id { current = renamed }
    }

    /// Delete a project and everything in it.
    ///
    /// To the Trash rather than unlinked: the images inside were imported by
    /// hand and may be the only copy the user still knows the location of.
    func delete(_ project: Project) {
        try? FileManager.default.trashItem(at: folder(for: project), resultingItemURL: nil)
        projects.removeAll { $0.id == project.id }
        if current?.id == project.id {
            current = projects.first
            rememberCurrent()
        }
    }

    /// Record what the user was doing. Called as the workspace changes, so it
    /// writes a small file often — hence no images or thumbnails in it.
    func updateSession(_ session: Project.Session) {
        guard var project = current, project.session != session else { return }
        project.session = session
        project.lastOpenedAt = Date()
        write(project)
        replace(project)
        current = project
    }

    // MARK: - Private

    private func replace(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        }
    }

    /// Dates are written as ISO 8601, so they have to be *read* that way. The
    /// default strategy is seconds-since-2001, and the mismatch does not throw
    /// anywhere visible: every project silently fails to decode and the app
    /// opens with no projects at all.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func write(_ project: Project) {
        let folder = self.folder(for: project)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(project) else { return }
        try? data.write(to: folder.appendingPathComponent(Self.projectFile), options: .atomic)
    }

    private func rememberCurrent() {
        if let current {
            UserDefaults.standard.set(current.id.uuidString, forKey: Self.lastOpenKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.lastOpenKey)
        }
    }
}
