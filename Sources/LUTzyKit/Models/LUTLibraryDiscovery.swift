import Foundation

/// The three ways the visual Library can turn one local source into shelves.
/// These are browsing facets, not new metadata owners: Manager still edits the
/// Origin, Tags, and Collections that feed them.
enum LUTLibraryGrouping: String, CaseIterable, Identifiable, Sendable {
    case brand
    case tag
    case collection

    var id: Self { self }

    var label: String {
        switch self {
        case .brand: return "Brand"
        case .tag: return "Tag"
        case .collection: return "Collection"
        }
    }

    var symbol: String {
        switch self {
        case .brand: return "building.2"
        case .tag: return "tag"
        case .collection: return "rectangle.stack"
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
