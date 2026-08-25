import SwiftUI

/// The library as a table: what is in it, how it is described, and where it sits.
///
/// The viewer answers "what does this look like". This answers "what have I
/// got, and is it filed properly" — a different question, needing a different
/// shape. A table because the work here is comparing rows and acting on many at
/// once: nine LUTs into a folder, or tagged 日系 together, is one action, and
/// doing it nine times through a context menu is why libraries stay untidy.
struct LibraryManagerView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var selection: Set<String> = []
    @State private var isTagging = false
    @State private var isMoving = false
    @State private var newTag = ""
    @State private var newFolder = ""

    private var rows: [LibraryRow] { viewModel.visibleLUTs }

    /// The selected LUTs, in the order the table shows them.
    private var selected: [CubeLUT] {
        rows.map(\.lut).filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Two things get managed here, and they are managed differently:
            // LUTs are a library shared across projects, images belong to one.
            // A picker rather than two sections, because it is one question —
            // what am I tidying — and the answer changes often.
            Picker("", selection: $viewModel.managerTab) {
                Text("LUTs").tag(AppViewModel.ManagerTab.luts)
                Text("Images").tag(AppViewModel.ManagerTab.images)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if viewModel.managerTab == .images {
                ImageManagerView(viewModel: viewModel)
            } else {
                lutTable
            }
        }
    }

    private var lutTable: some View {
        VStack(spacing: 0) {
            Table(rows, selection: $selection) {
                TableColumn("") { row in
                    Button {
                        viewModel.tags.toggleFavourite(row.lut)
                    } label: {
                        Image(systemName: viewModel.tags.isFavourite(row.lut) ? "star.fill" : "star")
                            .foregroundStyle(viewModel.tags.isFavourite(row.lut) ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .width(28)

                TableColumn("Name") { row in
                    Text(row.lut.name).lineLimit(1)
                }

                TableColumn("Folder") { row in
                    Text(row.category)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Input") { row in
                    Text(row.lut.inputSpace == .vlog ? "V-Log" : "Display")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(60)

                TableColumn("Tags") { row in
                    // Measured and typed together: from here they are all just
                    // how the LUT is described.
                    Text(viewModel.tags.tags(for: row.lut)
                        .filter { $0.hasPrefix("input:") == false }
                        .joined(separator: "  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 240)
            }
            .tableStyle(.inset)

            Divider()
            actionBar
        }
        .sheet(isPresented: $isTagging) { tagSheet }
        .sheet(isPresented: $isMoving) { moveSheet }
    }

    /// Actions for the selection, disabled rather than hidden when nothing is
    /// selected — so it is obvious that selecting is what makes them work.
    private var actionBar: some View {
        HStack(spacing: 10) {
            Text(selection.isEmpty ? "\(rows.count) LUTs" : "\(selection.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Only the buttons dim: the count is still worth reading with
            // nothing selected, and dimming the whole bar would hide it.
            Group {
                Button("Star") { viewModel.setFavourite(selected) }
                Button("Tag…") { newTag = ""; isTagging = true }
                Button("Move…") { newFolder = ""; isMoving = true }
                Button("Remove", role: .destructive) { viewModel.remove(selected) }
            }
            .disabled(selection.isEmpty)
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var tagSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tag \(selected.count) LUT\(selected.count == 1 ? "" : "s")")
                .font(.headline)
            TextField("e.g. 日系, 婚禮", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitTag)
            HStack {
                Spacer()
                Button("Cancel") { isTagging = false }
                Button("Add") { commitTag() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var moveSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move \(selected.count) LUT\(selected.count == 1 ? "" : "s")")
                .font(.headline)
            Picker("Folder", selection: $newFolder) {
                Text("Top Level").tag("")
                ForEach(viewModel.library.categoryNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            TextField("or a new folder", text: $newFolder)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitMove)
            HStack {
                Spacer()
                Button("Cancel") { isMoving = false }
                Button("Move") { commitMove() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func commitTag() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tag.isEmpty == false else { return }
        viewModel.addTag(tag, to: selected)
        isTagging = false
    }

    private func commitMove() {
        viewModel.move(selected, toCategory: newFolder.trimmingCharacters(in: .whitespacesAndNewlines))
        isMoving = false
    }
}
