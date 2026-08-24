import Foundation
import Combine

/// Tags for a LUT collection, keyed by what the file *contains*.
///
/// Keyed by content hash rather than by path so a rename, a move, or a copy
/// into another folder keeps its tags — the thing being described is the
/// transform, not where it happens to sit today.
///
/// Two kinds of tag, and the difference is the whole design:
///
/// - **measured** tags come from `LUTProfiler` and are replaced on every scan.
///   They are what the file objectively does, so a rescan re-deriving them is
///   correct; a stale "高對比" on a LUT that was edited would be a lie.
/// - **typed** tags are personal vocabulary — 日系, 這次婚禮用 — and are never
///   touched by a rescan. Nothing measurable could reproduce them, so losing
///   them to an automated pass is unrecoverable.
///
/// Stored as JSON rather than SQLite: a LUT library is hundreds of rows, not
/// millions, the whole file is read once at launch, and a JSON file is
/// something the user can open, diff, and back up.
@MainActor
final class LUTTagStore: ObservableObject {

    struct Entry: Codable, Equatable {
        var name: String
        var inputSpace: String
        var metrics: LUTMetrics
        var measured: [String]
        var typed: [String]
        /// Starred. A flag rather than a reserved tag: a favourite is not a
        /// description of the LUT, and putting it in the tag vocabulary would
        /// mean it turned up in the filter row alongside 高對比.
        var isFavourite: Bool = false
        /// Which version of the measuring rules produced `measured`. Without
        /// it, an entry measured once is never measured again, and improving
        /// the tagger would leave every existing library describing itself by
        /// the old rules forever.
        var taggerVersion: Int = 0
    }

    /// Bump when `LUTProfiler`'s metrics or thresholds change. Every entry below
    /// this is re-measured on the next scan; typed tags are unaffected.
    static let taggerVersion = 1

    /// Everything known, by content hash.
    @Published private(set) var entries: [String: Entry] = [:]

    /// Every tag in use, measured and typed together, with how many LUTs carry
    /// it — the filter list, in one pass.
    @Published private(set) var counts: [(tag: String, count: Int)] = []

