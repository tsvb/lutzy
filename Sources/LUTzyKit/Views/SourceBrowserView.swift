import SwiftUI

/// Docked panel listing the source folder's images, grouped by subfolder.
/// Selecting a row opens it; the selection is the list's own, bound to the
/// collection's index, so it stays in sync with the filmstrip and ←/→
/// navigation and is scrolled into view when either moves it.
struct SourceBrowserView: View {
    let viewModel: AppViewModel

    private var collection: ImageCollection { viewModel.collection }

    /// The list's selection, expressed as the collection's index. `nil` from the list (a click on
    /// empty space) is ignored: there is always a current image while the browser is showing.
    private var selection: Binding<ImageCollection.Item.ID?> {
        Binding(
            get: { collection.selectedItem?.id },
            set: { id in
                guard let id, let index = collection.items.firstIndex(where: { $0.id == id }) else { return }
                viewModel.selectCollectionImage(at: index)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .background(.bar)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(collection.sourceFolderURL?.lastPathComponent ?? "Source")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(collection.items.count) image\(collection.items.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                viewModel.refreshSource()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .help("Rescan source folder")
            .disabled(collection.sourceFolderURL == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                ForEach(groups) { group in
                    if showHeaders {
                        Section {
                            rows(group)
                        } header: {
                            Text(group.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        rows(group)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: collection.selectedIndex) { _, idx in
                guard collection.items.indices.contains(idx) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(collection.items[idx].id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func rows(_ group: Group) -> some View {
        ForEach(group.entries, id: \.item.id) { entry in
            SourceBrowserRow(
                item: entry.item,
                isSelected: entry.index == collection.selectedIndex
            )
            .tag(entry.item.id)
            .id(entry.item.id)
        }
    }

    // MARK: - Grouping

    /// Only show subfolder section headers when there's actually more than one
    /// group (i.e. the source has subfolders).
    private var showHeaders: Bool { groups.count > 1 }

    private struct Group: Identifiable {
        let id: String
        let name: String
        let entries: [(index: Int, item: ImageCollection.Item)]
    }

    /// Items grouped by subfolder, preserving each item's index in
    /// `collection.items` (which the filmstrip and navigation use). Items are
    /// already sorted by subfolder, so groups come out in order.
    private var groups: [Group] {
        var order: [String] = []
        var buckets: [String: [(Int, ImageCollection.Item)]] = [:]
        for (i, item) in collection.items.enumerated() {
            if buckets[item.subfolder] == nil { order.append(item.subfolder) }
            buckets[item.subfolder, default: []].append((i, item))
        }
        return order.map { key in
            Group(
                id: key.isEmpty ? "·root" : key,
                name: key.isEmpty ? (collection.sourceFolderURL?.lastPathComponent ?? "Images") : key,
                entries: buckets[key]!.map { (index: $0.0, item: $0.1) }
            )
        }
    }
}

// MARK: - Row

private struct SourceBrowserRow: View {
    let item: ImageCollection.Item
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
            Text(item.displayName)
                .font(.callout)
                .fontWeight(isSelected ? .medium : .regular)
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumb = item.thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 38, height: 38)
                .overlay(ProgressView().controlSize(.small))
        }
    }
}
