import SwiftUI

/// Pure summary of a Manager selection. Keeping the tri-state rules outside
/// SwiftUI makes mixed metadata deterministic and directly testable.
struct LUTManagerSelectionState: Equatable {
    enum Membership: Equatable { case none, mixed, all }

    let recordIDs: Set<LUTRecordID>
    let commonTags: [String]
    let mixedTags: [String]
    let commonOrigin: LUTOrigin?
    let commonDescription: String?
    let hasMixedDescription: Bool
    let allStarred: Bool

    init(
        records: [LUTRecord],
        visibleTagsByRecordID: [LUTRecordID: Set<String>] = [:]
    ) {
        recordIDs = Set(records.map(\.id))
        let tagSets = records.map { record in
            visibleTagsByRecordID[record.id] ?? Set(record.typedTags)
        }
        let common = tagSets.dropFirst().reduce(tagSets.first ?? []) { $0.intersection($1) }
        let union = tagSets.reduce(into: Set<String>()) { $0.formUnion($1) }
        commonTags = common.sorted()
        mixedTags = union.subtracting(common).sorted()
        let origins = Set(records.map(\.origin))
        commonOrigin = origins.count == 1 ? origins.first : nil
        let descriptions = Set(records.map { $0.descriptionText ?? "" })
        commonDescription = descriptions.count == 1 ? descriptions.first : nil
        hasMixedDescription = descriptions.count > 1
        allStarred = records.isEmpty == false && records.allSatisfy(\.isStarred)
    }

    func membership(in members: Set<LUTRecordID>) -> Membership {
        let count = recordIDs.intersection(members).count
        if count == 0 { return .none }
        if count == recordIDs.count { return .all }
        return .mixed
    }
}

