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
    var isAvailable: Bool { true }
}

/// The app's navigation column: what you are doing, and what you are looking at.
///
/// Two groups, because they answer different questions. **Workspace** is the
/// mode. **Library** is the scope — every folder, plus the two views across all
/// of them (everything, and starred), which are exactly the shortcuts a library
/// gets used through once it is past a hundred files.
struct NavigationSidebar: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var isNaming = false
    @State private var newProjectName = ""
    @State private var renaming: Project?

    var body: some View {
        List(selection: navigationSelection) {
            projectSection
            Section("Workspace") {
                ForEach(AppSection.allCases) { section in
                    Label(section.label, systemImage: section.symbol)
                        .tag(NavigationTarget.section(section))
                }
            }

            if viewModel.projects.current != nil {
                Section("Images") {
                    Label("All Images", systemImage: "photo.on.rectangle")
                        .badge(viewModel.collection.items.count)
                        .tag(NavigationTarget.images)
                    // Both ways in, in one place. They used to be split
                    // between here and a toolbar menu that said "Import" with
                    // no tooltip, which meant two places to look for one thing.
                    Menu {
                        Button("From Files…") { viewModel.importImages() }
                        Button("From Photos…") { viewModel.importFromPhotos() }
                    } label: {
                        Label("Import Images…", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Copy images into this project")
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
            Menu {
                Button("Import LUTs…") { viewModel.importLUTs() }
                Divider()
                Button("Use a LUT Folder…") { viewModel.chooseLUTFolder() }
                if viewModel.library.isManaged == false, let folder = viewModel.library.folderURL {
                    Text("Currently: \(folder.lastPathComponent)")
                    Button("Back to the App's Library") { viewModel.library.useManagedFolder() }
                }
            } label: {
                Label("Import LUTs…", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .help("Copy LUTs into the app's library, or point the library at a folder of your own")
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 170, idealWidth: 190, maxWidth: 240)
    }

    /// The open project, and a way to switch. At the top because everything
    /// below it — the images, the workspace, what was on screen last time —
    /// belongs to whichever one this is.
    @ViewBuilder
    private var projectSection: some View {
        Section("Project") {
            Menu {
                ForEach(viewModel.projects.projects) { project in
                    Button {
                        viewModel.openProject(project)
                    } label: {
                        if project.id == viewModel.projects.current?.id {
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
                        }
                    }
                }
                if viewModel.projects.projects.isEmpty == false { Divider() }
                Button("New Project…") { newProjectName = ""; isNaming = true }
                if let current = viewModel.projects.current {
                    Button("Rename…") { newProjectName = current.name; renaming = current }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([viewModel.projects.folder(for: current)])
                    }
                    Divider()
                    Button("Delete Project", role: .destructive) { viewModel.deleteProject(current) }
                }
            } label: {
                Label(viewModel.projects.current?.name ?? "No Project", systemImage: "folder.badge.gearshape")
            }
        }
        .sheet(isPresented: $isNaming) {
            nameSheet(title: "New Project", action: { viewModel.createProject(named: $0) })
        }
        .sheet(item: $renaming) { project in
            nameSheet(title: "Rename Project", action: { viewModel.projects.rename(project, to: $0) })
        }
    }

    private func nameSheet(title: String, action: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Name", text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit(action) }
            HStack {
                Spacer()
                Button("Cancel") { isNaming = false; renaming = nil }
                Button("OK") { commit(action) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func commit(_ action: (String) -> Void) {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }
        action(name)
        isNaming = false
        renaming = nil
    }

    /// One selection for two kinds of row.
    ///
    /// A mode and a scope are independent — browsing the Fuji folder while in
    /// the viewer is a normal thing to want — but they share a list, so the
    /// selection reads back whichever of the two the user touched last.
    private var navigationSelection: Binding<NavigationTarget?> {
        Binding(
            get: {
                if viewModel.section == .manager && viewModel.managerTab == .images { return .images }
                if viewModel.showingFavouritesOnly { return .starred }
                if let folder = viewModel.browsedCategory { return .folder(folder) }
                return .section(viewModel.section)
            },
            set: { target in
                guard let target else { return }
                switch target {
                case .section(let section):
                    // Just the section. The editor sets itself up in `onAppear`
                    // rather than here: a click on an already-selected row is
                    // not a selection change, so a project restored straight
                    // into the editor would never have run the setup.
                    viewModel.section = section
                case .everything:
                    viewModel.showingFavouritesOnly = false
                    viewModel.browse(nil)
                case .images:
                    viewModel.managerTab = .images
                    viewModel.section = .manager
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
    case images
    case everything
    case starred
    case folder(String)
}
