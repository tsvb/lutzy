import SwiftUI

/// Visual local LUT browser. Selecting a card opens detail here; it does not
/// silently mutate the Viewer document.
struct LUTLibraryView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var grouping: LUTLibraryGrouping = .folder
    @State private var selectedShelfID: String?
    @State private var shelfReturnFocus: LUTLibraryFocusTarget?
    @State private var selectedCardTarget: LUTLibraryFocusTarget?
    @FocusState private var keyboardFocus: LUTLibraryFocusTarget?
    @AccessibilityFocusState private var accessibilityFocus: LUTLibraryFocusTarget?

    private var shelves: [LUTLibraryShelf] {
        viewModel.libraryDiscoveryShelves(for: grouping)
    }

    private var selectedShelf: LUTLibraryShelf? {
        selectedShelfID.flatMap { id in shelves.first(where: { $0.id == id }) }
    }

    var body: some View {
        ZStack {
            discoveryHome
                .allowsHitTesting(selectedShelf == nil && viewModel.selectedLibraryLUT == nil)
                .accessibilityHidden(selectedShelf != nil || viewModel.selectedLibraryLUT != nil)

            if let selectedShelf {
                shelfGrid(selectedShelf)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .allowsHitTesting(viewModel.selectedLibraryLUT == nil)
                    .accessibilityHidden(viewModel.selectedLibraryLUT != nil)
            }

            if let lut = viewModel.selectedLibraryLUT {
                LUTLibraryDetailView(
                    lut: lut,
                    viewModel: viewModel,
                    backLabel: selectedShelf.map { "Back to \($0.title)" } ?? "Back to \(grouping.label)",
                    accessibilityFocus: $accessibilityFocus
                ) {
                    let returnTarget = selectedCardTarget
                    viewModel.setLUTDetailFocused(false)
                    viewModel.selectedLibraryLUTID = nil
                    restoreFocus(returnTarget)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.libraryLUTSource) { _, _ in
            selectedShelfID = nil
            viewModel.selectedLibraryLUTID = nil
            shelfReturnFocus = nil
            selectedCardTarget = nil
        }
        .onChange(of: grouping) { _, _ in
            selectedShelfID = nil
            viewModel.selectedLibraryLUTID = nil
            shelfReturnFocus = nil
            selectedCardTarget = nil
        }
    }

    private var discoveryHome: some View {
        VStack(spacing: 0) {
            discoveryHeader
            Divider()

            if shelves.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: grouping.symbol)
                } description: {
                    Text(emptyDescription)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(shelves) { shelf in
                            discoveryShelf(shelf)
                                .id(shelf.id)
                        }
                    }
                    .padding(.vertical, 18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var discoveryHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Discover LUTs")
                    .font(.title2.weight(.semibold))
                Text("\(viewModel.title(for: viewModel.libraryLUTSource)) · \(viewModel.luts(for: viewModel.libraryLUTSource).count) local LUTs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Group LUTs", selection: $grouping) {
                ForEach(LUTLibraryGrouping.allCases) { grouping in
                    Label(grouping.label, systemImage: grouping.symbol)
                        .tag(grouping)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 520)
            .accessibilityLabel("Group LUTs")
            .focused($keyboardFocus, equals: .groupingControl)
            .accessibilityFocused($accessibilityFocus, equals: .groupingControl)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func discoveryShelf(_ shelf: LUTLibraryShelf) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    openShelf(shelf, from: .shelfHeading(shelf.id))
                } label: {
                    HStack(spacing: 6) {
                        Text(shelf.title)
                            .font(.headline)
                        Text("\(shelf.luts.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .focused($keyboardFocus, equals: .shelfHeading(shelf.id))
                .accessibilityFocused($accessibilityFocus, equals: .shelfHeading(shelf.id))

                Spacer()

                Button("View All") {
                    openShelf(shelf, from: .viewAll(shelf.id))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("View all \(shelf.title) LUTs")
                .focused($keyboardFocus, equals: .viewAll(shelf.id))
                .accessibilityFocused($accessibilityFocus, equals: .viewAll(shelf.id))
            }
            .padding(.horizontal, 18)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(shelf.luts) { lut in
                        let focusTarget = LUTLibraryFocusTarget.homeCard(
                            shelfID: shelf.id, lutID: lut.lutID
                        )
                        LUTPreviewCard(
                            lut: lut,
                            viewModel: viewModel,
                            renderingActive: selectedShelf == nil && viewModel.selectedLibraryLUT == nil,
                            libraryKeyboardFocus: $keyboardFocus,
                            libraryAccessibilityFocus: $accessibilityFocus,
                            libraryFocusTarget: focusTarget,
                            librarySelected: selectedCardTarget == focusTarget,
                            onActivate: { openDetail(lut, from: focusTarget) },
                            onLibraryContentMutation: handleContentMutation
                        )
                            .frame(width: 220, alignment: .top)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func shelfGrid(_ shelf: LUTLibraryShelf) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    let returnTarget = shelfReturnFocus
                    selectedShelfID = nil
                    if selectedCardTarget?.isGridCard == true { selectedCardTarget = nil }
                    restoreFocus(returnTarget)
                } label: {
                    Label("Back to Discover", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .focused($keyboardFocus, equals: .gridBack(shelf.id))
                .accessibilityFocused($accessibilityFocus, equals: .gridBack(shelf.id))

                Text(grouping.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            LUTPreviewGalleryView(
                viewModel: viewModel,
                luts: shelf.luts,
                title: shelf.title,
                renderingActive: viewModel.selectedLibraryLUT == nil,
                libraryShelfID: shelf.id,
                libraryKeyboardFocus: $keyboardFocus,
                libraryAccessibilityFocus: $accessibilityFocus,
                selectedLibraryCardTarget: selectedCardTarget,
                onLibraryActivate: openDetail,
                onLibraryContentMutation: handleContentMutation
            )
        }
    }

    private func openShelf(_ shelf: LUTLibraryShelf, from origin: LUTLibraryFocusTarget) {
        shelfReturnFocus = origin
        selectedShelfID = shelf.id
        selectedCardTarget = nil
        moveFocus(to: .gridBack(shelf.id))
    }

    private func openDetail(_ lut: CubeLUT, from origin: LUTLibraryFocusTarget) {
        selectedCardTarget = origin
        viewModel.selectLibraryLUT(lut)
        Task { @MainActor in
            await Task.yield()
            accessibilityFocus = .detailBack
        }
    }

    private func restoreFocus(_ target: LUTLibraryFocusTarget?) {
        guard let target else { return }
        let resolved = target.resolved(in: shelves)
        if target.isCard && resolved != target { selectedCardTarget = nil }
        if selectedShelfID != nil && selectedShelf == nil { selectedShelfID = nil }
        moveFocus(to: resolved)
    }

    private func handleContentMutation(from target: LUTLibraryFocusTarget) {
        Task { @MainActor in
            await Task.yield()
            let resolved = target.resolved(in: shelves)
            guard resolved != target else { return }
            if target.isCard { selectedCardTarget = nil }
            if selectedShelfID != nil && selectedShelf == nil { selectedShelfID = nil }
            moveFocus(to: resolved)
        }
    }

    private func moveFocus(to target: LUTLibraryFocusTarget) {
        Task { @MainActor in
            await Task.yield()
            keyboardFocus = target
            accessibilityFocus = target
        }
    }

    private var emptyTitle: String {
        switch grouping {
        case .folder: return "No Folders in This Source"
        case .collectionAndStar: return "No Collections or Starred LUTs"
        case .brand: return "No Brands in This Source"
        case .tag: return "No Tags in This Source"
        }
    }

    private var emptyDescription: String {
        switch grouping {
        case .folder: return "Import LUT folders or choose another source."
        case .collectionAndStar: return "Create Collections in LUT Manager or Star LUTs while browsing."
        case .brand: return "Set Brand in LUT Manager to organise confirmed brands."
        case .tag: return "Add Tags in LUT Manager or let local measurement finish."
        }
    }
}

private struct LUTLibraryDetailView: View {
    let lut: CubeLUT
    @ObservedObject var viewModel: AppViewModel
    let backLabel: String
    let accessibilityFocus: AccessibilityFocusState<LUTLibraryFocusTarget?>.Binding
    let onBack: () -> Void

    @State private var rendered: LUTLibraryRenderPair?
    @State private var split = 0.5
    @FocusState private var comparisonFocused: Bool

    private struct RenderKey: Hashable {
        let lutID: LUTID
        let sampleID: String
        let revision: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            detailNavigation
            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    comparison
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .focusable()
                        .focused($comparisonFocused)
                        .onMoveCommand { direction in
                            switch direction {
                            case .left: adjustSplit(by: -0.05)
                            case .right: adjustSplit(by: 0.05)
                            default: break
                            }
                        }
                        .onChange(of: comparisonFocused) { _, focused in
                            viewModel.setLUTDetailFocused(focused)
                        }
                    Divider()
                    sampleStrip
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(viewModel.catalog.effectiveName(for: lut))
                            .font(.title2.weight(.semibold))
                        LabeledContent("Brand", value: viewModel.catalog.origin(for: lut).label)
                        LabeledContent("Input Profile", value: viewModel.managerInputLabel(for: lut))
                        LabeledContent("Size", value: "\(lut.size)³")
                        let description = viewModel.catalog.description(for: lut)
                        if description.isEmpty == false {
                            Text("Description").font(.subheadline.weight(.semibold))
                            Text(description)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        LabeledContent("Sample", value: viewModel.selectedLibrarySample.name)
                        Text(viewModel.selectedLibrarySample.note)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(viewModel.selectedLibrarySample.colorProfile)
                            .font(.caption2).foregroundStyle(.tertiary)
                        Text(viewModel.selectedLibrarySample.provenance)
                            .font(.caption2).foregroundStyle(.tertiary)

                        if viewModel.allTags(for: lut).isEmpty == false {
                            Text("Tags").font(.subheadline.weight(.semibold))
                            FlowLayout(spacing: 5, lineSpacing: 5) {
                                ForEach(viewModel.allTags(for: lut), id: \.self) { tag in
                                    Text(tag).font(.caption2)
                                        .padding(.horizontal, 7).padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.08), in: Capsule())
                                }
                            }
                        }

                        Button("Open in Viewer") { viewModel.openLibraryLUTInViewer(lut) }
                            .buttonStyle(.borderedProminent)
                        Button(viewModel.isStarred(lut) ? "Unstar" : "Star") {
                            viewModel.toggleStarred(lut)
                        }
                        Menu("Add to Collection") {
                            ForEach(viewModel.catalog.collections) { collection in
                                Button(collection.name) {
                                    viewModel.catalog.setMembership(
                                        true, collectionID: collection.id, recordIDs: [lut.lutID]
                                    )
                                }
                            }
                        }
                        .disabled(viewModel.catalog.collections.isEmpty)
                    }
                    .padding(18)
                }
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 380)
            }
        }
        .task(id: RenderKey(
            lutID: lut.lutID,
            sampleID: viewModel.selectedLibrarySampleID,
            revision: viewModel.lutGalleryRevision
        )) {
            rendered = nil
            rendered = await viewModel.makeLUTLibraryDetailImages(
                for: lut,
                sample: viewModel.selectedLibrarySample,
                maxSize: CGSize(width: 1400, height: 900)
            )
        }
        .onAppear {
            Task { @MainActor in comparisonFocused = true }
        }
        .onDisappear {
            viewModel.setLUTDetailFocused(false)
        }
    }

    private var detailNavigation: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Label(backLabel, systemImage: "chevron.left")
                    .font(.headline)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("\(backLabel) (Esc)")
            .accessibilityFocused(accessibilityFocus, equals: .detailBack)

            Spacer()

            Text("LUT Detail")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(.bar)
    }

    private var comparison: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.9)
                if let rendered {
                    // Keep comparison semantics consistent with Viewer:
                    // Before is always on the left and After is on the right.
                    Image(nsImage: viewModel.isShowingLibraryOriginal
                          ? rendered.original : rendered.graded)
                        .resizable().scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                    if viewModel.isShowingLibraryOriginal == false {
                        Image(nsImage: rendered.original)
                            .resizable().scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: geo.size.width * split)
                            }

                        Rectangle()
                            .fill(Color.white.opacity(0.95))
                            .frame(width: 2, height: geo.size.height)
                            .offset(x: geo.size.width * split - 1)
                            .shadow(color: .black.opacity(0.6), radius: 2)

                        Image(systemName: "arrow.left.and.right.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.black.opacity(0.55))
                            .offset(x: geo.size.width * split - 11)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    comparisonFocused = true
                    split = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                }
            )
            .overlay(alignment: .top) {
                HStack {
                    comparisonLabel("Before")
                    Spacer()
                    if viewModel.isShowingLibraryOriginal == false {
                        comparisonLabel("After")
                    }
                }
                .padding(12)
            }
            .help("Drag to compare. Hold Space to show the complete original.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Before and After comparison")
            .accessibilityValue(comparisonAccessibilityValue)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjustSplit(by: 0.05)
                case .decrement: adjustSplit(by: -0.05)
                @unknown default: break
                }
            }
        }
    }

    private var comparisonAccessibilityValue: String {
        if viewModel.isShowingLibraryOriginal {
            return "Before, 100 percent"
        }
        return "Before \(Int(split * 100)) percent, After \(Int((1 - split) * 100)) percent"
    }

    private func adjustSplit(by amount: Double) {
        comparisonFocused = true
        split = min(max(split + amount, 0), 1)
    }

    private func comparisonLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var sampleStrip: some View {
        HStack(spacing: 10) {
            ForEach(viewModel.librarySamples) { sample in
                Button {
                    viewModel.selectedLibrarySampleID = sample.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Group {
                            if let url = sample.url, let image = NSImage(contentsOf: url) {
                                Image(nsImage: image).resizable().scaledToFill()
                            } else {
                                Color.primary.opacity(0.07)
                            }
                        }
                        .frame(width: 86, height: 52)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(viewModel.selectedLibrarySampleID == sample.id
                                        ? Color.accentColor : Color.primary.opacity(0.1),
                                        lineWidth: viewModel.selectedLibrarySampleID == sample.id ? 2 : 1)
                        }
                        Text(sample.name).font(.caption2).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use \(sample.name) sample")
            }
            Spacer()
            Text("Fixed samples")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
