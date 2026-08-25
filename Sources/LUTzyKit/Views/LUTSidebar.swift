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

    @State private var isDropTargeted = false
    /// Whether the filter panel is open. Starts open: the point of it is to be
    /// seen, and someone who wants the space back can close it.
    @State private var filtersExpanded = true

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
            return filtered.isEmpty
                ? nil : LUTLibrary.Category(id: cat.id, name: cat.name, luts: filtered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("LUT Library")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                if filteredCategories.count > 1 {
                    Button(action: toggleAll) {
                        Image(
                            systemName: allExpanded
                                ? "rectangle.compress.vertical"
                                : "rectangle.expand.vertical")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .disabled(isSearching)
                    .help(allExpanded ? "Collapse all folders" : "Expand all folders")
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

            scopeMenu

            tagFilterBar

            Divider()

            // LUT list
            if viewModel.library.isScanning && viewModel.library.allLUTs.isEmpty {
                scanningState
            } else if viewModel.library.allLUTs.isEmpty {
                emptyState
            } else if viewModel.showingFavouritesOnly && viewModel.tags.favouriteCount == 0 {
                noFavouritesState
            } else {
                lutList
            }
        }
        // Wider than before, and draggable up to it: the filter panel wraps, so a
        // wider sidebar means more of the vocabulary per row rather than just
        // more whitespace.
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 460)
        .safeAreaInset(edge: .bottom) {
            importMenu
        }
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

    private var scopeLabel: String {
        if viewModel.showingFavouritesOnly { return "Starred" }
        return viewModel.browsedCategory ?? "All LUTs"
    }

    private var scopeSymbol: String {
        if viewModel.showingFavouritesOnly { return "star.fill" }
        return viewModel.browsedCategory == nil ? "square.stack.3d.up" : "folder.fill"
    }

    /// LUT scope belongs to the LUT column, not primary navigation. The active
    /// scope remains visible while the top-level mode highlight stays put.
    private var scopeMenu: some View {
        Menu {
            Button {
                viewModel.showingFavouritesOnly = false
                viewModel.browse(nil)
            } label: {
                Label(
                    "All LUTs",
                    systemImage: viewModel.browsedCategory == nil
                        && !viewModel.showingFavouritesOnly
                        ? "checkmark"
                        : "square.stack.3d.up"
                )
            }
            Button {
                viewModel.browse(nil)
                viewModel.showingFavouritesOnly = true
            } label: {
                Label(
                    "Starred", systemImage: viewModel.showingFavouritesOnly ? "checkmark" : "star")
            }

            if viewModel.folderTiles.isEmpty == false {
                Divider()
                Section("Folders") {
                    ForEach(viewModel.folderTiles, id: \.name) { folder in
                        Button {
                            viewModel.showingFavouritesOnly = false
                            viewModel.browse(folder.name)
                        } label: {
                            Label(
                                "\(folder.name)  \(folder.count)",
                                systemImage: viewModel.browsedCategory == folder.name
                                    ? "checkmark" : "folder"
                            )
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: scopeSymbol)
                    .frame(width: 14)
                Text(scopeLabel)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .help("Choose which part of the LUT library to show")
    }

    private var importMenu: some View {
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
        .background(.bar)
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
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
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

    /// The tags in use, as a wrapping panel of toggles.
    ///
    /// Wrapping rather than a scrolling line: a filter exists to be surveyed
    /// before it is used, and a single row that hides two thirds of the
    /// vocabulary behind a horizontal drag cannot be surveyed at all.
    ///
    /// Measured tags and typed ones sit together deliberately: from the point
    /// of view of finding a LUT there is no difference between "高對比" (which
    /// was measured) and "日系" (which was typed), and separating them would
    /// make the user remember which kind each one was.
    @ViewBuilder
    private var tagFilterBar: some View {
        if viewModel.tags.counts.isEmpty == false {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) { filtersExpanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filtersExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Filter")
                                .font(.caption)
                            if viewModel.tagFilter.isEmpty == false {
                                Text("\(viewModel.tagFilter.count)")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor, in: Capsule())
                                    .foregroundColor(.white)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if viewModel.tagFilter.isEmpty == false {
                        Button("Clear") { viewModel.clearTagFilter() }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                if filtersExpanded {
                    // Capped so a big vocabulary cannot push the LUT list off
                    // the bottom of the window; it scrolls past that point.
                    ScrollView(.vertical, showsIndicators: false) {
                        FlowLayout(spacing: 5, lineSpacing: 5) {
                            ForEach(viewModel.tags.counts, id: \.tag) { item in
                                tagChip(item.tag, count: item.count)
                            }
                        }
                    }
                    .frame(maxHeight: 132)
                } else if viewModel.tagFilter.isEmpty == false {
                    // Collapsed, still show what is currently narrowing the
                    // list — a filter you cannot see is a list that looks broken.
                    FlowLayout(spacing: 5, lineSpacing: 5) {
                        ForEach(viewModel.tagFilter.sorted(), id: \.self) { tag in
                            tagChip(tag, count: nil)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func tagChip(_ tag: String, count: Int?) -> some View {
        let active = viewModel.tagFilter.contains(tag)
        return Button {
            viewModel.toggleTagFilter(tag)
        } label: {
            HStack(spacing: 4) {
                Text(tag)
                if let count {
                    Text("\(count)")
                        .foregroundStyle(
                            active ? Color.white.opacity(0.75) : Color(nsColor: .tertiaryLabelColor)
                        )
                }
            }
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                active ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.08),
                in: Capsule()
            )
            .foregroundColor(active ? .white : .primary)
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
            Image(
                systemName: viewModel.library.scanError == nil
                    ? "cube.transparent" : "exclamationmark.triangle"
            )
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
        List(
            selection: Binding(
                get: { viewModel.selectedLUT },
                set: { viewModel.selectLUT($0) }
            )
        ) {
            ForEach(filteredCategories) { category in
                Section(isExpanded: isExpandedBinding(category.id)) {
                    ForEach(category.luts) { lut in
                        LUTRow(
                            lut: lut,
                            isSelected: viewModel.selectedLUT == lut,
                            isFavourite: viewModel.tags.isFavourite(lut),
                            toggleFavourite: { viewModel.tags.toggleFavourite(lut) }
                        )
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
            collapsed.formUnion(ids)  // everything open → collapse all
        } else {
            collapsed.subtract(ids)  // some closed → expand all
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