    private let fileURL: URL
    /// Coalesces the writes a burst of tagging would otherwise cause.
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
        load()
    }

    private static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("LUTStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("lut-tags.json")
    }

    // MARK: - Reading

    func tags(for lut: CubeLUT) -> [String] {
        guard let entry = entries[lut.contentHash] else { return [] }
        return (entry.measured + entry.typed).sorted()
    }

    func typedTags(for lut: CubeLUT) -> [String] {
        entries[lut.contentHash]?.typed ?? []
    }

    func isFavourite(_ lut: CubeLUT) -> Bool {
        entries[lut.contentHash]?.isFavourite ?? false
    }

    var favouriteCount: Int {
        entries.values.filter(\.isFavourite).count
    }

    /// Star or unstar. Creates an entry if the LUT has never been measured —
    /// starring something should not depend on a scan having reached it yet.
    func toggleFavourite(_ lut: CubeLUT) {
        var entry = entries[lut.contentHash] ?? Entry(
            name: lut.name, inputSpace: lut.inputSpace == .vlog ? "vlog" : "display",
            metrics: LUTProfiler.measure(lut), measured: [], typed: [], taggerVersion: 0
        )
        entry.isFavourite.toggle()
        entries[lut.contentHash] = entry
        scheduleSave()
    }

    func metrics(for lut: CubeLUT) -> LUTMetrics? {
        entries[lut.contentHash]?.metrics
    }

    /// Whether a LUT carries every one of `required`. An empty requirement
    /// matches everything, so a cleared filter is not a special case.
    func matches(_ lut: CubeLUT, required: Set<String>) -> Bool {
        guard required.isEmpty == false else { return true }
        return required.isSubset(of: Set(tags(for: lut)))
    }

    // MARK: - Writing

    /// Add a typed tag. Measured tags are not addable by hand — they are
    /// claims about the file, and one typed over the top would survive a
    /// rescan that disagreed with it.
    func addTag(_ tag: String, to lut: CubeLUT) {
        let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return }
        var entry = entries[lut.contentHash] ?? Entry(
            name: lut.name, inputSpace: lut.inputSpace == .vlog ? "vlog" : "display",
            metrics: LUTProfiler.measure(lut), measured: [], typed: [], taggerVersion: 0
        )
        guard entry.typed.contains(cleaned) == false else { return }
        entry.typed.append(cleaned)
        entry.typed.sort()
        entries[lut.contentHash] = entry
        refreshCounts()
        scheduleSave()
    }

    func removeTag(_ tag: String, from lut: CubeLUT) {
        guard var entry = entries[lut.contentHash] else { return }
        entry.typed.removeAll { $0 == tag }
        entries[lut.contentHash] = entry
        refreshCounts()
        scheduleSave()
    }

    /// Measure and record a whole library, keeping every typed tag.
    ///
    /// The measuring runs off the main actor: it samples 91 probe points per
    /// LUT through a tetrahedral interpolation, which is fast for one file and
    /// not free for three hundred.
    func index(_ luts: [CubeLUT]) async {
        let pending = unmeasured(among: luts)
        guard pending.isEmpty == false else { return }
        let measured = await Task.detached { Self.measure(pending) }.value
        apply(measured)
    }

    /// The same work on the calling actor.
    ///
    /// For a handful of LUTs, and for `lutcheck`, which drives the view model
    /// from a run loop: hopping off the main actor and back needs that actor to
    /// be free to run continuations, and a test that blocks it waiting for the
    /// result would wait forever.
    func indexNow(_ luts: [CubeLUT]) {
        let pending = unmeasured(among: luts)
        guard pending.isEmpty == false else { return }
        apply(Self.measure(pending))
    }

    /// What still needs measuring: never seen, or measured by older rules.
    ///
    /// Note the key is the LUT's *contents*, so a file edited in place is a new
    /// entry rather than an update — which is right for the measured tags and
    /// does mean typed tags do not follow an edit. An edited LUT is a different
    /// transform; a renamed one is not.
    private func unmeasured(among luts: [CubeLUT]) -> [CubeLUT] {
        luts.filter { lut in
            guard let entry = entries[lut.contentHash] else { return true }
            return entry.measured.isEmpty || entry.taggerVersion < Self.taggerVersion
        }
    }

    private nonisolated static func measure(_ luts: [CubeLUT]) -> [(String, String, String, LUTMetrics, [String])] {
        luts.map { lut in
            let metrics = LUTProfiler.measure(lut)
            return (lut.contentHash, lut.name,
                    lut.inputSpace == .vlog ? "vlog" : "display",
                    metrics,
                    LUTProfiler.autoTags(metrics, inputSpace: lut.inputSpace))
        }
    }

    private func apply(_ measured: [(String, String, String, LUTMetrics, [String])]) {
        for (hash, name, space, metrics, tags) in measured {
            var entry = entries[hash] ?? Entry(name: name, inputSpace: space, metrics: metrics, measured: [], typed: [])
            entry.name = name
            entry.inputSpace = space
            entry.metrics = metrics
            entry.measured = tags     // replaced wholesale; `typed` is untouched
            entry.taggerVersion = Self.taggerVersion
            entries[hash] = entry
        }
        refreshCounts()
        scheduleSave()
    }

    // MARK: - Persistence

    private func refreshCounts() {
        var tally: [String: Int] = [:]
        for entry in entries.values {
            for tag in Set(entry.measured + entry.typed) { tally[tag, default: 0] += 1 }
        }
        // Commonest first, alphabetical within a count: the list is scanned by
        // eye, and a stable order is what makes that possible.
        counts = tally.map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.tag < $1.tag : $0.count > $1.count }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return }
        entries = decoded
        refreshCounts()
    }

    /// Debounced: tagging is a burst of small edits, and each one rewriting the
    /// whole file would be the only slow thing about it.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = entries
        let url = fileURL
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard Task.isCancelled == false else { return }
            await Task.detached {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                guard let data = try? encoder.encode(snapshot) else { return }
                try? data.write(to: url, options: .atomic)
            }.value
        }
    }

    /// Mark every entry as measured by older rules, so the next index
    /// re-measures it. What a tagger-version bump does, on demand — used by
    /// `lutcheck` to prove a real rescan preserves typed tags.
    func forceRemeasure() {
        for key in entries.keys { entries[key]?.taggerVersion = -1 }
    }

    /// Write now rather than on the debounce. For tests and for quitting.
    func flush() {
        saveTask?.cancel()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
