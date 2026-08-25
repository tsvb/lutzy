import Foundation

/// A directory in the LUT library, including the LUTs stored in descendants.
///
/// `LUTLibrary.Category` keeps the complete relative path (for example
/// `Sony/VENICE/Creative`). This type turns those flat paths back into the
/// hierarchy people recognise on disk without changing how the library is
/// stored.
struct LUTFolderNode: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let count: Int
    let children: [LUTFolderNode]

    var id: String { path }
}

enum LUTFolderHierarchy {
    /// Whether a category belongs to a selected folder. Selecting a parent is
    /// recursive: `Sony` includes both `Sony` and `Sony/VENICE`, but never a
    /// neighbouring folder such as `Sony Pictures`.
    static func contains(categoryPath: String, in selectedFolder: String?) -> Bool {
        guard let selectedFolder, selectedFolder.isEmpty == false else { return true }
        return categoryPath == selectedFolder || categoryPath.hasPrefix(selectedFolder + "/")
    }

    /// Build an outline from direct LUT counts keyed by complete folder path.
    /// Parent counts are roll-ups, so the number beside `Sony` describes what
    /// selecting Sony will actually reveal in the Viewer.
    static func tree(from directCounts: [String: Int]) -> [LUTFolderNode] {
        var paths = Set<String>()

        for rawPath in directCounts.keys {
            let parts = rawPath.split(separator: "/").map(String.init)
            guard parts.isEmpty == false else { continue }
            for depth in 1...parts.count {
                paths.insert(parts.prefix(depth).joined(separator: "/"))
            }
        }

        func parent(of path: String) -> String? {
            let parts = path.split(separator: "/")
            guard parts.count > 1 else { return nil }
            return parts.dropLast().joined(separator: "/")
        }

        func makeNode(_ path: String) -> LUTFolderNode {
            let children = paths
                .filter { parent(of: $0) == path }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map(makeNode)
            let count = directCounts.reduce(into: 0) { total, item in
                if contains(categoryPath: item.key, in: path) { total += item.value }
            }
            return LUTFolderNode(
                path: path,
                name: path.split(separator: "/").last.map(String.init) ?? path,
                count: count,
                children: children
            )
        }

        return paths
            .filter { parent(of: $0) == nil }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map(makeNode)
    }
}
