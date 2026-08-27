import AppKit
import SwiftUI

/// A contact sheet for auditioning every LUT below the selected folder on the
/// photograph that is currently open.
struct LUTPreviewGalleryView: View {
    @ObservedObject var viewModel: AppViewModel
    let suppliedLUTs: [CubeLUT]?
    let suppliedTitle: String?
    let renderingActive: Bool
    let libraryShelfID: String?
    let libraryKeyboardFocus: FocusState<LUTLibraryFocusTarget?>.Binding?
    let libraryAccessibilityFocus: AccessibilityFocusState<LUTLibraryFocusTarget?>.Binding?
    let selectedLibraryCardTarget: LUTLibraryFocusTarget?
    let onLibraryActivate: ((CubeLUT, LUTLibraryFocusTarget) -> Void)?
    let onLibraryContentMutation: ((LUTLibraryFocusTarget) -> Void)?

    @State private var searchText = ""
    @AppStorage("lutzy.viewerLUTCardWidth") private var cardWidth = 220.0

    init(
        viewModel: AppViewModel,
        luts: [CubeLUT]? = nil,
        title: String? = nil,
        renderingActive: Bool = true,
        libraryShelfID: String? = nil,
        libraryKeyboardFocus: FocusState<LUTLibraryFocusTarget?>.Binding? = nil,
        libraryAccessibilityFocus: AccessibilityFocusState<LUTLibraryFocusTarget?>.Binding? = nil,
        selectedLibraryCardTarget: LUTLibraryFocusTarget? = nil,
        onLibraryActivate: ((CubeLUT, LUTLibraryFocusTarget) -> Void)? = nil,
        onLibraryContentMutation: ((LUTLibraryFocusTarget) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.suppliedLUTs = luts
        self.suppliedTitle = title
        self.renderingActive = renderingActive
        self.libraryShelfID = libraryShelfID
        self.libraryKeyboardFocus = libraryKeyboardFocus
        self.libraryAccessibilityFocus = libraryAccessibilityFocus
        self.selectedLibraryCardTarget = selectedLibraryCardTarget
        self.onLibraryActivate = onLibraryActivate
        self.onLibraryContentMutation = onLibraryContentMutation
    }

    private var baseLUTs: [CubeLUT] { suppliedLUTs ?? viewModel.galleryLUTs }

    private var visibleLUTs: [CubeLUT] {
        guard searchText.isEmpty == false else { return baseLUTs }
        let query = searchText.localizedLowercase
        return baseLUTs.filter {
            viewModel.catalog.effectiveName(for: $0).localizedLowercase.contains(query)
        }
    }

    private var folderName: String {
        if let suppliedTitle { return suppliedTitle }
        return viewModel.title(for: viewModel.section == .lutLibrary
            ? viewModel.libraryLUTSource : viewModel.viewerLUTSource)
    }

    var body: some View {
        VStack(spacing: 0) {
            galleryHeader
            Divider()

            if visibleLUTs.isEmpty {
                emptyState
            } else {
                gallery
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var galleryHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: suppliedLUTs == nil ? "folder.fill" : "rectangle.grid.2x2.fill")
                .foregroundStyle(Color.accentColor)
            Text(folderName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("\(visibleLUTs.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if viewModel.section != .lutLibrary && viewModel.comparisonLayout.isGrid {
                Rectangle()
                    .fill(Color.primary.opacity(0.16))
                    .frame(width: 1, height: 16)
                Label(
                    "Assigning to Cell \((viewModel.activeGridCellIndex ?? 0) + 1)",
                    systemImage: "scope"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                Text("Click a look or drag it onto any cell")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(suppliedLUTs == nil ? "Search this folder" : "Search this shelf", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
                if searchText.isEmpty == false {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            Image(systemName: "rectangle.grid.3x2")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $cardWidth, in: 150...320)
                .frame(width: 105)
                .help("Preview size")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var gallery: some View {
        let columns = [
            GridItem(
                .adaptive(
                    minimum: CGFloat(cardWidth),
                    maximum: CGFloat(cardWidth) * 1.35
                ),
                spacing: 8
            )
        ]

        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(visibleLUTs) { lut in
                    let focusTarget = libraryShelfID.map {
                        LUTLibraryFocusTarget.gridCard(shelfID: $0, lutID: lut.lutID)
                    }
                    LUTPreviewCard(
                        lut: lut,
                        viewModel: viewModel,
                        renderingActive: renderingActive,
                        libraryKeyboardFocus: libraryKeyboardFocus,
                        libraryAccessibilityFocus: libraryAccessibilityFocus,
                        libraryFocusTarget: focusTarget,
                        librarySelected: focusTarget == selectedLibraryCardTarget,
                        onActivate: activation(for: lut, target: focusTarget),
                        onLibraryContentMutation: onLibraryContentMutation
                    )
                }
            }
            .padding(10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "folder" : "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "No LUTs in this folder" : "No matching LUTs")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if searchText.isEmpty == false {
                Button("Clear Search") { searchText = "" }
                    .buttonStyle(.borderless)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activation(
        for lut: CubeLUT,
        target: LUTLibraryFocusTarget?
    ) -> (() -> Void)? {
        guard let target, let onLibraryActivate else { return nil }
        return { onLibraryActivate(lut, target) }
    }
}

struct LUTPreviewCard: View {
    let lut: CubeLUT
    @ObservedObject var viewModel: AppViewModel
    var renderingActive = true
    var libraryKeyboardFocus: FocusState<LUTLibraryFocusTarget?>.Binding? = nil
    var libraryAccessibilityFocus: AccessibilityFocusState<LUTLibraryFocusTarget?>.Binding? = nil
    var libraryFocusTarget: LUTLibraryFocusTarget? = nil
    var librarySelected: Bool? = nil
    var onActivate: (() -> Void)? = nil
    var onLibraryContentMutation: ((LUTLibraryFocusTarget) -> Void)? = nil

    @State private var preview: NSImage?
    @State private var isHovering = false

    private var isSelected: Bool {
        if let librarySelected { return librarySelected }
        return viewModel.section == .lutLibrary
            ? viewModel.selectedLibraryLUTID == lut.lutID
            : viewModel.selectedLUT?.lutID == lut.lutID
    }
    private var isFavourite: Bool { viewModel.isStarred(lut) }

    /// Typed tags communicate the owner's intent, so they are shown before
    /// measured tags. Cards deliberately stop at three; the detail view keeps
    /// the complete set.
    private var visibleTags: [String] {
        LUTGalleryMetadata.visibleTags(
            typed: viewModel.typedTags(for: lut),
            measured: viewModel.visibleMeasuredTags(for: lut)
        )
    }

    private var renderIdentity: RenderIdentity {
        RenderIdentity(
            lutID: lut.lutID,
            revision: viewModel.lutGalleryRevision,
            sampleID: viewModel.section == .lutLibrary ? viewModel.selectedLibrarySampleID : nil,
            active: renderingActive
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1))

                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFill()
                } else if viewModel.sourceImage != nil || viewModel.section == .lutLibrary {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "cube.transparent")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .clipped()
            .overlay(alignment: .topTrailing) {
                Button {
                    toggleStarred()
                } label: {
                    Image(systemName: isFavourite ? "star.fill" : "star")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isFavourite ? Color.yellow : Color.white)
                        .padding(6)
                        .background(Color.black.opacity(0.42), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(7)
                .opacity(isFavourite || isHovering ? 1 : 0.72)
                .help(isFavourite ? "Unstar \(lut.name)" : "Star \(lut.name)")
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(viewModel.catalog.effectiveName(for: lut))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if lut.inputSpace == .vlog {
                        Text("V-LOG")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(cardProvenance)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if visibleTags.isEmpty == false {
                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(visibleTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(isHovering ? 0.18 : 0.07),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            activate()
        }
        .modifier(LUTLibraryCardFocusModifier(
            keyboardFocus: libraryKeyboardFocus,
            accessibilityFocus: libraryAccessibilityFocus,
            target: libraryFocusTarget
        ))
        .onKeyPress(.return) {
            guard libraryFocusTarget != nil else { return .ignored }
            activate()
            return .handled
        }
        .onKeyPress(.space) {
            guard libraryFocusTarget != nil else { return .ignored }
            activate()
            return .handled
        }
        .draggable(lut.lutID.raw) {
                Label(viewModel.catalog.effectiveName(for: lut), systemImage: "cube.fill")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        }
        .onHover { isHovering = $0 }
        .help(
            viewModel.section == .lutLibrary
                ? "Inspect \(lut.name)"
                : viewModel.comparisonLayout.isGrid
                ? "Click to assign to Cell \((viewModel.activeGridCellIndex ?? 0) + 1), or drag onto another cell"
                : "Apply \(lut.name)"
        )
        .contextMenu {
            Button(isFavourite ? "Unstar" : "Star") {
                toggleStarred()
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([lut.url])
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.catalog.effectiveName(for: lut)), \(cardProvenance)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            activate()
        }
        .task(id: renderIdentity) {
            preview = nil
            guard renderingActive else { return }
            guard viewModel.sourceImage != nil || viewModel.section == .lutLibrary else { return }
            preview = await viewModel.makeLUTGalleryPreview(
                for: lut,
                maxSize: CGSize(width: 640, height: 400)
            )
        }
    }

    private var cardProvenance: String {
        let brand = viewModel.catalog.origin(for: lut).label
        guard let source = viewModel.catalog.sourceLabel(for: lut),
              source.localizedCaseInsensitiveCompare(brand) != .orderedSame
        else { return brand }
        return "\(brand) · \(source)"
    }

    private struct RenderIdentity: Hashable {
        let lutID: LUTID
        let revision: Int
        let sampleID: String?
        let active: Bool
    }

    private func activate() {
        if let onActivate {
            onActivate()
        } else if viewModel.section == .lutLibrary {
            viewModel.selectLibraryLUT(lut)
        } else {
            viewModel.chooseLUTFromGallery(lut)
        }
    }

    private func toggleStarred() {
        viewModel.toggleStarred(lut)
        if let libraryFocusTarget {
            onLibraryContentMutation?(libraryFocusTarget)
        }
    }
}

private struct LUTLibraryCardFocusModifier: ViewModifier {
    let keyboardFocus: FocusState<LUTLibraryFocusTarget?>.Binding?
    let accessibilityFocus: AccessibilityFocusState<LUTLibraryFocusTarget?>.Binding?
    let target: LUTLibraryFocusTarget?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let keyboardFocus, let accessibilityFocus, let target {
            content
                .focusable()
                .focused(keyboardFocus, equals: target)
                .accessibilityFocused(accessibilityFocus, equals: target)
        } else {
            content
        }
    }
}
