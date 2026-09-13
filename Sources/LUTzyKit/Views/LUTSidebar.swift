import SwiftUI

/// Sidebar showing the LUT library grouped by category.
struct LUTSidebar: View {
    let viewModel: AppViewModel
    /// Owned by `ContentView`, which suspends the plain-key shortcuts while this is true.
    var searchFocus: FocusState<Bool>.Binding
    @State private var searchText = ""

    /// Names of collapsed folders, newline-joined in `UserDefaults` (a folder absent from the set
    /// is expanded, so newly-discovered folders default to expanded). `@AppStorage` rather than a
    /// hand-persisted `@State` so the Settings window's "Expand All" is reflected here at once.
    @AppStorage(AppPreference.collapsedLUTCategories) private var collapsedRaw = ""

    private var collapsed: Set<String> {
        get { Set(collapsedRaw.split(separator: "\n").map(String.init)) }
        nonmutating set { collapsedRaw = newValue.sorted().joined(separator: "\n") }
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private var filteredCategories: [LUTLibrary.Category] {
        if searchText.isEmpty {
            return viewModel.library.categories
        }
        let query = searchText.lowercased()
        return viewModel.library.categories.compactMap { cat in
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
            // LUT list
            if viewModel.library.isScanning && viewModel.library.allLUTs.isEmpty {
                scanningState
            } else if viewModel.library.allLUTs.isEmpty {
                emptyState
            } else if isSearching && filteredCategories.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                lutList
            }
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
        // The system search field, in the sidebar's own slot: matches LUT names and folder names,
        // clears on Escape, and reports its focus so the plain-key shortcuts stand down while typing.
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search LUTs")
        .searchFocused(searchFocus)
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
        if let scanError = viewModel.library.scanError {
            ContentUnavailableView {
                Label("Couldn't Scan LUT Folder", systemImage: "exclamationmark.triangle")
            } description: {
                Text(scanError)
            } actions: {
                Button("Choose Folder…") { viewModel.chooseLUTFolder() }
                    .buttonStyle(.bordered)
            }
        } else {
            ContentUnavailableView {
                Label("No LUTs", systemImage: "cube.transparent")
            } description: {
                Text("Choose a folder of .cube files to build your LUT library.")
            } actions: {
                Button("Choose Folder…") { viewModel.chooseLUTFolder() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var lutList: some View {
        List(selection: Binding(
            get: { viewModel.selectedLUT },
            set: { viewModel.selectLUT($0) }
        )) {
            Text("None")
                .foregroundStyle(.secondary)
                .tag(Optional<CubeLUT>.none)

            ForEach(filteredCategories) { category in
                Section(isExpanded: isExpandedBinding(category.id)) {
                    ForEach(category.luts) { lut in
                        LUTRow(lut: lut)
                            .tag(lut)
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
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    // MARK: - Folder collapse state

    /// Expansion binding for one folder. While searching, folders are forced
    /// open so matches are always visible and writes are ignored.
    private func isExpandedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { isSearching || !collapsed.contains(id) },
            set: { expand in
                guard !isSearching else { return }
                if expand { collapsed.remove(id) } else { collapsed.insert(id) }
            }
        )
    }
}

struct LUTRow: View {
    let lut: CubeLUT

    /// Display-only: underscores read as spaces, but `lut.name` itself is left untouched — it is
    /// still the identity used for matching, resolving, and export naming elsewhere.
    private var displayName: String {
        lut.name.replacingOccurrences(of: "_", with: " ")
    }

    var body: some View {
        Text(displayName)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(lut.name)
            .contentShape(Rectangle())
    }
}
