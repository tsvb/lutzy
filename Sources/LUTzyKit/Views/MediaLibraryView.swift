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
                Picker("View", selection: Binding(
                    get: { viewModel.media.viewMode },
                    set: { viewModel.media.viewMode = $0 }
                )) {
                    Label("Columns", systemImage: "rectangle.split.3x1").tag(MediaLibraryViewMode.columns)
                    Label("List", systemImage: "list.bullet").tag(MediaLibraryViewMode.list)
                }
                .pickerStyle(.segmented).fixedSize()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()

            Group {
                if records.isEmpty { emptyState }
                else if viewModel.media.viewMode == .list { listView }
                else { columnsView }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var listView: some View {
        Table(records, selection: Binding(
            get: { viewModel.media.selectedID },
            set: { viewModel.media.selectedID = $0 }
        )) {
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
        MediaColumnsBrowser(viewModel: viewModel, searchText: searchText)
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

/// Finder-style hierarchy: choosing a folder adds its children in the next
/// column while every ancestor stays visible. Media selection is the same
/// `MediaRecordID` binding used by List mode.
private struct MediaColumnsBrowser: View {
    @ObservedObject var viewModel: AppViewModel
    let searchText: String

    @State private var pathStack: [String] = []

    private var available: [MediaRecord] {
        viewModel.media.records.filter(\.isAvailable)
    }

    var body: some View {
        HSplitView {
            Group {
                if searchText.isEmpty {
                    hierarchy
                } else {
                    searchResults
                }
            }
            .frame(minWidth: 420, maxHeight: .infinity, alignment: .topLeading)

            if let record = viewModel.media.selectedRecord {
                preview(record)
                    .frame(minWidth: 260, idealWidth: 340, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Select Media", systemImage: "photo")
                    .frame(minWidth: 260, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { synchronize(to: viewModel.selectedMediaFolder) }
        .onChange(of: viewModel.selectedMediaFolder) { _, path in synchronize(to: path) }
    }

    private var hierarchy: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0...pathStack.count, id: \.self) { index in
                        let path = index == 0 ? "" : pathStack[index - 1]
                        column(path: path, index: index)
                            .frame(width: 245)
                        Divider()
                    }
                }
                .frame(minHeight: geometry.size.height, maxHeight: geometry.size.height, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var searchResults: some View {
        List(filteredSearchResults, selection: selectedRecordBinding) { record in
            recordRow(record)
                .tag(record.id)
                .onTapGesture(count: 2) { viewModel.openMedia(record) }
        }
        .overlay(alignment: .topLeading) {
            Text("Search Results")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(10)
                .allowsHitTesting(false)
        }
    }

    private func column(path: String, index: Int) -> some View {
        List(selection: selectedRecordBinding) {
            ForEach(childFolders(of: path), id: \.path) { folder in
                Button {
                    chooseFolder(folder.path, fromColumn: index)
                } label: {
                    HStack {
                        Label(folder.name, systemImage: "folder")
                        Spacer()
                        Text("\(folder.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    pathStack.indices.contains(index) && pathStack[index] == folder.path
                        ? Color.accentColor.opacity(0.18) : Color.clear
                )
            }

            ForEach(immediateMedia(in: path)) { record in
                recordRow(record)
                    .tag(record.id)
                    .onTapGesture(count: 2) { viewModel.openMedia(record) }
            }
        }
        .overlay(alignment: .topLeading) {
            Text(path.isEmpty ? "Media" : URL(fileURLWithPath: path).lastPathComponent)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(10)
                .allowsHitTesting(false)
        }
    }

    private var selectedRecordBinding: Binding<MediaRecordID?> {
        Binding(
            get: { viewModel.media.selectedID },
            set: { viewModel.media.selectedID = $0 }
        )
    }

    private func childFolders(of path: String) -> [(path: String, name: String, count: Int)] {
        let prefix = path.isEmpty ? "" : path + "/"
        var children: [String: Int] = [:]
        for record in available {
            let folder = record.logicalFolder
            guard folder.hasPrefix(prefix) else { continue }
            let remainder = String(folder.dropFirst(prefix.count))
            guard let name = remainder.split(separator: "/").first.map(String.init), name.isEmpty == false else {
                continue
            }
            let childPath = path.isEmpty ? name : path + "/" + name
            children[childPath, default: 0] += 1
        }
        return children.map { path, count in
            (path: path, name: URL(fileURLWithPath: path).lastPathComponent, count: count)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func immediateMedia(in path: String) -> [MediaRecord] {
        available.filter { $0.logicalFolder == path }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var filteredSearchResults: [MediaRecord] {
        available.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.logicalPath.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func chooseFolder(_ path: String, fromColumn index: Int) {
        pathStack = Array(pathStack.prefix(index)) + [path]
        viewModel.selectedMediaFolder = path
    }

    private func synchronize(to path: String?) {
        guard let path, path.isEmpty == false else {
            pathStack = []
            return
        }
        var accumulated: [String] = []
        var current = ""
        for component in path.split(separator: "/") {
            current = current.isEmpty ? String(component) : current + "/" + component
            accumulated.append(current)
        }
        pathStack = accumulated
    }

    private func recordRow(_ record: MediaRecord) -> some View {
        HStack(spacing: 8) {
            if let image = viewModel.thumbnail(for: record) {
                Image(nsImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 42, height: 28).clipped().cornerRadius(3)
            } else {
                Image(systemName: record.kind == .video ? "film" : "photo")
                    .frame(width: 42, height: 28)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(record.displayName).lineLimit(1)
                if let detail = viewModel.media.disambiguator(for: record) {
                    Text(detail).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func preview(_ record: MediaRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            if let image = viewModel.thumbnail(for: record) {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 260)
            } else {
                Image(systemName: record.kind == .video ? "play.rectangle" : "photo")
                    .font(.system(size: 54)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            Text(record.displayName).font(.headline)
            Text(record.logicalPath).font(.caption).foregroundStyle(.secondary)
            Button("Open in Viewer") { viewModel.openMedia(record) }
                .buttonStyle(.borderedProminent)
                .disabled(record.kind == .video)
            Spacer()
        }
        .padding(18)
    }
}
