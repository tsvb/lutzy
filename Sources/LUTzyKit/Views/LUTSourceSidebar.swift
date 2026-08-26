import SwiftUI

/// Folder/Collection/Starred navigation shared by Viewer, LUT Library, and
/// LUT Manager while each workspace retains its own source selection.
struct LUTSourceSidebar: View {
    @ObservedObject var viewModel: AppViewModel
    let context: LUTWorkspaceContext

    @State private var isCreatingCollection = false
    @State private var collectionName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context == .manager ? "Manage LUTs" : "LUT Library")
                        .font(.headline)
                    Text("Folders, Collections, and Starred")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(viewModel.luts(for: viewModel.lutSource(for: context)).count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()
            LUTSourceList(viewModel: viewModel, context: context)
            Divider()

            HStack {
                Menu {
                    Button("Import LUTs or Folder…") { viewModel.importLUTs() }
                    Button("Use Existing LUT Folder…") { viewModel.chooseLUTFolder() }
                } label: {
                    Label("Import LUT Folder…", systemImage: "folder.badge.plus")
                }
                .menuStyle(.borderlessButton)
                Spacer()
                if context == .manager {
                    Button { collectionName = ""; isCreatingCollection = true } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.managerSelection.isEmpty)
                    .help(viewModel.managerSelection.isEmpty
                          ? "Select one or more LUTs to create a Collection"
                          : "New Collection from Selection")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.bar)
        }
        .frame(minWidth: 220, idealWidth: 265, maxWidth: 380)
        .sheet(isPresented: $isCreatingCollection) {
            VStack(alignment: .leading, spacing: 12) {
                Text("New Collection").font(.headline)
                Text("Includes \(viewModel.managerSelection.count) selected LUT\(viewModel.managerSelection.count == 1 ? "" : "s").")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Collection name", text: $collectionName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createCollection)
                HStack {
                    Spacer()
                    Button("Cancel") { isCreatingCollection = false }
                    Button("Create", action: createCollection)
                        .keyboardShortcut(.defaultAction)
                        .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .frame(width: 320)
        }
    }

    private func createCollection() {
        guard let item = viewModel.createCollection(
            named: collectionName, from: viewModel.managerSelection
        ) else { return }
        viewModel.setLUTSource(.collection(item.id), for: context)
        isCreatingCollection = false
    }
}

struct LUTSourceList: View {
    @ObservedObject var viewModel: AppViewModel
    let context: LUTWorkspaceContext

    @State private var collectionToRename: UUID?
    @State private var renameText = ""

    private var selected: LUTSource { viewModel.lutSource(for: context) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                sourceRow(.all, label: "All LUTs", symbol: "square.stack.3d.up",
                          count: viewModel.library.allLUTs.count)

                groupHeader("Folders")
                ForEach(viewModel.lutFolderTree) { node in
                    LUTSourceFolderBranch(
                        node: node,
                        selected: selected,
                        choose: { viewModel.setLUTSource($0, for: context) },
                        depth: 0
                    )
                }

                groupHeader("Collections")
                if viewModel.catalog.collections.isEmpty {
                    Text("Create Collections in LUT Manager")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                } else {
                    ForEach(viewModel.catalog.collections) { collection in
                        sourceRow(
                            .collection(collection.id), label: collection.name,
                            symbol: "rectangle.stack", count: viewModel.catalog.members(of: collection.id).count
                        )
                        .contextMenu {
                            if context == .manager {
                                Button("Rename Collection…") {
                                    renameText = collection.name
                                    collectionToRename = collection.id
                                }
                                Button("Delete Collection", role: .destructive) {
                                    if selected == .collection(collection.id) {
                                        viewModel.setLUTSource(.all, for: context)
                                    }
                                    viewModel.catalog.deleteCollection(collection.id)
                                }
                            }
                        }
                    }
                }

                groupHeader("Star")
                sourceRow(.starred, label: "Starred", symbol: "star.fill", count: viewModel.starredCount)
            }
            .padding(8)
        }
        .alert("Rename Collection", isPresented: Binding(
            get: { collectionToRename != nil },
            set: { if $0 == false { collectionToRename = nil } }
        )) {
            TextField("Collection name", text: $renameText)
            Button("Cancel", role: .cancel) { collectionToRename = nil }
            Button("Rename") { commitCollectionRename() }
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func commitCollectionRename() {
        guard let id = collectionToRename else { return }
        viewModel.catalog.renameCollection(id, to: renameText)
        collectionToRename = nil
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 9)
            .padding(.top, 11)
            .padding(.bottom, 3)
    }

    private func sourceRow(_ source: LUTSource, label: String, symbol: String, count: Int) -> some View {
        Button { viewModel.setLUTSource(source, for: context) } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).frame(width: 16)
                Text(label).lineLimit(1)
                Spacer()
                Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(selected == source ? Color.accentColor.opacity(0.22) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct LUTSourceFolderBranch: View {
    let node: LUTFolderNode
    let selected: LUTSource
    let choose: (LUTSource) -> Void
    let depth: Int
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if node.children.isEmpty == false {
                    Button { expanded.toggle() } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 12, height: 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expanded ? "Collapse \(node.name)" : "Expand \(node.name)")
                } else {
                    Color.clear.frame(width: 12)
                }

                Button { choose(.folder(node.path)) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                        Text(node.name).lineLimit(1)
                        Spacer()
                        Text("\(node.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(depth) * 14 + 6)
            .padding(.trailing, 9)
            .padding(.vertical, 5)
            .background(selected == .folder(node.path) ? Color.accentColor.opacity(0.22) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))

            if expanded {
                ForEach(node.children) { child in
                    LUTSourceFolderBranch(node: child, selected: selected, choose: choose, depth: depth + 1)
                }
            }
        }
    }
}
