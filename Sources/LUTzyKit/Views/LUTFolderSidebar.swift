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
                        select: viewModel.browse
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

    @State private var isExpanded = true

    var body: some View {
        if node.children.isEmpty {
            rowButton
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(node.children) { child in
                    LUTFolderBranch(node: child, selectedPath: selectedPath, select: select)
                }
            } label: {
                rowButton
            }
        }
    }

    private var rowButton: some View {
        Button {
            select(node.path)
        } label: {
            LUTFolderRow(
                name: node.name,
                count: node.count,
                symbol: selectedPath == node.path ? "folder.fill" : "folder",
                selected: selectedPath == node.path
            )
        }
        .buttonStyle(.plain)
        .help(node.path)
    }
}

private struct LUTFolderRow: View {
    let name: String
    let count: Int
    let symbol: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .frame(width: 15)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            Text(name)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            selected ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}
