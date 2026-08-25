import Foundation

enum LUTSource: Hashable, Sendable {
    case all
    case folder(String)
    case collection(UUID)
    case starred

    var title: String {
        switch self {
        case .all: return "All LUTs"
        case .folder(let path): return path.split(separator: "/").last.map(String.init) ?? path
        case .collection: return "Collection"
        case .starred: return "Starred"
        }
    }
}

enum LUTWorkspaceContext: Sendable {
    case viewer
    case library
    case manager
}
