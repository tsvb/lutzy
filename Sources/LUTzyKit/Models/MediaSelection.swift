import Foundation

/// Finder-like selection helper shared by Media Library presentations.
enum ImageManagerSelection {
    static func selecting(
        _ id: String,
        orderedIDs: [String],
        current: Set<String>,
        anchor: String?,
        toggling: Bool,
        extending: Bool
    ) -> (selection: Set<String>, anchor: String) {
        if extending,
           let anchor,
           let start = orderedIDs.firstIndex(of: anchor),
           let end = orderedIDs.firstIndex(of: id) {
            let bounds = min(start, end)...max(start, end)
            let range = Set(bounds.map { orderedIDs[$0] })
            return (toggling ? current.union(range) : range, anchor)
        }
        if toggling {
            var updated = current
            if updated.contains(id) { updated.remove(id) } else { updated.insert(id) }
            return (updated, id)
        }
        return ([id], id)
    }
}