/// The library as a table: what is in it, how it is described, and where it sits.
///
/// The viewer answers "what does this look like". This answers "what have I
/// got, and is it filed properly" — a different question, needing a different
/// shape. A table because the work here is comparing rows and acting on many at
/// once: nine LUTs into a folder, or tagged 日系 together, is one action, and
/// doing it nine times through a context menu is why libraries stay untidy.
struct LibraryManagerView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var selection: Set<LUTID> = []
    @State private var newTag = ""
    @State private var newFolder = ""
    @State private var displayName = ""
    @State private var descriptionDraft = ""
    @State private var originChoice: OriginChoice = .unknown
    @State private var vendorName = ""
    @State private var inspectorFolder = ""

    private enum OriginChoice: String, CaseIterable {
        case mixed, unknown, vendor, custom
        var label: String {
            switch self {
            case .mixed: return "Mixed"
            case .unknown: return "Unknown"
            case .vendor: return "Brand"
            case .custom: return "Self-made"
            }
        }
    }

    private var rows: [LibraryRow] { viewModel.visibleLUTs }

    /// The selected LUTs, in the order the table shows them.
    private var selectedRows: [LibraryRow] { rows.filter { selection.contains($0.id) } }
    private var selected: [CubeLUT] { selectedRows.map(\.lut) }

    private var selectedIDs: Set<LUTID> { Set(selected.map(\.lutID)) }

    private var selectionState: LUTManagerSelectionState {
        LUTManagerSelectionState(
            records: selected.compactMap(viewModel.catalog.record(for:)),
            visibleTagsByRecordID: Dictionary(uniqueKeysWithValues: selected.map {
                ($0.lutID, Set(viewModel.allTags(for: $0).filter { $0.hasPrefix("input:") == false }))
            })
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LUT Manager")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Global library")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()
            HSplitView {
                lutTable
                    .frame(minWidth: 520)
                metadataInspector
                    .frame(minWidth: 260, idealWidth: 310, maxWidth: 390)
            }
        }
        .onAppear { viewModel.managerSelection = selection }
        .onChange(of: selection) { _, value in
            viewModel.managerSelection = value
            refreshInspectorDrafts()
        }
        .onChange(of: Set(rows.map(\.id))) { _, visibleIDs in
            selection.formIntersection(visibleIDs)
        }
    }

    private var lutTable: some View {
        VStack(spacing: 0) {
            Table(rows, selection: $selection) {
                TableColumn("") { row in
                    Button {
                        viewModel.toggleStarred(row.lut)
                    } label: {
                        Image(systemName: viewModel.isStarred(row.lut) ? "star.fill" : "star")
                            .foregroundStyle(viewModel.isStarred(row.lut) ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .width(28)

                TableColumn("Name") { row in
                    Text(viewModel.catalog.effectiveName(for: row.lut)).lineLimit(1)
                }

                TableColumn("Folder") { row in
                    Text(row.category)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Brand") { row in
                    Text(viewModel.managerBrandLabel(for: row.lut))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Description") { row in
                    let description = viewModel.catalog.description(for: row.lut)
                    Text(description.isEmpty ? "—" : description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 130, ideal: 220)

                TableColumn("Input") { row in
                    Text(viewModel.managerInputLabel(for: row.lut))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 90, ideal: 130)

                TableColumn("Tags") { row in
                    // Measured and typed together: from here they are all just
                    // how the LUT is described.
                    Text(viewModel.allTags(for: row.lut)
                        .filter { $0.hasPrefix("input:") == false }
                        .joined(separator: "  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 240)
            }
            .tableStyle(.inset)

        }
    }

    private var metadataInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Metadata").font(.headline)
                    Spacer()
                    Text(selection.isEmpty ? "No selection" : "\(selection.count) selected")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if selection.isEmpty {
                    ContentUnavailableView(
                        "Select LUTs", systemImage: "slider.horizontal.3",
                        description: Text("Edit Name, Brand, Description, Tags, folders, Starred, and Collections here.")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    nameSection
                    Divider()
                    originSection
                    Divider()
                    descriptionSection
                    Divider()
                    tagsSection
                    Divider()
                    collectionsSection
                    Divider()
                    folderSection
                    Divider()
                    starredSection
                    Divider()
                    removeSection
                    Text("Transform and colour changes belong in LUT Editor.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Name").font(.subheadline.weight(.semibold))
            TextField(selection.count == 1 ? "Uses filename when empty" : "Available for one LUT", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .disabled(selection.count != 1)
                .onSubmit(commitDisplayName)
            if selection.count == 1 {
                HStack {
                    Button("Apply", action: commitDisplayName).buttonStyle(.bordered)
                    Button("Reset to Filename") {
                        viewModel.catalog.setDisplayName(nil, for: selectedIDs)
                        refreshInspectorDrafts()
                    }
                    .buttonStyle(.borderless)
                }
                Text("The .cube filename is not changed.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var originSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Brand").font(.subheadline.weight(.semibold))
            Picker("Brand", selection: $originChoice) {
                ForEach(OriginChoice.allCases, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .labelsHidden()
            .onChange(of: originChoice) { _, value in
                guard value != .mixed else { return }
                commitOrigin()
            }
            if originChoice == .vendor {
                TextField("Brand name", text: $vendorName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitOrigin)
                Button("Apply Brand", action: commitOrigin).buttonStyle(.bordered)
            }
            Text("Used for Brand browsing; it does not change the LUT file.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Description").font(.subheadline.weight(.semibold))
            if selectionState.hasMixedDescription {
                Text("Mixed descriptions. Applying replaces the Description on all selected LUTs.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            TextEditor(text: $descriptionDraft)
                .font(.body)
                .frame(minHeight: 72, maxHeight: 130)
                .padding(5)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                }
                .accessibilityLabel("Description")
            HStack {
                Button(selection.count == 1 ? "Apply" : "Apply to \(selection.count) LUTs") {
                    commitDescription()
                }
                .buttonStyle(.bordered)
                Button("Clear") {
                    descriptionDraft = ""
                    commitDescription()
                }
                .buttonStyle(.borderless)
            }
            Text("Provenance and context only; the .cube file is not changed.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags").font(.subheadline.weight(.semibold))
            if commonVisibleTags.isEmpty == false || mixedVisibleTags.isEmpty == false {
                FlowLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(commonVisibleTags, id: \.self) { tag in
                        Button { viewModel.removeTag(tag, from: selected) } label: {
                            Label(tag, systemImage: "xmark").labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Remove from selection")
                    }
                    ForEach(mixedVisibleTags, id: \.self) { tag in
                        mixedTagChip(tag)
                    }
                }
            } else {
                Text("No Tags")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("Add Tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addInspectorTag)
                Button(action: addInspectorTag) { Image(systemName: "plus") }
                    .buttonStyle(.bordered)
                    .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func mixedTagChip(_ tag: String) -> some View {
        HStack(spacing: 5) {
            Text(tag)
                .foregroundStyle(.secondary)
            Text("Mixed")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button {
                viewModel.addTag(tag, to: selected)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(tag) to all selected LUTs")
            .help("Add to all selected LUTs")
            Button {
                viewModel.removeTag(tag, from: selected)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(tag) from selected LUTs")
            .help("Remove from every selected LUT that has this Tag")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Collections").font(.subheadline.weight(.semibold))
            if viewModel.catalog.collections.isEmpty {
                Text("Create a Collection from the left sidebar.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.catalog.collections) { collection in
                    let members = viewModel.catalog.members(of: collection.id)
                    let membership = selectionState.membership(in: members)
                    Button {
                        viewModel.catalog.setMembership(
                            membership != .all,
                            collectionID: collection.id,
                            recordIDs: selectedIDs
                        )
                    } label: {
                        HStack {
                            Image(systemName: membership == .none ? "square" : (membership == .all ? "checkmark.square.fill" : "minus.square.fill"))
                            Text(collection.name)
                            Spacer()
                            let count = selectedIDs.intersection(members).count
                            if count > 0 { Text("\(count)/\(selectedIDs.count)").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var starredSection: some View {
        let allStarred = selectionState.allStarred
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Starred").font(.subheadline.weight(.semibold))
                Text(allStarred ? "All selected LUTs are starred" : "Star the whole selection")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button(allStarred ? "Unstar" : "Star") {
                viewModel.catalog.setStarred(!allStarred, for: selectedIDs)
            }
            .buttonStyle(.bordered)
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Physical Folder").font(.subheadline.weight(.semibold))
            if selection.count == 1 {
                Picker("Folder", selection: $inspectorFolder) {
                    Text("Top Level").tag("")
                    ForEach(viewModel.library.categoryNames, id: \.self) { folder in
                        Text(folder).tag(folder)
                    }
                }
                .labelsHidden()
                .onChange(of: inspectorFolder) { oldFolder, newFolder in
                    guard let lut = selected.first,
                          newFolder != selectedRows.first?.category
                    else { return }
                    if viewModel.moveLUT(lut, toCategory: newFolder) == false {
                        inspectorFolder = oldFolder
                    }
                }
                Text(inspectorFolder.isEmpty ? "Library root" : inspectorFolder)
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Picker("Folder", selection: $newFolder) {
                    Text("Top Level").tag("")
                    ForEach(viewModel.library.categoryNames, id: \.self) { folder in
                        Text(folder).tag(folder)
                    }
                }
                TextField("or enter a new folder", text: $newFolder)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitMove)
                Button("Move \(selection.count) LUTs", action: commitMove)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var removeSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Library").font(.subheadline.weight(.semibold))
                Text("Moves managed LUT files to the Trash.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button(selection.count == 1 ? "Remove LUT" : "Remove \(selection.count) LUTs", role: .destructive) {
                viewModel.remove(selected)
                selection.removeAll()
            }
            .buttonStyle(.bordered)
        }
    }

    private var commonVisibleTags: [String] {
        selectionState.commonTags
    }

    private var mixedVisibleTags: [String] {
        selectionState.mixedTags
    }

    private func refreshInspectorDrafts() {
        guard let first = selected.first else {
            displayName = ""; descriptionDraft = ""; originChoice = .unknown
            vendorName = ""; inspectorFolder = ""; newFolder = ""; return
        }
        displayName = selected.count == 1
            ? (viewModel.catalog.record(for: first)?.displayNameOverride ?? "") : ""
        descriptionDraft = selectionState.commonDescription ?? ""
        inspectorFolder = selected.count == 1 ? (selectedRows.first?.category ?? "") : ""
        newFolder = ""
        guard let origin = selectionState.commonOrigin else {
            originChoice = .mixed; vendorName = ""; return
        }
        switch origin {
        case .unknown: originChoice = .unknown; vendorName = ""
        case .custom: originChoice = .custom; vendorName = ""
        case .vendor(let name): originChoice = .vendor; vendorName = name
        }
    }

    private func commitDisplayName() {
        guard selection.count == 1 else { return }
        viewModel.catalog.setDisplayName(displayName, for: selectedIDs)
    }

    private func commitDescription() {
        viewModel.catalog.setDescription(descriptionDraft, for: selectedIDs)
        refreshInspectorDrafts()
    }

    private func commitOrigin() {
        switch originChoice {
        case .mixed: return
        case .unknown: viewModel.catalog.setOrigin(.unknown, for: selectedIDs)
        case .custom: viewModel.catalog.setOrigin(.custom, for: selectedIDs)
        case .vendor:
            let name = vendorName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false else { return }
            viewModel.catalog.setOrigin(.vendor(name), for: selectedIDs)
        }
    }

    private func addInspectorTag() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tag.isEmpty == false else { return }
        viewModel.catalog.addTag(tag, to: selectedIDs)
        newTag = ""
    }

    private func commitMove() {
        viewModel.move(selected, toCategory: newFolder.trimmingCharacters(in: .whitespacesAndNewlines))
        newFolder = ""
    }
}
