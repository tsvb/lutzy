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
    /// Components that preserve provenance or file-format packaging on disk
    /// but add no useful browsing choice. Arbitrary authored nesting remains
    /// intact; only this narrow vocabulary and repeated ancestor labels are
    /// hidden from navigation.
    static func isNavigationNoise(_ component: String, ancestors: [String]) -> Bool {
        let cleaned = component.trimmingCharacters(in: .whitespacesAndNewlines)
        if ancestors.contains(where: {
            $0.localizedCaseInsensitiveCompare(cleaned) == .orderedSame
        }) { return true }

        let token = cleaned.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return [
            "documents collection",
            "3dlut",
            "3d lut",
            "3d luts",
            "full to full range",
        ].contains(token)
    }

    static func navigationComponents(_ components: [String], ancestors: [String]) -> [String] {
        var visible: [String] = []
        var context = ancestors
        for component in components {
            guard isNavigationNoise(component, ancestors: context) == false else { continue }
            visible.append(component)
            context.append(component)
        }
        return visible
    }

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

        func childPaths(of path: String) -> [String] {
            paths
                .filter { parent(of: $0) == path }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        func displayedChildren(of path: String, ancestors: [String]) -> [LUTFolderNode] {
            childPaths(of: path).flatMap { childPath -> [LUTFolderNode] in
                let childName = childPath.split(separator: "/").last.map(String.init) ?? childPath
                if isNavigationNoise(childName, ancestors: ancestors) {
                    return displayedChildren(of: childPath, ancestors: ancestors)
                }
                return [makeNode(childPath, ancestors: ancestors + [childName])]
            }
        }

        func makeNode(_ path: String, ancestors: [String]) -> LUTFolderNode {
            let children = displayedChildren(of: path, ancestors: ancestors)
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
            .map { path in
                let name = path.split(separator: "/").last.map(String.init) ?? path
                return makeNode(path, ancestors: [name])
            }
    }
}
