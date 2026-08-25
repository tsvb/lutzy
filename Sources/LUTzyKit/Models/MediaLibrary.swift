import Foundation
import Combine
import CryptoKit
import UniformTypeIdentifiers

struct MediaRecordID: Codable, Sendable, Hashable {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = UUID(uuidString: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(), debugDescription: "Invalid MediaRecordID"
            )
        }
        rawValue = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString.lowercased())
    }
}

enum MediaKind: String, Codable, Sendable, CaseIterable {
    case image
    case video
}

struct MediaRecord: Identifiable, Codable, Sendable, Equatable {
    let id: MediaRecordID
    var displayName: String
    var kind: MediaKind
    var logicalPath: String
    var locator: String
    var fingerprint: String
    var byteCount: Int64
    var legacyOriginKey: String?
    var legacySourceName: String?
    var isAvailable: Bool

    var url: URL { URL(fileURLWithPath: locator) }
    var logicalFolder: String {
        let value = (logicalPath as NSString).deletingLastPathComponent
        return value == "." ? "" : value
    }
}

enum MediaLibraryViewMode: String, Codable, Sendable, CaseIterable {
    case columns
    case list
}

/// Global, project-free media manifest. It aggregates old project Images
/// folders without moving them and owns all new imports under one managed root.
@MainActor
final class MediaLibrary: ObservableObject {
    private struct Snapshot: Codable {
        var version: Int = 1
        var records: [MediaRecord]
    }

    struct ImportResult: Sendable, Equatable {
        var imported = 0
        var duplicates = 0
        var failed = 0
    }

    @Published private(set) var records: [MediaRecord] = []
    @Published var selectedID: MediaRecordID?
    @Published var viewMode: MediaLibraryViewMode = .columns

    let managedRoot: URL
    private let manifestURL: URL

    init(root: URL? = nil, manifestURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let app = base.appendingPathComponent("LUTStudio", isDirectory: true)
        self.managedRoot = root ?? app.appendingPathComponent("Media", isDirectory: true)
        if let manifestURL {
            self.manifestURL = manifestURL
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            self.manifestURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("media-manifest-test-\(UUID().uuidString).json")
        } else {
            self.manifestURL = app.appendingPathComponent("media-manifest.json")
        }
        try? FileManager.default.createDirectory(at: managedRoot, withIntermediateDirectories: true)
        load()
        refreshAvailability()
    }

    var selectedRecord: MediaRecord? {
        selectedID.flatMap { id in records.first { $0.id == id } }
    }

