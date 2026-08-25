import SwiftUI

/// The project's images as a table, so a subset can be chosen and acted on.
///
/// Export All could only ever say "all of them", and "these six, with this
/// look" is how a set actually gets used — a shortlist for a client, the frames
/// that came out, the ones worth reprinting. Choosing is the whole feature; the
/// table exists to make choosing possible.
struct ImageManagerView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var selection: Set<String> = []

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
            if rows.isEmpty {
                empty
            } else {
                table
            }
            Divider()
            actionBar
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(viewModel.projects.current == nil ? "No project open" : "No images in this project")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if viewModel.projects.current != nil {
                Button("Import Images…") { viewModel.importImages() }
                    .buttonStyle(.borderedProminent)
            }
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
            Button("Remove from Project", role: .destructive) {
                viewModel.removeImages(named: selection)
                selection = []
            }
        } primaryAction: { _ in
            openSelected()
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
        viewModel.selectCollectionImage(at: row.index)
        viewModel.section = .viewer
    }
}
