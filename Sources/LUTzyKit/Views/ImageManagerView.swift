import SwiftUI

enum ImageManagerPresentation: String, CaseIterable, Sendable {
    case list
    case gallery

    var label: String {
        switch self {
        case .list: return "List"
        case .gallery: return "Gallery"
        }
    }

    var symbol: String {
        switch self {
        case .list: return "list.bullet"
        case .gallery: return "square.grid.2x2"
        }
    }
}

/// Finder-like selection without a dependency on SwiftUI or the current event.
/// Kept as a value helper so Command/Shift behaviour can be verified headlessly.
enum ImageManagerSelection {
    static func selecting(
        _ id: String,
        orderedIDs: [String],
        current: Set<String>,
        anchor: String?,
        toggling: Bool,
        extending: Bool
    ) -> (selection: Set<String>, anchor: String) {
        if extending,
           let anchor,
           let start = orderedIDs.firstIndex(of: anchor),
           let end = orderedIDs.firstIndex(of: id) {
            let bounds = min(start, end)...max(start, end)
            let range = Set(bounds.map { orderedIDs[$0] })
            return (toggling ? current.union(range) : range, anchor)
        }

        if toggling {
            var updated = current
            if updated.contains(id) {
                updated.remove(id)
            } else {
                updated.insert(id)
            }
            return (updated, id)
        }

        return ([id], id)
    }
}

/// The project's images as a table, so a subset can be chosen and acted on.
///
/// Export All could only ever say "all of them", and "these six, with this
/// look" is how a set actually gets used — a shortlist for a client, the frames
/// that came out, the ones worth reprinting. Choosing is the whole feature; the
/// table exists to make choosing possible.
struct ImageManagerView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var selection: Set<String> = []
    @State private var selectionAnchor: String?
    @AppStorage("imageManager.presentation") private var presentationRaw = ImageManagerPresentation.list.rawValue

    private struct Row: Identifiable {
        let id: String
        let name: String
        let folder: String
        let thumbnail: NSImage?
        let index: Int
    }

    private var rows: [Row] {
        viewModel.collection.items.enumerated().map { index, item in
            Row(id: item.displayName, name: item.displayName,
                folder: item.subfolder, thumbnail: item.thumbnail, index: index)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            presentationBar
            Divider()
            if rows.isEmpty {
                empty
            } else {
                switch presentation {
                case .list:
                    table
                case .gallery:
                    gallery
                }
            }
            Divider()
            actionBar
        }
    }

    private var presentation: ImageManagerPresentation {
        ImageManagerPresentation(rawValue: presentationRaw) ?? .list
    }

    private var presentationBar: some View {
        HStack {
            Text("Images")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Picker("Presentation", selection: $presentationRaw) {
                ForEach(ImageManagerPresentation.allCases, id: \.rawValue) { mode in
                    Label(mode.label, systemImage: mode.symbol)
                        .labelStyle(.iconOnly)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Show images as a list or gallery")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No images")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Import Images…") { viewModel.importImages() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn("") { row in
                if let thumbnail = row.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 26)
                        .clipped()
                        .cornerRadius(2)
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 40, height: 26)
                }
            }
            .width(46)

            TableColumn("Name") { row in
                Text(row.name).lineLimit(1)
            }

            TableColumn("Folder") { row in
                Text(row.folder.isEmpty ? "—" : row.folder)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 140)
        }
        .tableStyle(.inset)
        // Double-clicking is how you leave the manager for the viewer: the row
        // you were judging becomes the picture you are looking at.
        .contextMenu(forSelectionType: String.self) { _ in
            Button("Open in Viewer") { openSelected() }
            Button("Export Selected…") { viewModel.batchExportDialog(named: selection) }
            Divider()
            Button("Move to Trash", role: .destructive) {
                viewModel.removeImages(named: selection)
                selection = []
            }
        } primaryAction: { _ in
            openSelected()
        }
    }

    private var gallery: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170, maximum: 250), spacing: 12)],
                spacing: 12
            ) {
                ForEach(rows) { row in
                    galleryCard(row)
                }
            }
            .padding(12)
        }
    }

    private func galleryCard(_ row: Row) -> some View {
        let isSelected = selection.contains(row.id)
        return Button {
            selectGalleryRow(row)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let thumbnail = row.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Rectangle().fill(Color.primary.opacity(0.06))
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 118)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(row.folder.isEmpty ? "Image library" : row.folder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            open(row)
        })
        .contextMenu {
            Button("Open in Viewer") { open(row) }
            Button("Export Selected…") { viewModel.batchExportDialog(named: actionSelection(for: row)) }
            Divider()
            Button("Move to Trash", role: .destructive) {
                viewModel.removeImages(named: actionSelection(for: row))
                selection = []
                selectionAnchor = nil
            }
        }
        .accessibilityRepresentation {
            Button(row.folder.isEmpty ? row.name : "\(row.name), \(row.folder)") {
                selectGalleryRow(row)
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction(named: "Open in Viewer") { open(row) }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text(selection.isEmpty ? "\(rows.count) images" : "\(selection.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let lut = viewModel.selectedLUT, selection.isEmpty == false {
                Text("· with \(lut.name)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Group {
                Button("Open") { openSelected() }
                    .disabled(selection.count != 1)
                Button("Export Selected…") { viewModel.batchExportDialog(named: selection) }
                Button("Remove", role: .destructive) {
                    viewModel.removeImages(named: selection)
                    selection = []
                    selectionAnchor = nil
                }
            }
            .disabled(selection.isEmpty)
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openSelected() {
        guard let name = selection.first,
              let row = rows.first(where: { $0.name == name }) else { return }
        open(row)
    }

    private func open(_ row: Row) {
        viewModel.selectCollectionImage(at: row.index)
        viewModel.viewerSurface = .preview
        viewModel.section = .viewer
    }

    private func selectGalleryRow(_ row: Row) {
        let modifiers = NSEvent.modifierFlags
        let result = ImageManagerSelection.selecting(
            row.id,
            orderedIDs: rows.map(\.id),
            current: selection,
            anchor: selectionAnchor,
            toggling: modifiers.contains(.command),
            extending: modifiers.contains(.shift)
        )
        selection = result.selection
        selectionAnchor = result.anchor
    }

    private func actionSelection(for row: Row) -> Set<String> {
        selection.contains(row.id) ? selection : [row.id]
    }
}
