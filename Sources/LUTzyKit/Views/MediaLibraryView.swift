import SwiftUI

struct MediaLibrarySidebar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Media Library").font(.headline)
                Spacer()
                Text("\(viewModel.media.records.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            List(selection: $viewModel.selectedMediaFolder) {
                Label("All Media", systemImage: "photo.on.rectangle.angled")
                    .tag(nil as String?)
                Section("Folders") {
                    ForEach(viewModel.media.folders, id: \.path) { folder in
                        HStack {
                            Label(folder.path.isEmpty ? "Top Level" : folder.path, systemImage: "folder")
                            Spacer()
                            Text("\(folder.count)").foregroundStyle(.secondary)
                        }
                        .tag(folder.path as String?)
                    }
                }
            }
            .listStyle(.sidebar)
            Divider()
            Button { viewModel.importImages() } label: {
                Label("Import Images or Videos…", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
    }
}

struct MediaLibraryView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var searchText = ""

    private var records: [MediaRecord] {
        let base = viewModel.media.records(in: viewModel.selectedMediaFolder)
        guard searchText.isEmpty == false else { return base }
        return base.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(viewModel.selectedMediaFolder ?? "All Media")
                    .font(.subheadline.weight(.semibold))
                Text("\(records.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                TextField("Search Media", text: $searchText)
                    .textFieldStyle(.roundedBorder).frame(width: 210)
                Picker("View", selection: $viewModel.media.viewMode) {
                    Label("Columns", systemImage: "rectangle.split.3x1").tag(MediaLibraryViewMode.columns)
                    Label("List", systemImage: "list.bullet").tag(MediaLibraryViewMode.list)
                }
                .pickerStyle(.segmented).fixedSize()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()

            if records.isEmpty { emptyState }
            else if viewModel.media.viewMode == .list { listView }
            else { columnsView }
        }
    }

    private var listView: some View {
        Table(records, selection: $viewModel.media.selectedID) {
            TableColumn("Name") { record in mediaName(record) }
            TableColumn("Kind") { record in Text(record.kind == .image ? "Image" : "Video") }
                .width(70)
            TableColumn("Folder") { record in
                Text(record.logicalFolder.isEmpty ? "—" : record.logicalFolder)
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            TableColumn("Source") { record in
                Text(viewModel.media.disambiguator(for: record) ?? "Local")
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .tableStyle(.inset)
        .contextMenu(forSelectionType: MediaRecordID.self) { ids in
            if let id = ids.first, let record = viewModel.media.record(id) {
                Button("Open in Viewer") { viewModel.openMedia(record) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let record = viewModel.media.record(id) { viewModel.openMedia(record) }
        }
    }

    private var columnsView: some View {
        HSplitView {
            List(selection: $viewModel.selectedMediaFolder) {
                Text("All Media").tag(nil as String?)
                ForEach(viewModel.media.folders, id: \.path) { folder in
                    Label(folder.path.isEmpty ? "Top Level" : folder.path, systemImage: "folder")
                        .tag(folder.path as String?)
                }
            }
            .frame(minWidth: 180, idealWidth: 240)

            List(records, selection: $viewModel.media.selectedID) { record in
                mediaName(record)
                    .tag(record.id)
                    .onTapGesture(count: 2) { viewModel.openMedia(record) }
            }
            .frame(minWidth: 280)

            if let record = viewModel.media.selectedRecord {
                mediaPreview(record).frame(minWidth: 260, idealWidth: 340)
            } else {
                ContentUnavailableView("Select Media", systemImage: "photo")
                    .frame(minWidth: 260)
            }
        }
    }

    private func mediaName(_ record: MediaRecord) -> some View {
        HStack(spacing: 8) {
            if let image = viewModel.thumbnail(for: record) {
                Image(nsImage: image).resizable().scaledToFill().frame(width: 42, height: 28).clipped().cornerRadius(3)
            } else {
                Image(systemName: record.kind == .video ? "film" : "photo")
                    .frame(width: 42, height: 28).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
            }
            Text(record.displayName).lineLimit(1)
            if let detail = viewModel.media.disambiguator(for: record) {
                Text(detail).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func mediaPreview(_ record: MediaRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            if let image = viewModel.thumbnail(for: record) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 260)
            } else {
                Image(systemName: record.kind == .video ? "play.rectangle" : "photo")
                    .font(.system(size: 54)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
            }
            Text(record.displayName).font(.headline)
            Text(record.logicalPath).font(.caption).foregroundStyle(.secondary)
            Button("Open in Viewer") { viewModel.openMedia(record) }
                .buttonStyle(.borderedProminent).disabled(record.kind == .video)
            Spacer()
        }
        .padding(18)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Media", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Import images or videos. Folder hierarchy will be preserved.")
        } actions: {
            Button("Import Media…") { viewModel.importImages() }.buttonStyle(.borderedProminent)
        }
    }
}