    var folders: [(path: String, count: Int)] {
        let groups = Dictionary(grouping: records.filter(\.isAvailable), by: \.logicalFolder)
        return groups.map { (path: $0.key, count: $0.value.count) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func record(_ id: MediaRecordID) -> MediaRecord? { records.first { $0.id == id } }

    /// A secondary label is shown only when the visible name collides in the
    /// same logical folder; the legacy project never reappears as navigation.
    func disambiguator(for record: MediaRecord) -> String? {
        let collisions = records.filter {
            $0.id != record.id && $0.logicalFolder == record.logicalFolder
                && $0.displayName == record.displayName
        }
        return collisions.isEmpty ? nil : record.legacySourceName
    }

    func records(in folder: String?) -> [MediaRecord] {
        records.filter { record in
            guard record.isAvailable else { return false }
            guard let folder, folder.isEmpty == false else { return true }
            return record.logicalFolder == folder || record.logicalFolder.hasPrefix(folder + "/")
        }
        .sorted {
            if $0.logicalPath != $1.logicalPath {
                return $0.logicalPath.localizedStandardCompare($1.logicalPath) == .orderedAscending
            }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }

    /// Index every legacy project by stable project UUID + relative path.
    /// Existing records are refreshed in place, making migration idempotent.
    func migrateLegacyProjects(_ store: ProjectStore) {
        var byOrigin = Dictionary(uniqueKeysWithValues: records.compactMap { record in
            record.legacyOriginKey.map { ($0, record.id) }
        })
        var changed = false

        for project in store.projects {
            let root = store.imagesFolder(for: project)
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
            ) else { continue }
            let rootPath = Self.normalized(root)
            while let url = walker.nextObject() as? URL {
                guard let kind = Self.kind(for: url), let data = try? Data(contentsOf: url) else { continue }
                let path = Self.normalized(url)
                let relative = path.hasPrefix(rootPath + "/")
                    ? String(path.dropFirst(rootPath.count + 1)) : url.lastPathComponent
                let origin = "\(project.id.uuidString.lowercased())|\(relative)"
                let size = Int64(data.count)
                if let id = byOrigin[origin], let index = records.firstIndex(where: { $0.id == id }) {
                    records[index].locator = path
                    records[index].isAvailable = true
                    records[index].byteCount = size
                    continue
                }
                let record = MediaRecord(
                    id: MediaRecordID(), displayName: url.deletingPathExtension().lastPathComponent,
                    kind: kind, logicalPath: relative, locator: path,
                    fingerprint: Self.digest(data), byteCount: size,
                    legacyOriginKey: origin, legacySourceName: project.name, isAvailable: true
                )
                records.append(record)
                byOrigin[origin] = record.id
                changed = true
            }
        }
        if changed { sortAndPersist() } else { persist() }
    }

    /// Copy supported images and videos into the global managed root while
    /// retaining the complete hierarchy supplied by the user.
    func importMedia(from urls: [URL]) async -> ImportResult {
        let existing = Set(records.map(\.fingerprint))
        let root = managedRoot
        let result = await Task.detached {
            Self.copyIn(urls, to: root, existingFingerprints: existing)
        }.value
        for record in result.records { records.append(record) }
        sortAndPersist()
        return result.tally
    }

    private struct CopyOutcome: Sendable {
        var tally: ImportResult
        var records: [MediaRecord]
    }

    private nonisolated static func copyIn(
        _ urls: [URL], to root: URL, existingFingerprints: Set<String>
    ) -> CopyOutcome {
        let fm = FileManager.default
        var tally = ImportResult()
        var records: [MediaRecord] = []
        var known = existingFingerprints

        func copyOne(_ source: URL, relative: String) {
            guard let kind = kind(for: source), let data = try? Data(contentsOf: source) else {
                tally.failed += 1
                return
            }
            let fingerprint = digest(data)
            guard known.insert(fingerprint).inserted else {
                tally.duplicates += 1
                return
            }
            let logical = relative.isEmpty ? source.lastPathComponent : relative
            let logicalFolder = (logical as NSString).deletingLastPathComponent
            let destinationFolder = logicalFolder == "."
                ? root : root.appendingPathComponent(logicalFolder, isDirectory: true)
            do {
                try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                let destination = uniqueURL(in: destinationFolder, named: source.lastPathComponent)
                try data.write(to: destination, options: .atomic)
                records.append(MediaRecord(
                    id: MediaRecordID(), displayName: source.deletingPathExtension().lastPathComponent,
                    kind: kind, logicalPath: logical, locator: normalized(destination),
                    fingerprint: fingerprint, byteCount: Int64(data.count),
                    legacyOriginKey: nil, legacySourceName: nil, isAvailable: true
                ))
                tally.imported += 1
            } catch {
                tally.failed += 1
            }
        }

        for source in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
                tally.failed += 1
                continue
            }
            if isDirectory.boolValue {
                let sourceRoot = normalized(source)
                guard let walker = fm.enumerator(at: source, includingPropertiesForKeys: nil) else {
                    tally.failed += 1
                    continue
                }
                while let file = walker.nextObject() as? URL {
                    guard kind(for: file) != nil else { continue }
                    let path = normalized(file)
                    let nested = path.hasPrefix(sourceRoot + "/")
                        ? String(path.dropFirst(sourceRoot.count + 1)) : file.lastPathComponent
                    copyOne(file, relative: source.lastPathComponent + "/" + nested)
                }
            } else {
                copyOne(source, relative: source.lastPathComponent)
            }
        }
        return CopyOutcome(tally: tally, records: records)
    }

    func legacySessionID(projectID: UUID, basename: String) -> MediaRecordID? {
        let prefix = projectID.uuidString.lowercased() + "|"
        let matches = records.filter {
            guard let origin = $0.legacyOriginKey, origin.hasPrefix(prefix) else { return false }
            return URL(fileURLWithPath: $0.locator).lastPathComponent == basename
        }
        return matches.count == 1 ? matches[0].id : nil
    }

    func refreshAvailability() {
        for index in records.indices {
            records[index].isAvailable = FileManager.default.fileExists(atPath: records[index].locator)
        }
    }

    func flush() { persist() }

    private func sortAndPersist() {
        records.sort { $0.logicalPath.localizedStandardCompare($1.logicalPath) == .orderedAscending }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        records = snapshot.records
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(Snapshot(records: records)) else { return }
        try? FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: manifestURL, options: .atomic)
    }

    private nonisolated static func kind(for url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()
        if ImageDecoder.supportedExtensions.contains(ext) { return .image }
        guard let type = UTType(filenameExtension: ext), type.conforms(to: .movie) else { return nil }
        return .video
    }

    private nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func normalized(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private nonisolated static func uniqueURL(in folder: URL, named name: String) -> URL {
        let candidate = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for suffix in 2...9999 {
            let candidate = folder.appendingPathComponent("\(stem) \(suffix).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) == false { return candidate }
        }
        return folder.appendingPathComponent("\(UUID().uuidString)-\(name)")
    }
}
