import Foundation

/// A small process-local cache for UI features that need to sample a LUT table
/// repeatedly. Library discovery stays header-only; Inspector and Editor pay
/// for a background parse once, then reuse the immutable table.
actor LUTMaterializationCache {
    private let capacity: Int
    private var completed: [String: CubeLUT] = [:]
    private var order: [String] = []
    private var inFlight: [String: Task<CubeLUT?, Never>] = [:]

    init(capacity: Int = 4) {
        self.capacity = max(capacity, 1)
    }

    func materialized(_ source: CubeLUT) async -> CubeLUT? {
        if source.retainsTableData { return source }
        // Identical tables can legitimately have different catalog identity,
        // name, or Input Profile. Include those semantics so a cached table
        // never returns another record's metadata to Editor or Inspector.
        let key = "\(source.lutID.raw)|\(source.inputSpace.rawValue)|\(source.contentHash)"
        if let cached = completed[key] {
            touch(key)
            return cached
        }

        let worker: Task<CubeLUT?, Never>
        if let existing = inFlight[key] {
            worker = existing
        } else {
            worker = Task.detached(priority: .userInitiated) {
                source.materialized()
            }
            inFlight[key] = worker
        }

        let result = await worker.value
        inFlight[key] = nil
        guard Task.isCancelled == false, let result else { return nil }
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
