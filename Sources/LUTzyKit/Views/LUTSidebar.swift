import SwiftUI

/// Sidebar showing the LUT library grouped by category.
struct LUTSidebar: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var searchText = ""

    /// Names of collapsed folders. Stored as a set of category names (a folder
    /// absent from the set is expanded), so newly-discovered folders default to
    /// expanded. Persisted across launches and re-scans.
    private static let collapsedKey = "lutzy.collapsedLUTCategories"
    @State private var collapsed: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: LUTSidebar.collapsedKey) ?? [])

    /// What the sidebar is showing. Folders and favourites are two ways of
    /// narrowing the same library rather than two libraries, so this is a view
    /// mode and the filters underneath compose with it.
    enum Browse: String, CaseIterable {
        case list, folders, favourites
        var symbol: String {
            switch self {
            case .list: return "list.bullet"
            case .folders: return "folder"
            case .favourites: return "star"
            }
        }
    }
    @State private var browse: Browse = .list

    @State private var isDropTargeted = false

    /// The LUT whose tag sheet is open, and the text being typed into it.
    @State private var taggingLUT: CubeLUT?
    @State private var newTag: String = ""
    /// The LUT waiting for a folder name to be typed.
    @State private var movingLUT: CubeLUT?
    @State private var newFolder: String = ""

    private var isSearching: Bool { !searchText.isEmpty }

    /// Search narrows whatever the tag filter has already left. The two
    /// compose rather than override: "the warm ones, called classic" is the
    /// question people actually ask of a library this size.
    private var filteredCategories: [LUTLibrary.Category] {
        let base = viewModel.filteredCategories
        if searchText.isEmpty {
            return base
        }
        let query = searchText.lowercased()
        return base.compactMap { cat in
            // A folder-name match surfaces the whole folder; otherwise keep only
            // the LUTs whose own name matches.
            if cat.name.lowercased().contains(query) {
                return cat
            }
            let filtered = cat.luts.filter { $0.name.lowercased().contains(query) }
            return filtered.isEmpty ? nil : LUTLibrary.Category(id: cat.id, name: cat.name, luts: filtered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("LUTs")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                if filteredCategories.count > 1 {
                    Button(action: toggleAll) {
                        Image(systemName: allExpanded ? "rectangle.compress.vertical"
                                                       : "rectangle.expand.vertical")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .disabled(isSearching)
                    .help(allExpanded ? "Collapse all folders" : "Expand all folders")
                }
                Picker("", selection: $browse) {
                    ForEach(Browse.allCases, id: \.self) { mode in
                        Image(systemName: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: browse) { _, mode in
                    viewModel.showingFavouritesOnly = mode == .favourites
                }
                Text("\(viewModel.library.allLUTs.count)")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .quaternaryLabelColor), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Search (matches LUT names and folder names)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .onExitCommand { searchText = "" }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if let browsed = viewModel.browsedCategory {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").font(.caption2)
                    Text(browsed).font(.caption).lineLimit(1)
                    Spacer()
                    Button {
                        viewModel.browse(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Show every folder")
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            tagFilterBar

            Divider()

            // LUT list
            if viewModel.library.isScanning && viewModel.library.allLUTs.isEmpty {
                scanningState
            } else if viewModel.library.allLUTs.isEmpty {
                emptyState
            } else if browse == .folders {
                folderBrowser
            } else if browse == .favourites && viewModel.tags.favouriteCount == 0 {
                noFavouritesState
            } else {
                lutList
            }
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            importDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $taggingLUT) { lut in
            addTagSheet(for: lut)
        }
        .sheet(item: $movingLUT) { lut in
            newFolderSheet(for: lut)
        }
    }

    /// A LUT's tags: what was measured, what was typed, and a way to add more.
    ///
    /// Measured tags are shown but not removable — they are claims about the
    /// file, and deleting one by hand would only mean the next scan puts it
    /// back. Typed ones are the user's, and are the only ones that can go.
    @ViewBuilder
    private func tagMenu(for lut: CubeLUT) -> some View {
        let measured = viewModel.tags.tags(for: lut).filter {
            viewModel.tags.typedTags(for: lut).contains($0) == false
        }
        let typed = viewModel.tags.typedTags(for: lut)

        Button("Add Tag…") {
            newTag = ""
            taggingLUT = lut
        }
        Button(viewModel.tags.isFavourite(lut) ? "Unstar" : "Star") {
            viewModel.tags.toggleFavourite(lut)
        }
        if viewModel.library.isManaged {
            Menu("Move to Folder") {
                Button("Top Level") { viewModel.moveLUT(lut, toCategory: "") }
                Divider()
                ForEach(viewModel.library.categoryNames, id: \.self) { name in
                    Button(name) { viewModel.moveLUT(lut, toCategory: name) }
                }
                Divider()
                Button("New Folder…") { movingLUT = lut }
            }
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([lut.url])
        }
        if viewModel.library.isManaged {
            Button("Remove from Library") { viewModel.removeLUT(lut) }
        }
        if typed.isEmpty == false {
            Divider()
            ForEach(typed, id: \.self) { tag in
                Button("Remove “\(tag)”") { viewModel.tags.removeTag(tag, from: lut) }
            }
        }
        if measured.isEmpty == false {
            Divider()
            Section("Measured") {
                ForEach(measured, id: \.self) { tag in
                    Text(tag)
                }
            }
        }
    }

    private func addTagSheet(for lut: CubeLUT) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tag \(lut.name)")
                .font(.headline)
            TextField("e.g. 日系, 婚禮, 想再試", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitTag(for: lut) }
            HStack {
                Spacer()
                Button("Cancel") { taggingLUT = nil }
                Button("Add") { commitTag(for: lut) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    /// Collect the dropped URLs, then import them in one pass.
    ///
    /// One pass rather than one import per provider: the library rescans after
    /// each import, and a folder of fifty files dropped as fifty providers
    /// would rescan fifty times.
    private func importDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }
        group.notify(queue: .main) {
            guard urls.isEmpty == false else { return }
            Task { @MainActor in viewModel.importLUTs(from: urls) }
        }
        return true
    }

    private func newFolderSheet(for lut: CubeLUT) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move \(lut.name) to a new folder")
                .font(.headline)
            TextField("Folder name", text: $newFolder)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitMove(lut) }
            HStack {
                Spacer()
                Button("Cancel") { movingLUT = nil }
                Button("Move") { commitMove(lut) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func commitMove(_ lut: CubeLUT) {
        let name = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }
        viewModel.moveLUT(lut, toCategory: name)
        newFolder = ""
        movingLUT = nil
    }

    private func commitTag(for lut: CubeLUT) {
        viewModel.tags.addTag(newTag, to: lut)
        newTag = ""
        taggingLUT = nil
    }

    /// The tags in use, as a row of toggles.
    ///
    /// Measured tags and typed ones sit together deliberately: from the point
    /// of view of finding a LUT there is no difference between "高對比" (which
    /// was measured) and "日系" (which was typed), and separating them would
    /// make the user remember which kind each one was.
    @ViewBuilder
    private var tagFilterBar: some View {
        if viewModel.tags.counts.isEmpty == false {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if viewModel.tagFilter.isEmpty == false {
                        Button {
                            viewModel.clearTagFilter()
                        } label: {
                            Label("Clear", systemImage: "xmark")
                                .font(.caption2)
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.secondary)
                    }
                    ForEach(viewModel.tags.counts, id: \.tag) { item in
                        let active = viewModel.tagFilter.contains(item.tag)
                        Button {
                            viewModel.toggleTagFilter(item.tag)
                        } label: {
                            Text("\(item.tag) \(item.count)")
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(active ? Color.accentColor.opacity(0.85)
                                                   : Color.primary.opacity(0.08),
                                            in: Capsule())
                                .foregroundColor(active ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    /// The folders, as tiles with counts.
    ///
    /// A grid rather than the list's own section headers because this answers a
    /// different question: not "which LUT" but "what have I got", and a library
    /// of several hundred is easier to take in as a dozen tiles than as a
    /// scroll.
    private var folderBrowser: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                folderTile(name: "All LUTs", count: viewModel.library.allLUTs.count, category: nil)
                ForEach(viewModel.folderTiles, id: \.name) { tile in
                    folderTile(name: tile.name, count: tile.count, category: tile.name)
                }
            }
            .padding(12)
        }
    }

    private func folderTile(name: String, count: Int, category: String?) -> some View {
        let active = viewModel.browsedCategory == category
        return Button {
            viewModel.browse(category)
            browse = .list
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var noFavouritesState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "star")
                .font(.system(size: 28))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            Text("Nothing starred yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Click a LUT's star to keep it here")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().controlSize(.small)
            Text("Scanning LUT folder…")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: viewModel.library.scanError == nil
                  ? "cube.transparent" : "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            Text(viewModel.library.scanError ?? "No LUTs yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
            Text("Drop .cube files or folders here")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            // Importing is the primary action now: the library lives inside the
            // app, so this is a one-time step rather than something to redo on
            // every launch. Pointing at a folder is still there for anyone who
            // would rather keep their files where they are.
            Button("Import LUTs…") {
                viewModel.importLUTs()
            }
            .buttonStyle(.borderedProminent)
            Button("Use a Folder Instead…") {
                viewModel.chooseLUTFolder()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var lutList: some View {
        List(selection: Binding(
            get: { viewModel.selectedLUT },
            set: { viewModel.selectLUT($0) }
        )) {
            ForEach(filteredCategories) { category in
                Section(isExpanded: isExpandedBinding(category.id)) {
                    ForEach(category.luts) { lut in
                        LUTRow(lut: lut,
                               isSelected: viewModel.selectedLUT == lut,
                               isFavourite: viewModel.tags.isFavourite(lut),
                               toggleFavourite: { viewModel.tags.toggleFavourite(lut) })
                            .tag(lut)
                            .contextMenu { tagMenu(for: lut) }
                    }
                } header: {
                    HStack {
                        Text(category.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(category.luts.count)")
                            .font(.caption2)
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Folder collapse state

    /// True when no visible folder is collapsed (drives the toggle-all icon).
    private var allExpanded: Bool {
        collapsed.isDisjoint(with: Set(filteredCategories.map(\.id)))
    }

    /// Expansion binding for one folder. While searching, folders are forced
    /// open so matches are always visible and writes are ignored.
    private func isExpandedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { isSearching || !collapsed.contains(id) },
            set: { expand in
                guard !isSearching else { return }
                if expand { collapsed.remove(id) } else { collapsed.insert(id) }
                persistCollapsed()
            }
        )
    }

    private func toggleAll() {
        let ids = Set(filteredCategories.map(\.id))
        if allExpanded {
            collapsed.formUnion(ids)   // everything open → collapse all
        } else {
            collapsed.subtract(ids)    // some closed → expand all
        }
        persistCollapsed()
    }

    private func persistCollapsed() {
        UserDefaults.standard.set(Array(collapsed), forKey: Self.collapsedKey)
    }
}

struct LUTRow: View {
    let lut: CubeLUT
    let isSelected: Bool
    let isFavourite: Bool
    let toggleFavourite: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 4, height: 20)

            Text(lut.name)
                .font(.system(.body, design: .default))
                .lineLimit(1)

            Spacer()

            // The star appears on hover unless it is already set: a column of
            // empty stars down a library of several hundred is noise, and a
            // filled one is information.
            if isFavourite || isHovering {
                Button(action: toggleFavourite) {
                    Image(systemName: isFavourite ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(isFavourite ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(isFavourite ? "Unstar" : "Star")
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
