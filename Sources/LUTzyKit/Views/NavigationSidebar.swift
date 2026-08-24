import SwiftUI

/// What the app is being used for right now.
///
/// The app grew three jobs that were sharing one screen: keeping a library
/// (importing, tagging, filing), looking at pictures through it, and — later —
/// building a LUT. They want different room. A viewer wants the whole window
/// for the picture; a manager wants a table it can survey and act on in bulk.
/// Splitting them means neither has to apologise to the other.
enum AppSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case viewer
    case manager
    case editor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .viewer: return "Viewer"
        case .manager: return "Manager"
        case .editor: return "Editor"
        }
    }

    var symbol: String {
        switch self {
        case .viewer: return "photo"
        case .manager: return "square.grid.2x2"
        case .editor: return "slider.horizontal.3"
        }
    }

    /// The editor is listed before it exists on purpose: it says where the app
    /// is going, and an empty section that explains itself is better than a
    /// feature appearing one day with no warning.
    var isAvailable: Bool { self != .editor }
}

/// The app's navigation column: what you are doing, and what you are looking at.
///
/// Two groups, because they answer different questions. **Workspace** is the
/// mode. **Library** is the scope — every folder, plus the two views across all
/// of them (everything, and starred), which are exactly the shortcuts a library
/// gets used through once it is past a hundred files.
struct NavigationSidebar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        List(selection: navigationSelection) {
            Section("Workspace") {
                ForEach(AppSection.allCases) { section in
                    Label(section.label, systemImage: section.symbol)
                        .foregroundStyle(section.isAvailable ? .primary : .tertiary)
                        .tag(NavigationTarget.section(section))
                }
            }

            Section("Library") {
                Label("All LUTs", systemImage: "square.stack.3d.up")
                    .badge(viewModel.library.allLUTs.count)
                    .tag(NavigationTarget.everything)
                Label("Starred", systemImage: "star")
                    .badge(viewModel.tags.favouriteCount)
                    .tag(NavigationTarget.starred)
            }

            if viewModel.folderTiles.isEmpty == false {
                Section("Folders") {
                    ForEach(viewModel.folderTiles, id: \.name) { folder in
                        Label(folder.name, systemImage: "folder")
                            .badge(folder.count)
                            .tag(NavigationTarget.folder(folder.name))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            // Importing lives at the bottom of the navigation rather than
            // buried in a menu: it is the one thing a new library needs, and
            // the one thing an old one needs repeatedly.
            Button {
                viewModel.importLUTs()
            } label: {
                Label("Import LUTs…", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 170, idealWidth: 190, maxWidth: 240)
    }

    /// One selection for two kinds of row.
    ///
    /// A mode and a scope are independent — browsing the Fuji folder while in
    /// the viewer is a normal thing to want — but they share a list, so the
    /// selection reads back whichever of the two the user touched last.
    private var navigationSelection: Binding<NavigationTarget?> {
        Binding(
            get: {
                if viewModel.showingFavouritesOnly { return .starred }
                if let folder = viewModel.browsedCategory { return .folder(folder) }
                return .section(viewModel.section)
            },
            set: { target in
                guard let target else { return }
                switch target {
                case .section(let section):
                    guard section.isAvailable else { return }
                    viewModel.section = section
                case .everything:
                    viewModel.showingFavouritesOnly = false
                    viewModel.browse(nil)
                case .starred:
                    viewModel.showingFavouritesOnly = true
                    viewModel.browse(nil)
                case .folder(let name):
                    viewModel.showingFavouritesOnly = false
                    viewModel.browse(name)
                }
            }
        )
    }
}

/// A row in the navigation column.
enum NavigationTarget: Hashable {
    case section(AppSection)
    case everything
    case starred
    case folder(String)
}
