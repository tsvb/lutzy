import Foundation

/// A small process-local cache for UI features that need to sample a LUT table
/// repeatedly. Library discovery stays header-only; Inspector and Editor pay
/// for a background parse once, then reuse the immutable table.
actor LUTMaterializationCache {
    private let capacity: Int
    private var completed: [String: CubeLUT] = [:]
    private var order: [String] = []
    private var activeParses = 0
    private(set) var peakParseCount = 0

    init(capacity: Int = 4) {
        self.capacity = max(capacity, 1)
    }

    func materialized(_ source: CubeLUT) async -> CubeLUT? {
        if source.retainsTableData { return source }
        // Identical tables can legitimately have different catalog identity,
        // name, location, or Input Profile. Include those semantics so a cached
        // table never returns stale metadata to Editor or Inspector.
        let key = [
            source.lutID.raw, source.id, source.name, source.category,
            source.inputSpace.rawValue, source.contentHash,
        ].joined(separator: "|")
        if let cached = completed[key] {
            touch(key)
            return cached
        }

        // Actor isolation serialises all cache misses, globally bounding parse
        // concurrency to one. The parser runs on this actor's executor—not the
        // MainActor—and sees caller cancellation while walking file lines.
        activeParses += 1
        peakParseCount = max(peakParseCount, activeParses)
        defer { activeParses -= 1 }
        guard Task.isCancelled == false,
              let result = source.materialized(),
              Task.isCancelled == false
        else { return nil }
        insert(result, for: key)
        return result
    }

    func sample(_ points: [Float], from source: CubeLUT) async -> [Float]? {
        guard let lut = await materialized(source), Task.isCancelled == false else { return nil }
        return lut.sample(points)
    }

    var count: Int { completed.count }

    private func insert(_ lut: CubeLUT, for key: String) {
        completed[key] = lut
        touch(key)
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            completed[oldest] = nil
        }
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
