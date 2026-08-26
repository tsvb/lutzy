import AppKit
import PhotosUI
import SwiftUI

/// Main window layout: sidebar + preview + toolbar.
///
/// One of two entry points LUTzyKit exposes to the executable (the other is
/// `LUTzyCommands`); everything else in the module stays internal.
public struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var photosSelection: [PhotosPickerItem] = []

    public init() {}

    public var body: some View {
        mainContent
            .navigationTitle("")
            .toolbar {
                if viewModel.section == .viewer {
                    ToolbarItemGroup(placement: .primaryAction) {
                        toolbarContent
                    }
                }
            }
            .photosPicker(
                isPresented: $viewModel.isPhotosPickerPresented,
                selection: $photosSelection,
                maxSelectionCount: 50,
                matching: .images
            )
            .onChange(of: photosSelection) { _, newSelection in
                handlePhotosSelection(newSelection)
            }
            .sheet(
                isPresented: Binding(
                    get: { viewModel.derive.isSheetPresented },
                    set: { viewModel.derive.isSheetPresented = $0 }
                )
            ) {
                RecipeExtractorSheet(coordinator: viewModel.derive)
            }
            .sheet(item: $viewModel.lutImportReview) { review in
                LUTImportReviewView(
                    review: review,
                    onInspect: viewModel.inspectLUTFromImportReview,
                    onDismiss: { viewModel.lutImportReview = nil }
                )
            }
            .modifier(KeyboardShortcuts(viewModel: viewModel))
            .modifier(MenuCommandReceivers(viewModel: viewModel))
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                ),
                presenting: viewModel.errorMessage
            ) { _ in
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { message in
                Text(message)
            }
    }

    private func handlePhotosSelection(_ selection: [PhotosPickerItem]) {
        guard !selection.isEmpty else { return }
        Task {
            var dataItems: [(name: String, data: Data)] = []
            for (i, item) in selection.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    dataItems.append((name: "Photo \(i + 1)", data: data))
                }
            }
            photosSelection = []
            if !dataItems.isEmpty {
                viewModel.importPhotosData(dataItems)
            }
        }
    }

    private var mainContent: some View {
        // Three columns: Workspace, local source navigation, and the active job.
        NavigationSplitView {
            NavigationSidebar(viewModel: viewModel)
        } content: {
            libraryColumn
        } detail: {
            sectionContent
        }
        .inspector(isPresented: $viewModel.isInspectorPresented) {
            InfoInspectorView(viewModel: viewModel)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
    }

    /// Viewer navigates LUTs by folder and auditions the files as pictures.
    /// Manager and Editor retain the denser LUT list needed for metadata and
    /// direct file-oriented work.
    @ViewBuilder
    private var libraryColumn: some View {
        switch viewModel.section {
        case .viewer:
            ViewerWorkspaceSidebar(viewModel: viewModel)
        case .mediaLibrary:
            MediaLibrarySidebar(viewModel: viewModel)
        case .lutLibrary:
            LUTSourceSidebar(viewModel: viewModel, context: .library)
        case .manager:
            LUTSourceSidebar(viewModel: viewModel, context: .manager)
        case .editor:
            LUTSidebar(viewModel: viewModel)
        }
    }

    /// What the detail column shows, by section.
    @ViewBuilder
    private var sectionContent: some View {
        switch viewModel.section {
        case .viewer:
            viewerContent
        case .mediaLibrary:
            MediaLibraryView(viewModel: viewModel)
        case .lutLibrary:
            LUTLibraryView(viewModel: viewModel)
        case .manager:
            LibraryManagerView(viewModel: viewModel)
        case .editor:
            EditorView(viewModel: viewModel)
        }
    }

    private var viewerContent: some View {
        VStack(spacing: 0) {
            VSplitView {
                VStack(spacing: 0) {
                    PreviewView(viewModel: viewModel)

                    if viewModel.collection.isActive {
                        Divider()
                        FilmstripView(collection: viewModel.collection) { index in
                            viewModel.selectCollectionImage(at: index)
                        }
                        .frame(height: 86)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(minHeight: 260, idealHeight: 440)

                LUTPreviewGalleryView(viewModel: viewModel)
                    .frame(minHeight: 210, idealHeight: 320)
            }

            StatusBar(viewModel: viewModel)
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.collection.isActive)
    }

    @ViewBuilder
    private var toolbarContent: some View {
        Group {
            // How the preview is divided. A menu rather than a toggle: there are
            // seven layouts now, and V still cycles the two that get used most.
            Menu {
                ForEach(ComparisonLayout.allCases, id: \.self) { layout in
                    Button {
                        viewModel.setLayout(layout)
                    } label: {
                        Label(layout.label, systemImage: layout.symbol)
                    }
                }
            } label: {
                Label(
                    viewModel.comparisonLayout.label, systemImage: viewModel.comparisonLayout.symbol
                )
            }
            .help(
                "Compare against the original, against another LUT, or several LUTs at once (V toggles the last two)"
            )

            // Info inspector (histogram + EXIF)
            Button {
                viewModel.toggleInspector()
            } label: {
                Label("Info", systemImage: "sidebar.right")
            }
            .help("Show histogram & EXIF (⌘I)")
            .keyboardShortcut("i", modifiers: .command)
            .disabled(viewModel.sourceImage == nil)

            Divider()

            // LUT intensity
            HStack(spacing: 6) {
                Text("Intensity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { viewModel.lutIntensity },
                        set: { viewModel.setLUTIntensity($0) }
                    ),
                    in: 0...1
                )
                .frame(width: 100)
                Text("\(Int((viewModel.lutIntensity * 100).rounded()))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .help("LUT intensity (0–100%)")
            .disabled(viewModel.selectedLUT == nil)

            // Only a V-Log LUT reads this, so it appears only when one is picked:
            // a control that cannot change the picture should not be on screen.
            if viewModel.isSourceSpaceRelevant {
                Picker(
                    "Source",
                    selection: Binding(
                        get: { viewModel.sourceSpace },
                        set: { viewModel.setSourceSpace($0) }
                    )
                ) {
                    ForEach(SourceSpace.allCases, id: \.self) { space in
                        Text(space.label).tag(space)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .help(
                    """
                    This LUT expects V-Log. Auto reads the file first and measures \
                    the image only if the file does not say; override either.

                    V-Log is exact — the file already holds the code values the LUT \
                    wants. Ordinary undoes the rendering first, which is exact \
                    maths against a generic neutral curve — but that curve is not \
                    the Photo Style that made your file.
                    """)

                if viewModel.conversionCaveat != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help(viewModel.conversionCaveat ?? "")
                }

                if let evidence = viewModel.sourceSpaceEvidence {
                    Text(evidence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(evidence)
                }
            }

            Divider()

            // Export. The file format lives here rather than in its own permanent
            // segmented control: it is a property of the export, it is decided once
            // and rarely revisited, and as a toolbar fixture it took the width of
            // three real controls to say something nobody was looking at.
            Menu {
                Button("Export…") { viewModel.exportDialog() }
                Divider()
                Picker("Format", selection: $viewModel.exportFormat) {
                    ForEach(ExportFormat.allCases) { fmt in
                        Text(fmt.rawValue).tag(fmt)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            } primaryAction: {
                viewModel.exportDialog()
            }
            // ⌘S is bound once, on the File ▸ Export menu item (LUTzyApp.swift).
            // Binding it here too gave the window two competing handlers.
            .help("Export the graded image as \(viewModel.exportFormat.rawValue) (⌘S)")
            .disabled(viewModel.sourceImage == nil)

            // Batch export — only when a multi-image set is loaded
            if viewModel.collection.isActive {
                Button {
                    viewModel.batchExportDialog()
                } label: {
                    Label("Export All", systemImage: "square.and.arrow.up.on.square")
                }
                .help("Apply the current LUT to all imported images and export to a folder (⌘⇧E)")
                .disabled(viewModel.isExporting)
            }
        }
    }
}

// The File menu, its notification names, and `MenuCommandReceivers` live in
// MenuCommands.swift.
