import SwiftUI

/// Viewer's folder-first LUT navigation.
///
/// LUT files deliberately do not appear here. The column answers only “which
/// folder are we auditioning?”, while the contact sheet beside the photograph
/// answers “which look in that folder?”.
struct LUTFolderSidebar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if viewModel.library.isScanning && viewModel.library.allLUTs.isEmpty {
                scanningState
            } else if viewModel.library.allLUTs.isEmpty {
                emptyState
            } else {
                folderOutline
            }
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 380)
        .safeAreaInset(edge: .bottom) { importMenu }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LUT Folders")
                    .font(.headline)
                Text("Select a folder to preview its looks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(viewModel.library.allLUTs.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var folderOutline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                folderButton(
                    name: "All LUTs",
                    path: nil,
                    count: viewModel.library.allLUTs.count,
                    symbol: "square.stack.3d.up"
                )

                Divider()
                    .padding(.vertical, 6)

                ForEach(viewModel.lutFolderTree) { node in
                    LUTFolderBranch(
                        node: node,
                        selectedPath: viewModel.browsedCategory,
                        select: viewModel.browse,
                        depth: 0
                    )
                }
            }
            .padding(8)
        }
    }

    private func folderButton(
        name: String,
        path: String?,
        count: Int,
        symbol: String
    ) -> some View {
        let selected = viewModel.browsedCategory == path
        return Button {
            viewModel.browse(path)
        } label: {
            LUTFolderRow(
                name: name,
                count: count,
                symbol: symbol,
                selected: selected
            )
        }
        .buttonStyle(.plain)
    }

    private var importMenu: some View {
        Menu {
            Button("Import LUTs or Folder…") { viewModel.importLUTs() }
            Divider()
            Button("Use Existing LUT Folder…") { viewModel.chooseLUTFolder() }
            if viewModel.library.isManaged == false, let folder = viewModel.library.folderURL {
                Text("Currently: \(folder.lastPathComponent)")
                Button("Back to the App's Library") { viewModel.library.useManagedFolder() }
            }
        } label: {
            Label("Import LUT Folder…", systemImage: "folder.badge.plus")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .help("Import a folder and preserve its hierarchy")
    }

    private var scanningState: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView().controlSize(.small)
            Text("Scanning LUT folders…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(viewModel.library.scanError ?? "No LUT folders yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Import LUT Folder…") { viewModel.importLUTs() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }
}

private struct LUTFolderBranch: View {
    let node: LUTFolderNode
    let selectedPath: String?
    let select: (String?) -> Void
    let depth: Int

    @State private var isExpanded: Bool

    init(
        node: LUTFolderNode,
        selectedPath: String?,
        select: @escaping (String?) -> Void,
        depth: Int
    ) {
        self.node = node
        self.selectedPath = selectedPath
        self.select = select
        self.depth = depth

        // Keep a large library legible on first open: reveal its packages, not
        // every folder inside every package. A restored deep selection is the
        // exception — all of its ancestors open so the selected row is visible.
        let containsSelection = selectedPath.map {
            LUTFolderHierarchy.contains(categoryPath: $0, in: node.path)
        } ?? false
        _isExpanded = State(initialValue: depth == 0 || containsSelection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            branchRow

            if node.children.isEmpty == false, isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(node.children) { child in
                        LUTFolderBranch(
                            node: child,
                            selectedPath: selectedPath,
                            select: select,
                            depth: depth + 1
                        )
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.11))
                        .frame(width: 1)
                        .padding(.vertical, 3)
                        .offset(x: 7)
                }
            }
        }
        .onChange(of: selectedPath) { _, selectedPath in
            guard let selectedPath else { return }
            if LUTFolderHierarchy.contains(categoryPath: selectedPath, in: node.path) {
                isExpanded = true
            }
        }
    }

    private var branchRow: some View {
        let selected = selectedPath == node.path

        return HStack(spacing: 0) {
            if node.children.isEmpty {
                Color.clear
                    .frame(width: 18, height: 28)
            } else {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse \(node.name)" : "Expand \(node.name)")
                .accessibilityLabel(isExpanded ? "Collapse \(node.name)" : "Expand \(node.name)")
            }

            Button {
                select(node.path)
            } label: {
                LUTFolderRow(
                    name: node.name,
                    count: node.count,
                    symbol: selected ? "folder.fill" : "folder",
                    selected: selected,
                    drawsSelectionBackground: false
                )
            }
            .buttonStyle(.plain)
            .help(node.path)
            .accessibilityLabel("\(node.name), \(node.count) LUTs")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            selected ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

}

private struct LUTFolderRow: View {
    let name: String
    let count: Int
    let symbol: String
    let selected: Bool
    var drawsSelectionBackground = true

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .frame(width: 15)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            drawsSelectionBackground && selected ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}
