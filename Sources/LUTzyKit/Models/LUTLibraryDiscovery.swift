import Foundation

/// The four ways the visual Library can turn one local source into shelves.
/// These are browsing facets, not new metadata owners: Manager still edits the
/// Origin, Tags, and Collections that feed them.
enum LUTLibraryGrouping: String, CaseIterable, Identifiable, Sendable {
    case folder
    case collectionAndStar
    case brand
    case tag

    var id: Self { self }

    var label: String {
        switch self {
        case .folder: return "Folder"
        case .collectionAndStar: return "Collection & Star"
        case .brand: return "Brand"
        case .tag: return "Tag"
        }
    }

    var symbol: String {
        switch self {
        case .folder: return "folder"
        case .collectionAndStar: return "rectangle.stack.badge.person.crop"
        case .brand: return "building.2"
        case .tag: return "tag"
        }
    }
}

/// One horizontal row on the discovery home and the payload for its complete
/// Grid. The ID is semantic so a shelf keeps its navigation identity while
/// metadata edits replace or reorder the LUT values inside it.
struct LUTLibraryShelf: Identifiable, Sendable {
    let id: String
    let title: String
    let luts: [CubeLUT]
}

enum LUTLibraryDiscovery {
    /// Roll physical categories into the immediate children of the active
    /// folder source. From All LUTs this yields top-level folders; from a
    /// selected folder it yields that folder's next level while keeping any
    /// LUTs stored directly in the selected folder in their own row.
    static func folderShelves(
        from luts: [CubeLUT],
        selectedFolder: String?
    ) -> [LUTLibraryShelf] {
        let base = selectedFolder?
            .split(separator: "/")
            .map(String.init) ?? []
        var groups: [String: (title: String, luts: [CubeLUT])] = [:]

        for lut in luts {
            let category = lut.category == "General"
                ? [] : lut.category.split(separator: "/").map(String.init)
            let relative = LUTFolderHierarchy.navigationComponents(
                Array(category.dropFirst(min(base.count, category.count))),
                ancestors: base
            )

            let path: String
            let title: String
            if let next = relative.first {
                let components = base + [next]
                path = components.joined(separator: "/")
                title = next
            } else if let selectedFolder, selectedFolder.isEmpty == false {
                path = selectedFolder
                title = base.last ?? selectedFolder
            } else {
                path = "General"
                title = "General"
            }

            if groups[path] == nil { groups[path] = (title, []) }
            groups[path]?.luts.append(lut)
        }

        return groups.map { path, group in
            LUTLibraryShelf(id: "folder:\(path)", title: group.title, luts: group.luts)
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
}

/// Stable keyboard and assistive-technology return points across the three
/// Library navigation levels. Card targets include their shelf because the
/// same LUT can legitimately appear in several discovery rows.
enum LUTLibraryFocusTarget: Hashable {
    case groupingControl
    case shelfHeading(String)
    case viewAll(String)
    case gridBack(String)
    case detailBack
    case homeCard(shelfID: String, lutID: LUTID)
    case gridCard(shelfID: String, lutID: LUTID)

    var isGridCard: Bool {
        if case .gridCard = self { return true }
        return false
    }

    var isCard: Bool {
        switch self {
        case .homeCard, .gridCard: return true
        default: return false
        }
    }

    /// Resolve a return point after metadata changes may have removed the
    /// originating card or its whole shelf from the active source.
    func resolved(in shelves: [LUTLibraryShelf]) -> LUTLibraryFocusTarget {
        switch self {
        case .groupingControl:
            return self
        case .shelfHeading(let shelfID), .viewAll(let shelfID), .gridBack(let shelfID):
            return shelves.contains(where: { $0.id == shelfID }) ? self : .groupingControl
        case .homeCard(let shelfID, let lutID):
            guard let shelf = shelves.first(where: { $0.id == shelfID }) else {
                return .groupingControl
            }
            return shelf.luts.contains(where: { $0.lutID == lutID })
                ? self : .shelfHeading(shelfID)
        case .gridCard(let shelfID, let lutID):
            guard let shelf = shelves.first(where: { $0.id == shelfID }) else {
                return .groupingControl
            }
            return shelf.luts.contains(where: { $0.lutID == lutID })
                ? self : .gridBack(shelfID)
        case .detailBack:
            return .groupingControl
        }
    }
}
