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

    var discoveryID: String {
        switch self {
        case .vendor(let name): return "vendor:\(name.localizedLowercase)"
        case .custom: return "custom"
        case .unknown: return "unknown"
        }
    }
}

struct LUTRecord: Identifiable, Codable, Sendable, Equatable {
    let id: LUTRecordID
    var locator: String
    var bookmark: Data?
    /// Nil means the bookmark resolves the file itself. A value means the
    /// bookmark resolves an ancestor directory and this relative path locates
    /// the file inside it (needed when a brand-new save target cannot yet make
    /// a file bookmark).
    var bookmarkRelativePath: String? = nil
    var fingerprint: String
    var isAvailable: Bool
    var displayNameOverride: String?
    /// Human-readable provenance or usage context. It is record metadata, not
    /// a CUBE comment, so third-party transform bytes remain untouched.
    var descriptionText: String? = nil
    var origin: LUTOrigin = .unknown
    /// The precise encoded pixels this transform expects (for example
    /// Panasonic V-Log or Sony S-Log3). This is catalog metadata and remains
    /// separate from both the emulated-look Brand and descriptive Tags.
    var inputProfile: String? = nil
    var typedTags: [String] = []
    /// Per-record curation of content-level measured tags. Optional keeps
    /// catalogs written before this field was introduced decode-compatible.
    /// The measurement itself remains shared by content hash; hiding it here
    /// lets identical physical files be organised independently.
    var excludedMeasuredTags: [String]?
    var isStarred: Bool = false
    var collectionIDs: Set<UUID> = []
    /// A repository manifest is an initial seed, not a live policy engine.
    /// Once considered, rescans must not put metadata back after a user edit.
    var curatedMetadataSeed: String? = nil
    /// A one-time compatibility repair for catalogs created before Brand was
    /// persisted. Optional keeps legacy snapshots decode-compatible.
    var legacyBrandInferenceVersion: Int? = nil

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
        /// Old transient references that must continue to resolve after a
        /// crash interrupted document/session adoption. Optional so version-1
        /// catalogs written before recovery aliases remain readable.
        var identityAliases: [String: String]?
    }

    private struct SaveRecovery: Codable {
        let locator: String
        let bookmark: Data?
        let bookmarkRelativePath: String?
        let transientID: LUTRecordID?
        let expectedFingerprint: String?
    }

    @Published private(set) var records: [LUTRecordID: LUTRecord] = [:]
    @Published private(set) var collections: [LUTCollectionRecord] = []
    private var identityAliases: [String: String] = [:]

    private let fileURL: URL
    private let recoveryURL: URL

    init(fileURL: URL? = nil) {
        let fileURL = fileURL ?? Self.defaultURL()
        self.fileURL = fileURL
        self.recoveryURL = fileURL.appendingPathExtension("save-recovery")
        load()
        recoverPendingSave()
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

    func record(for id: LUTRecordID) -> LUTRecord? { records[resolvedRecordID(for: id)] }

    func record(for lut: CubeLUT) -> LUTRecord? { record(for: lut.lutID) }

    func recordID(for locator: URL) -> LUTRecordID? {
        let path = Self.normalized(locator)
        return records.values.first { $0.locator == path }?.id
    }

    /// Resolve and parse a catalogued LUT that is not part of the active scan
    /// root. This is what makes an explicitly saved outside-root LUT survive a
    /// relaunch instead of leaving a durable ID that cannot produce pixels.
    func loadLUT(for id: LUTRecordID) -> CubeLUT? {
        let durableID = resolvedRecordID(for: id)
        guard var record = records[durableID] else { return nil }
        var url = record.url
        var scopeURL: URL?
        var didAccessSecurityScope = false

        if let bookmark = record.bookmark {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                scopeURL = resolved
                url = record.bookmarkRelativePath.map {
                    resolved.appendingPathComponent($0)
                } ?? resolved
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
            if didAccessSecurityScope { scopeURL?.stopAccessingSecurityScopedResource() }
        }

        guard FileManager.default.fileExists(atPath: url.path),
              let parsed = try? CubeLUT(url: url, category: "External")
        else {
            if record.isAvailable {
                record.isAvailable = false
                records[durableID] = record
                persist()
            }
            return nil
        }

        record.locator = Self.normalized(url)
        record.fingerprint = parsed.contentHash
        record.isAvailable = true
        records[durableID] = record
        persist()
        return parsed.withRecordID(durableID)
    }

    func effectiveName(for lut: CubeLUT) -> String {
        guard let override = record(for: lut)?.displayNameOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines), override.isEmpty == false
        else { return lut.name }
        return override
    }

    func origin(for lut: CubeLUT) -> LUTOrigin { record(for: lut)?.origin ?? .unknown }
    func inputProfile(for lut: CubeLUT) -> String {
        if let value = record(for: lut)?.inputProfile?
            .trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false {
            return value
        }
        return lut.inputSpace == .vlog ? "Panasonic V-Log" : "Display / Rec.709"
    }
    func description(for id: LUTRecordID) -> String { record(for: id)?.descriptionText ?? "" }
    func description(for lut: CubeLUT) -> String { description(for: lut.lutID) }
    func typedTags(for lut: CubeLUT) -> [String] { record(for: lut)?.typedTags ?? [] }
    func excludedMeasuredTags(for id: LUTRecordID) -> [String] {
        record(for: id)?.excludedMeasuredTags ?? []
    }
    func excludedMeasuredTags(for lut: CubeLUT) -> [String] {
        excludedMeasuredTags(for: lut.lutID)
    }
    func isStarred(_ lut: CubeLUT) -> Bool { record(for: lut)?.isStarred ?? false }

    func setDisplayName(_ name: String?, for ids: Set<LUTRecordID>) {
        let cleaned = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(ids) { $0.displayNameOverride = cleaned?.isEmpty == false ? cleaned : nil }
    }

    func setDescription(_ description: String?, for ids: Set<LUTRecordID>) {
        let cleaned = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(ids) { $0.descriptionText = cleaned?.isEmpty == false ? cleaned : nil }
    }

    /// Seed repository-curated metadata exactly once per durable record.
    /// Existing non-empty values win so adding sidecar support cannot erase a
    /// catalog that the user already curated before this version.
    func seedCuratedMetadata(
        _ metadataByFingerprint: [String: CuratedLUTMetadata],
        for luts: [CubeLUT]
    ) {
        var changed = false
        for lut in luts {
            guard let metadata = metadataByFingerprint[lut.contentHash],
                  var record = records[lut.lutID]
            else { continue }

            var recordChanged = false
            if record.curatedMetadataSeed == nil {
                if record.descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
                   metadata.description.isEmpty == false {
                    record.descriptionText = metadata.description
                }
                if record.origin == .unknown { record.origin = metadata.origin }
                record.typedTags = Array(Set(record.typedTags + metadata.tags)).sorted()
                record.curatedMetadataSeed = metadata.seedID
                recordChanged = true
            }
            if record.inputProfile?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                record.inputProfile = metadata.inputProfile
                recordChanged = true
            }
            if recordChanged {
                records[lut.lutID] = record
                changed = true
            }
        }
        if changed { persist() }
    }

    /// Repair the old local library shown before Brand metadata existed. Only
    /// strong top-level folder or filename-prefix evidence participates, and a
    /// record is considered once so a later user-authored Unknown remains so.
    func inferMissingOrigins(for luts: [CubeLUT]) {
        var changed = false
        for lut in luts {
            guard var record = records[lut.lutID],
                  record.legacyBrandInferenceVersion == nil
            else { continue }
            if record.origin == .unknown,
               let inferred = Self.inferredLegacyOrigin(for: lut) {
                record.origin = inferred
            }
            // "Considered" is itself durable state. Without this marker on a
            // seeded/vendor/custom record, a later authored Unknown would be
            // mistaken for legacy missing metadata and silently overwritten.
            record.legacyBrandInferenceVersion = 1
            records[lut.lutID] = record
            changed = true
        }
        if changed { persist() }
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
            $0.excludedMeasuredTags?.removeAll { $0 == cleaned }
            if $0.excludedMeasuredTags?.isEmpty == true { $0.excludedMeasuredTags = nil }
            guard $0.typedTags.contains(cleaned) == false else { return }
            $0.typedTags.append(cleaned)
            $0.typedTags.sort()
        }
    }

    func removeTag(
        _ tag: String,
        from ids: Set<LUTRecordID>,
        hidingMeasuredFor measuredIDs: Set<LUTRecordID> = []
    ) {
        mutate(ids) {
            $0.typedTags.removeAll { $0 == tag }
            guard measuredIDs.contains($0.id) else { return }
            var excluded = Set($0.excludedMeasuredTags ?? [])
            excluded.insert(tag)
            $0.excludedMeasuredTags = excluded.sorted()
        }
    }

    @discardableResult
    func createCollection(named name: String) -> LUTCollectionRecord? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return nil }
        let previous = collections
        let now = Date()
        let item = LUTCollectionRecord(id: UUID(), name: cleaned, createdAt: now, updatedAt: now)
        collections.append(item)
        collections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard persistReportingFailure() else {
            collections = previous
            return nil
        }
        return item
    }

    /// Create the Manager workflow's required non-empty Collection in one
    /// catalog write, so interruption cannot leave an empty definition behind.
    @discardableResult
    func createCollection(
        named name: String, containing recordIDs: Set<LUTRecordID>
    ) -> LUTCollectionRecord? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false,
              recordIDs.isEmpty == false,
              recordIDs.allSatisfy({ records[$0] != nil })
        else { return nil }

        let previousCollections = collections
        let previousRecords = records
        let now = Date()
        let item = LUTCollectionRecord(id: UUID(), name: cleaned, createdAt: now, updatedAt: now)
        collections.append(item)
        collections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for id in recordIDs { records[id]?.collectionIDs.insert(item.id) }
        guard persistReportingFailure() else {
            collections = previousCollections
            records = previousRecords
            return nil
        }
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

    /// Persist intent before a derived LUT replaces anything at `destination`.
    /// If the process stops after the file write but before catalog adoption,
    /// the marker lets the next launch finish the same adoption deterministically.
    func beginSaveRecovery(
        for destination: URL,
        replacing transientID: LUTRecordID? = nil,
        expectedFingerprint: String? = nil,
        bookmark: Data? = nil,
        bookmarkRelativePath: String? = nil
    ) -> Bool {
        let marker = SaveRecovery(
            locator: Self.normalized(destination), bookmark: bookmark,
            bookmarkRelativePath: bookmarkRelativePath,
            transientID: transientID, expectedFingerprint: expectedFingerprint
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(marker) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: recoveryURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// A failed file write never needs launch recovery; discard only the marker
    /// for that exact destination so a different pending save is not erased.
    func cancelSaveRecovery(for destination: URL) {
        clearSaveRecovery(matching: Self.normalized(destination))
    }

    /// Adopt a successfully written LUT immediately, including paths outside
    /// the scanned root. Known locators retain record metadata.
    func adoptSavedLUT(
        _ lut: CubeLUT, bookmark: Data? = nil, bookmarkRelativePath: String? = nil,
        replacing transientID: LUTRecordID? = nil
    ) -> LUTRecordID? {
        let locator = Self.normalized(lut.url)
        if let existing = records.values.first(where: { $0.locator == locator })?.id {
            let previous = records[existing]
            let previousAliases = identityAliases
            records[existing]?.fingerprint = lut.contentHash
            records[existing]?.bookmark = bookmark ?? records[existing]?.bookmark
            if bookmark != nil { records[existing]?.bookmarkRelativePath = bookmarkRelativePath }
            records[existing]?.isAvailable = true
            registerAlias(from: transientID, to: existing)
            guard persistReportingFailure() else {
                if let previous { records[existing] = previous }
                identityAliases = previousAliases
                return nil
            }
            clearSaveRecovery(matching: locator)
            return existing
        }

        let id = LUTID(recordUUID: UUID())
        let previousAliases = identityAliases
        records[id] = LUTRecord(
            id: id, locator: locator, bookmark: bookmark,
            bookmarkRelativePath: bookmarkRelativePath,
            fingerprint: lut.contentHash, isAvailable: true
        )
        registerAlias(from: transientID, to: id)
        guard persistReportingFailure() else {
            records.removeValue(forKey: id)
            identityAliases = previousAliases
            return nil
        }
        clearSaveRecovery(matching: locator)
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
        identityAliases = snapshot.identityAliases ?? [:]
    }

    private func recoverPendingSave() {
        guard let data = try? Data(contentsOf: recoveryURL),
              let marker = try? JSONDecoder().decode(SaveRecovery.self, from: data)
        else { return }
        var url = URL(fileURLWithPath: marker.locator)
        var scopeURL: URL?
        var didAccessSecurityScope = false
        if let bookmark = marker.bookmark {
            var isStale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope], relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                // Keep the marker: access may become available after the user
                // remounts a volume or repairs permissions.
                return
            }
            scopeURL = resolved
            didAccessSecurityScope = resolved.startAccessingSecurityScopedResource()
            url = marker.bookmarkRelativePath.map {
                resolved.appendingPathComponent($0)
            } ?? resolved
        }
        defer {
            if didAccessSecurityScope { scopeURL?.stopAccessingSecurityScopedResource() }
        }
        guard FileManager.default.fileExists(atPath: url.path),
              let lut = try? CubeLUT(url: url, category: "Recovered")
        else {
            // With a persisted external scope, an access failure is retryable;
            // without one, absence proves the atomic replacement never landed.
            if marker.bookmark == nil { clearSaveRecovery(matching: marker.locator) }
            return
        }
        guard marker.expectedFingerprint == nil || marker.expectedFingerprint == lut.contentHash else {
            // The marker was written, but the atomic replacement never landed;
            // keep an existing destination untouched and discard the stale intent.
            clearSaveRecovery(matching: marker.locator)
            return
        }
        _ = adoptSavedLUT(
            lut, bookmark: marker.bookmark,
            bookmarkRelativePath: marker.bookmarkRelativePath,
            replacing: marker.transientID
        )
    }

    private func registerAlias(from transientID: LUTRecordID?, to durableID: LUTRecordID) {
        guard let transientID, transientID != durableID else { return }
        identityAliases[transientID.raw] = durableID.raw
    }

    private func resolvedRecordID(for id: LUTRecordID) -> LUTRecordID {
        var raw = id.raw
        var visited: Set<String> = []
        while let next = identityAliases[raw], visited.insert(raw).inserted {
            raw = next
        }
        return LUTRecordID(raw: raw)
    }

    private func clearSaveRecovery(matching locator: String) {
        guard let data = try? Data(contentsOf: recoveryURL),
              let marker = try? JSONDecoder().decode(SaveRecovery.self, from: data),
              marker.locator == locator
        else { return }
        try? FileManager.default.removeItem(at: recoveryURL)
    }

    private func persist() { _ = persistReportingFailure() }

    private func persistReportingFailure() -> Bool {
        let snapshot = Snapshot(
            records: Array(records.values), collections: collections,
            identityAliases: identityAliases.isEmpty ? nil : identityAliases
        )
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

    private static func inferredLegacyOrigin(for lut: CubeLUT) -> LUTOrigin? {
        let folder = lut.category.split(separator: "/").first.map(String.init) ?? ""
        let prefix = lut.name.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        let key = (folder.isEmpty || folder == "General" ? prefix : folder)
            .trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let names: [String: String] = [
            "arri": "ARRI", "blackmagic": "Blackmagic Design", "blackmagic design": "Blackmagic Design",
            "canon": "Canon", "dji": "DJI", "fuji": "Fujifilm", "fujifilm": "Fujifilm",
            "gopro": "GoPro", "hasselblad": "Hasselblad", "leica": "Leica", "nikon": "Nikon",
            "panasonic": "Panasonic", "panasonic-standard": "Panasonic", "red": "RED",
            "ricoh": "RICOH", "sony": "Sony"
        ]
        return names[key].map(LUTOrigin.vendor)
    }
}
