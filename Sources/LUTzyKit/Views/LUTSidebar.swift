import SwiftUI

/// Sidebar showing the LUT library grouped by category.
struct LUTSidebar: View {
    let viewModel: AppViewModel
    /// Owned by `ContentView`, which suspends the plain-key shortcuts while this is true.
    var searchFocus: FocusState<Bool>.Binding
    @State private var searchText = ""

    /// Names of collapsed folders. Stored as a set of category names (a folder
    /// absent from the set is expanded), so newly-discovered folders default to
    /// expanded. Persisted across launches and re-scans.
    private static let collapsedKey = "lutzy.collapsedLUTCategories"
    @State private var collapsed: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: LUTSidebar.collapsedKey) ?? [])

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
