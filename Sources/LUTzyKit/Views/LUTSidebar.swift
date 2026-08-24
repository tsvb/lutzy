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

    /// The LUT whose tag sheet is open, and the text being typed into it.
    @State private var taggingLUT: CubeLUT?
    @State private var newTag: String = ""

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

            tagFilterBar

            Divider()

            // LUT list
            if viewModel.library.isScanning && viewModel.library.allLUTs.isEmpty {
                scanningState
            } else if viewModel.library.allLUTs.isEmpty {
                emptyState
            } else {
                lutList
            }
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
        .sheet(item: $taggingLUT) { lut in
            addTagSheet(for: lut)
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
            Text(viewModel.library.scanError ?? "No LUTs loaded")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
            Button("Choose Folder...") {
                viewModel.chooseLUTFolder()
            }
            .buttonStyle(.bordered)
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
                        LUTRow(lut: lut, isSelected: viewModel.selectedLUT == lut)
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

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 4, height: 20)

            Text(lut.name)
                .font(.system(.body, design: .default))
                .lineLimit(1)

            Spacer()
        }
        .contentShape(Rectangle())
    }
}
