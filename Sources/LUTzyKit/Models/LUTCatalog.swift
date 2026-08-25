import Foundation
import Combine

/// A durable reference to one physical LUT file. `LUTID` remains the document
/// reference type for source compatibility; on-disk records use a `record://`
/// value while unsaved edits continue to use `derived://`.
typealias LUTRecordID = LUTID

enum LUTOrigin: Codable, Sendable, Equatable, Hashable {
    case vendor(String)
    case custom
    case unknown

    var label: String {
        switch self {
        case .vendor(let name): return name
        case .custom: return "Custom"
        case .unknown: return "Unknown"
        }
    }
}

struct LUTRecord: Identifiable, Codable, Sendable, Equatable {
    let id: LUTRecordID
    var locator: String
    var bookmark: Data?
    var fingerprint: String
    var isAvailable: Bool
    var displayNameOverride: String?
    var origin: LUTOrigin = .unknown
    var typedTags: [String] = []
    var isStarred: Bool = false
    var collectionIDs: Set<UUID> = []

    var url: URL { URL(fileURLWithPath: locator) }
}

struct LUTCollectionRecord: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
}

/// Persistent per-file identity and user-authored organisation metadata.
///
/// Content analysis intentionally stays in `LUTTagStore`; it describes the
/// transform. Everything here describes one library record and therefore must
/// not leak to an identical copy of the file.
@MainActor
final class LUTCatalog: ObservableObject {
    private struct Snapshot: Codable {
        var version: Int = 1
        var records: [LUTRecord]
        var collections: [LUTCollectionRecord]
    }

