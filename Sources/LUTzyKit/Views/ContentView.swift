import SwiftUI
import PhotosUI
import AppKit

/// Main window layout: sidebar + preview + toolbar.
///
/// One of two entry points LUTzyKit exposes to the executable (the other is
/// `LUTzyCommands`); everything else in the module stays internal.
public struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @State private var photosSelection: [PhotosPickerItem] = []

    /// The canvas is the window's resting focus. `.onKeyPress` (in `mainContent`) only fires while
    /// something in the split view has focus, and a preview canvas has nothing focusable of its
    /// own, so it is made focusable and takes focus at launch, on click, and when a sheet closes.
    @FocusState private var isCanvasFocused: Bool
    /// True while the sidebar's search field is being typed into; the key table stays out then.
    @FocusState private var isSearchFocused: Bool

    public init() {}

    public var body: some View {
        mainContent
            .navigationTitle(viewModel.sourceName.isEmpty ? "LUTzy" : viewModel.sourceName)
            .navigationSubtitle(viewModel.selectedLUT?.name ?? "")
            .toolbarTitleDisplayMode(.inline)
            .toolbar(id: "main") {
                toolbarContent
            }
            .photosPicker(
                isPresented: Bindable(viewModel).isPhotosPickerPresented,
                selection: $photosSelection,
                maxSelectionCount: 50,
                matching: .images
            )
            .onChange(of: photosSelection) { _, newSelection in
                handlePhotosSelection(newSelection)
            }
            .sheet(isPresented: Bindable(viewModel.derive).isSheetPresented) {
                RecipeExtractorSheet(coordinator: viewModel.derive)
            }
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
        NavigationSplitView {
            LUTSidebar(viewModel: viewModel, searchFocus: $isSearchFocused)
        } detail: {
            detailContent
                .focusable()
                .focusEffectDisabled()
                .focused($isCanvasFocused)
                .onTapGesture { isCanvasFocused = true }
        }
        .inspector(isPresented: Bindable(viewModel).isInspectorPresented) {
            InfoInspectorView(viewModel: viewModel)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .defaultFocus($isCanvasFocused, true)
        .task { isCanvasFocused = true }
        .onChange(of: viewModel.derive.isSheetPresented) { _, presented in
            if !presented { isCanvasFocused = true }
        }
        .onKeyPress(keys: KeyCommandMap.keys, phases: KeyCommandMap.phases) { press in
            guard !isSearchFocused,
                  !KeyCommandMap.textInputHasFocus(),
                  let action = KeyCommandMap.action(
                    for: press.key,
                    modifiers: press.modifiers,
                    phase: press.phase,
                    collectionActive: viewModel.collection.isActive
                  )
            else { return .ignored }
            viewModel.perform(action)
            return .handled
        }
    }

    private var detailContent: some View {
        // A real split so the browser is user-resizable, instead of a fixed 240pt `HStack`.
        HSplitView {
            if viewModel.isSourceBrowserPresented && !viewModel.collection.items.isEmpty {
                SourceBrowserView(viewModel: viewModel)
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 360)
            }

            VStack(spacing: 0) {
                PreviewView(viewModel: viewModel)

                if viewModel.collection.isActive {
                    Divider()
                    FilmstripView(collection: viewModel.collection) { index in
                        viewModel.selectCollectionImage(at: index)
                    }
                    .frame(height: 84)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                StatusBar(viewModel: viewModel)
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.collection.isActive)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSourceBrowserPresented)
    }

    /// A customizable toolbar (View ▸ Customize Toolbar…): every control has a stable id, and
    /// `ToolbarSpacer`s group them the way the old `Divider`s did, in the system's own idiom.
    /// Split in two because a toolbar builder takes ten items at most.
    @ToolbarContentBuilder
    private var toolbarContent: some CustomizableToolbarContent {
        viewControls
        fileControls
    }

    /// Format, comparison, and the two side panels.
    @ToolbarContentBuilder
    private var viewControls: some CustomizableToolbarContent {
        // Format picker
        ToolbarItem(id: "format", placement: .primaryAction) {
            Picker("Format", selection: Bindable(viewModel).exportFormat) {
                ForEach(ExportFormat.allCases) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .help("Export format")
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        // The three panel controls are toggles, not buttons: the icon stays put and the on state
        // shows as a highlight. A compare button whose icon flipped to "rectangle" read, next to
        // the two sidebar icons, as one option of a three-way layout picker.

        // Side-by-side toggle
        ToolbarItem(id: "compare", placement: .primaryAction) {
            Toggle(isOn: Bindable(viewModel).isSideBySide) {
                Label("Side by Side", systemImage: "rectangle.split.2x1")
            }
            .toggleStyle(.button)
            .help("Toggle side-by-side comparison (V)")
        }

        // Source folder browser
        ToolbarItem(id: "source", placement: .primaryAction) {
            Toggle(isOn: Bindable(viewModel).isSourceBrowserPresented) {
                Label("Source", systemImage: "sidebar.leading")
            }
            .toggleStyle(.button)
            .help("Show the source folder file browser")
            .disabled(viewModel.collection.items.isEmpty)
        }
    }

    /// Import, folders and export.
    @ToolbarContentBuilder
    private var fileControls: some CustomizableToolbarContent {
        ToolbarSpacer(.fixed, placement: .primaryAction)

        // Import menu
        ToolbarItem(id: "import", placement: .primaryAction) {
            Menu {
                Button("Open Image...") {
                    viewModel.openImageDialog()
                }
                Divider()
                Button("Import from Photos...") {
                    viewModel.importFromPhotos()
                }
                Button("Open Source Folder...") {
                    viewModel.chooseSourceFolder()
                }
                if !viewModel.collection.items.isEmpty {
                    Button("Refresh Source Folder") {
                        viewModel.refreshSource()
                    }
                }
            } label: {
                Label("Import", systemImage: "photo.on.rectangle")
            }
            .help("Open an image, a source folder, or import from Photos")
        }

        // Export. With a multi-image set loaded it becomes a split button: click exports this image,
        // the chevron offers Export All. Two adjacent buttons with near-identical share glyphs
        // (`square.and.arrow.up` and `…on.square`) were indistinguishable at toolbar size.
        // ⌘S is bound once, on the File ▸ Export menu item (LUTzyApp.swift), and ⌘⇧E on File ▸
        // Export All; binding either here too gave the window two competing handlers.
        ToolbarItem(id: "export", placement: .primaryAction) {
            if viewModel.collection.isActive {
                Menu {
                    exportAllButton
                } label: {
                    exportLabel
                } primaryAction: {
                    viewModel.exportDialog()
                }
                .help("Export the graded image (⌘S); the arrow offers Export All (⌘⇧E)")
                .disabled(viewModel.sourceImage == nil)
            } else {
                Button {
                    viewModel.exportDialog()
                } label: {
                    exportLabel
                }
                .help("Export the graded image (⌘S)")
                .disabled(viewModel.sourceImage == nil)
            }
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        // The inspector: Info (histogram + EXIF), Develop, Adjust.
        ToolbarItem(id: "inspector", placement: .primaryAction) {
            Toggle(isOn: Bindable(viewModel).isInspectorPresented) {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .toggleStyle(.button)
            .help("Show the inspector — info, develop and adjustments (⌘I)")
            .keyboardShortcut("i", modifiers: .command)
            .disabled(viewModel.sourceImage == nil)
        }
    }

    private var exportLabel: some View {
        Label("Export", systemImage: "square.and.arrow.up")
    }

    private var exportAllButton: some View {
        Button {
            viewModel.batchExportDialog()
        } label: {
            Label("Export All...", systemImage: "square.and.arrow.up.on.square")
        }
        // Not "the current LUT": `performBatchExport` hands every image the whole `EditDocument` —
        // RAW develop and adjustments included. Saying LUT understated it in the direction that
        // surprises people, because `rawDevelop` was seeded from one RAW's as-shot values.
        .help("Apply the current look — LUT, develop and adjustments — to all imported images "
              + "and export to a folder (⌘⇧E)")
        .disabled(viewModel.isExporting)
    }
}

// The File menu, its notification names, and `MenuCommandReceivers` live in
// MenuCommands.swift.
