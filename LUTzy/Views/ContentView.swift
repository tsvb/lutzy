import SwiftUI
import PhotosUI

/// Main window layout: sidebar + preview + toolbar.
struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var photosSelection: [PhotosPickerItem] = []

    var body: some View {
        mainContent
            .navigationTitle("")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    toolbarContent
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
            .sheet(isPresented: $viewModel.isRecipeSheetPresented) {
                RecipeExtractorSheet(vm: viewModel)
            }
            .modifier(KeyboardShortcuts(viewModel: viewModel))
            .modifier(MenuCommandReceivers(viewModel: viewModel))
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
            LUTSidebar(viewModel: viewModel)
        } detail: {
            detailContent
        }
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            PreviewView(viewModel: viewModel)

            if viewModel.collection.isActive {
                Divider()
                FilmstripView(collection: viewModel.collection) { index in
                    viewModel.selectCollectionImage(at: index)
                }
                .frame(height: 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            StatusBar(viewModel: viewModel)
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.collection.isActive)
    }

    @ViewBuilder
    private var toolbarContent: some View {
        // Format picker
        Picker("Format", selection: $viewModel.exportFormat) {
            ForEach(ImageProcessor.ExportFormat.allCases) { fmt in
                Text(fmt.rawValue).tag(fmt)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)

        Divider()

        // Side-by-side toggle
        Button {
            viewModel.toggleSideBySide()
        } label: {
            Label(
                viewModel.isSideBySide ? "Single View" : "Side by Side",
                systemImage: viewModel.isSideBySide ? "rectangle" : "rectangle.split.2x1"
            )
        }
        .help("Toggle side-by-side comparison (V)")

        Divider()

        // Import menu
        Menu {
            Button("Open Image...") {
                viewModel.openImageDialog()
            }
            Divider()
            Button("Import from Photos...") {
                viewModel.importFromPhotos()
            }
            Button("Import Folder...") {
                viewModel.importFolder()
            }
        } label: {
            Label("Import", systemImage: "photo.on.rectangle")
        }

        // LUT folder
        Button {
            viewModel.chooseLUTFolder()
        } label: {
            Label("LUT Folder", systemImage: "folder")
        }

        // Export
        Button {
            viewModel.exportDialog()
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .keyboardShortcut("s")
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

// MARK: - Status Bar

struct StatusBar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 0) {
            // Status message
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            // Hints
            HStack(spacing: 12) {
                KeyHint(key: "←→", label: "cycle LUTs")
                if viewModel.collection.isActive {
                    KeyHint(key: "[ ]", label: "cycle images")
                }
                KeyHint(key: "V", label: viewModel.isSideBySide ? "single view" : "side-by-side")
                KeyHint(key: "Space", label: "compare")
                KeyHint(key: "⌘S", label: "export")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            Text(label)
                .font(.caption2)
                .foregroundColor(Color(nsColor: .quaternaryLabelColor))
        }
    }
}

// MARK: - Keyboard shortcuts
//
// SwiftUI's `.onKeyPress` modifier only fires when the modified view (or a
// descendant) has focus. Inside a NavigationSplitView the sidebar list eats
// focus when clicked and the detail pane has nothing focusable by default, so
// `.onKeyPress` was effectively never firing. We use an NSEvent local monitor
// instead, which catches every key event at the window level regardless of
// which subview has focus. Menu shortcuts (⌘-anything) still go through the
// standard menu system — we explicitly let those events pass through.

struct KeyboardShortcuts: ViewModifier {
    @ObservedObject var viewModel: AppViewModel
    @State private var monitor: KeyMonitor?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if monitor == nil {
                    monitor = KeyMonitor(viewModel: viewModel)
                }
            }
            .onDisappear {
                monitor = nil
            }
    }
}

/// Owns an NSEvent local monitor for the lifetime of the main content view.
/// Class so we can clean up the monitor in `deinit`.
@MainActor
final class KeyMonitor {
    private var token: Any?
    private weak var viewModel: AppViewModel?

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self.token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            return self?.handle(event) ?? event
        }
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let vm = viewModel else { return event }

        // If a sheet is up, let the sheet's text fields and buttons handle keys.
        if vm.isRecipeSheetPresented { return event }

        // Don't consume Command-modified events — those belong to the menu bar.
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) { return event }

        let isDown = event.type == .keyDown

        // Hardware key codes (US layout independent for arrows/space)
        switch event.keyCode {
        case 49:  // Space — hold to compare original
            vm.showOriginal(isDown)
            return nil
        case 123: // Left arrow — previous LUT
            if isDown { vm.selectPreviousLUT() }
            return nil
        case 124: // Right arrow — next LUT
            if isDown { vm.selectNextLUT() }
            return nil
        default:
            break
        }

        // Character keys (key-down only)
        guard isDown, let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return event
        }
        switch chars {
        case "v":
            vm.toggleSideBySide()
            return nil
        case "[":
            guard vm.collection.isActive else { return event }
            vm.selectPreviousImage()
            return nil
        case "]":
            guard vm.collection.isActive else { return event }
            vm.selectNextImage()
            return nil
        default:
            return event
        }
    }
}

// MARK: - Menu command receivers

struct MenuCommandReceivers: ViewModifier {
    @ObservedObject var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openImage)) { _ in
                viewModel.openImageDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportImage)) { _ in
                viewModel.exportDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportAll)) { _ in
                viewModel.batchExportDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .chooseLUTFolder)) { _ in
                viewModel.chooseLUTFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importFromPhotos)) { _ in
                viewModel.importFromPhotos()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importFolder)) { _ in
                viewModel.importFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deriveRecipe)) { _ in
                viewModel.presentRecipeExtractor()
            }
    }
}

// MARK: - Notification names for menu commands

extension Notification.Name {
    static let openImage = Notification.Name("LUTzy.openImage")
    static let exportImage = Notification.Name("LUTzy.exportImage")
    static let exportAll = Notification.Name("LUTzy.exportAll")
    static let chooseLUTFolder = Notification.Name("LUTzy.chooseLUTFolder")
    static let importFromPhotos = Notification.Name("LUTzy.importFromPhotos")
    static let importFolder = Notification.Name("LUTzy.importFolder")
    static let deriveRecipe = Notification.Name("LUTzy.deriveRecipe")
}