    @Published private(set) var records: [LUTRecordID: LUTRecord] = [:]
    @Published private(set) var collections: [LUTCollectionRecord] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
        load()
    }

    private static func defaultURL() -> URL {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("lut-catalog-test-\(UUID().uuidString).json")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("LUTStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("lut-catalog.json")
    }

    func record(for id: LUTRecordID) -> LUTRecord? { records[id] }

    func record(for lut: CubeLUT) -> LUTRecord? { records[lut.lutID] }

    func recordID(for locator: URL) -> LUTRecordID? {
        let path = Self.normalized(locator)
        return records.values.first { $0.locator == path }?.id
    }

    /// Resolve and parse a catalogued LUT that is not part of the active scan
    /// root. This is what makes an explicitly saved outside-root LUT survive a
    /// relaunch instead of leaving a durable ID that cannot produce pixels.
    func loadLUT(for id: LUTRecordID) -> CubeLUT? {
        guard var record = records[id] else { return nil }
        var url = record.url
        var didAccessSecurityScope = false

        if let bookmark = record.bookmark {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                url = resolved
                didAccessSecurityScope = resolved.startAccessingSecurityScopedResource()
                if isStale,
                   let refreshed = try? resolved.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                   ) {
                    record.bookmark = refreshed
                }
            }
        }
        defer {
            if didAccessSecurityScope { url.stopAccessingSecurityScopedResource() }
        }

        guard FileManager.default.fileExists(atPath: url.path),
              let parsed = try? CubeLUT(url: url, category: "External")
        else {
            if record.isAvailable {
                record.isAvailable = false
                records[id] = record
                persist()
            }
            return nil
        }

        record.locator = Self.normalized(url)
        record.fingerprint = parsed.contentHash
        record.isAvailable = true
        records[id] = record
        persist()
        return parsed.withRecordID(id)
    }

    func effectiveName(for lut: CubeLUT) -> String {
        guard let override = record(for: lut)?.displayNameOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines), override.isEmpty == false
        else { return lut.name }
        return override
    }

    func origin(for lut: CubeLUT) -> LUTOrigin { record(for: lut)?.origin ?? .unknown }
    func typedTags(for lut: CubeLUT) -> [String] { record(for: lut)?.typedTags ?? [] }
    func isStarred(_ lut: CubeLUT) -> Bool { record(for: lut)?.isStarred ?? false }

    func setDisplayName(_ name: String?, for ids: Set<LUTRecordID>) {
        let cleaned = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(ids) { $0.displayNameOverride = cleaned?.isEmpty == false ? cleaned : nil }
    }

    func setOrigin(_ origin: LUTOrigin, for ids: Set<LUTRecordID>) {
        mutate(ids) { $0.origin = origin }
    }

    func setStarred(_ starred: Bool, for ids: Set<LUTRecordID>) {
        mutate(ids) { $0.isStarred = starred }
    }

    func toggleStarred(_ id: LUTRecordID) {
        mutate([id]) { $0.isStarred.toggle() }
    }

    func addTag(_ tag: String, to ids: Set<LUTRecordID>) {
        let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return }
        mutate(ids) {
            guard $0.typedTags.contains(cleaned) == false else { return }
            $0.typedTags.append(cleaned)
            $0.typedTags.sort()
        }
    }

    func removeTag(_ tag: String, from ids: Set<LUTRecordID>) {
        mutate(ids) { $0.typedTags.removeAll { $0 == tag } }
    }

    @discardableResult
    func createCollection(named name: String) -> LUTCollectionRecord? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return nil }
        let now = Date()
        let item = LUTCollectionRecord(id: UUID(), name: cleaned, createdAt: now, updatedAt: now)
        collections.append(item)
        collections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persist()
        return item
    }

    func renameCollection(_ id: UUID, to name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false, let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].name = cleaned
        collections[index].updatedAt = Date()
        collections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persist()
    }

    func deleteCollection(_ id: UUID) {
        collections.removeAll { $0.id == id }
        for key in records.keys { records[key]?.collectionIDs.remove(id) }
        persist()
    }

    func setMembership(_ member: Bool, collectionID: UUID, recordIDs: Set<LUTRecordID>) {
        mutate(recordIDs) {
            if member { $0.collectionIDs.insert(collectionID) }
            else { $0.collectionIDs.remove(collectionID) }
        }
        if let index = collections.firstIndex(where: { $0.id == collectionID }) {
            collections[index].updatedAt = Date()
            persist()
        }
    }

    func members(of collectionID: UUID) -> Set<LUTRecordID> {
        Set(records.values.filter { $0.collectionIDs.contains(collectionID) }.map(\.id))
    }

    /// Assign records to a complete scan result. Reconciliation is performed
    /// per fingerprint bucket so filesystem enumeration order can never decide
    /// which duplicate inherits metadata.
    func reconcile(_ categories: [LUTLibrary.Category], scannedRoot: URL) -> [LUTLibrary.Category] {
        let root = Self.normalized(scannedRoot)
        let scanned = categories.flatMap(\.luts)
        let exactByPath = Dictionary(uniqueKeysWithValues: records.values.map { ($0.locator, $0.id) })
        let scannedPaths = Set(scanned.map { Self.normalized($0.url) })

        // Only this scan root is authoritative for availability. Explicit
        // outside-root records are not made unavailable by scanning elsewhere.
        for id in records.keys {
            guard let record = records[id], Self.isInside(record.locator, root: root) else { continue }
            records[id]?.isAvailable = scannedPaths.contains(record.locator)
        }

        var assignment: [String: LUTRecordID] = [:]
        var unmatched: [CubeLUT] = []
        for lut in scanned {
            let path = Self.normalized(lut.url)
            if let id = exactByPath[path] {
                records[id]?.fingerprint = lut.contentHash
                records[id]?.isAvailable = true
                assignment[path] = id
            } else {
                unmatched.append(lut)
            }
        }

        let filesByFingerprint = Dictionary(grouping: unmatched, by: \.contentHash)
        let missingByFingerprint = Dictionary(grouping: records.values.filter {
            $0.isAvailable == false && Self.isInside($0.locator, root: root)
        }, by: \.fingerprint)

        for (fingerprint, files) in filesByFingerprint {
            let missing = missingByFingerprint[fingerprint] ?? []
            if files.count == 1, missing.count == 1, let file = files.first, let old = missing.first {
                let path = Self.normalized(file.url)
                records[old.id]?.locator = path
                records[old.id]?.isAvailable = true
                assignment[path] = old.id
            } else {
                for file in files {
                    let path = Self.normalized(file.url)
                    let id = LUTID(recordUUID: UUID())
                    records[id] = LUTRecord(
                        id: id, locator: path, fingerprint: fingerprint, isAvailable: true
                    )
                    assignment[path] = id
                }
            }
        }

        persist()
        return categories.map { category in
            LUTLibrary.Category(
                id: category.id,
                name: category.name,
                luts: category.luts.map { lut in
                    guard let id = assignment[Self.normalized(lut.url)] else { return lut }
                    return lut.withRecordID(id)
                }
            )
        }
    }

    /// Preserve identity across a Manager-controlled file move. Persistence is
    /// synchronous so the caller can roll the filesystem move back on failure.
    func updateLocator(for id: LUTRecordID, to destination: URL) -> Bool {
        guard var record = records[id] else { return false }
        let previous = record
        record.locator = Self.normalized(destination)
        record.isAvailable = true
        records[id] = record
        guard persistReportingFailure() else {
            records[id] = previous
            return false
        }
        return true
    }

    /// Adopt a successfully written LUT immediately, including paths outside
    /// the scanned root. Known locators retain record metadata.
    func adoptSavedLUT(_ lut: CubeLUT, bookmark: Data? = nil) -> LUTRecordID? {
        let locator = Self.normalized(lut.url)
        if let existing = records.values.first(where: { $0.locator == locator })?.id {
            let previous = records[existing]
            records[existing]?.fingerprint = lut.contentHash
            records[existing]?.bookmark = bookmark ?? records[existing]?.bookmark
            records[existing]?.isAvailable = true
            guard persistReportingFailure() else {
                if let previous { records[existing] = previous }
                return nil
            }
            return existing
        }

        let id = LUTID(recordUUID: UUID())
        records[id] = LUTRecord(
            id: id, locator: locator, bookmark: bookmark,
            fingerprint: lut.contentHash, isAvailable: true
        )
        guard persistReportingFailure() else {
            records.removeValue(forKey: id)
            return nil
        }
        return id
    }

    /// One-time copy from the old content-keyed store. It is intentionally
    /// additive so a migrated record can diverge without a later scan
    /// overwriting the user's record-level edits.
    func migrateLegacyMetadata(for luts: [CubeLUT], from legacy: LUTTagStore) {
        var changed = false
        for lut in luts {
            let id = lut.lutID
            guard var record = records[id] else { continue }
            if record.typedTags.isEmpty {
                let tags = legacy.legacyTypedTags(forFingerprint: lut.contentHash)
                if tags.isEmpty == false { record.typedTags = tags; changed = true }
            }
            if record.isStarred == false && legacy.legacyFavourite(forFingerprint: lut.contentHash) {
                record.isStarred = true
                changed = true
            }
            records[id] = record
        }
        if changed { persist() }
    }

    func flush() { persist() }

    private func mutate(_ ids: Set<LUTRecordID>, _ body: (inout LUTRecord) -> Void) {
        var changed = false
        for id in ids where records[id] != nil {
            body(&records[id]!)
            changed = true
        }
        if changed { persist() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? Self.decoder.decode(Snapshot.self, from: data)
        else { return }
        records = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.id, $0) })
        collections = snapshot.collections
    }

    private func persist() { _ = persistReportingFailure() }

    private func persistReportingFailure() -> Bool {
        let snapshot = Snapshot(records: Array(records.values), collections: collections)
        guard let data = try? Self.encoder.encode(snapshot) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func normalized(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isInside(_ locator: String, root: String) -> Bool {
        locator == root || locator.hasPrefix(root + "/")
    }
}
