import SwiftUI

// The File menu and the notifications it posts. These live in LUTzyKit rather
// than beside `@main` so the executable target stays a thin entry point (and so
// the menu can be exercised from tests).

// MARK: - Commands

/// LUTzy's File menu, replacing SwiftUI's default "New" group.
///
/// One of two entry points LUTzyKit exposes to the executable (the other is
/// `ContentView`). Each item posts a notification that `MenuCommandReceivers`
/// picks up on the view side — the menu bar is outside the view hierarchy, so
/// it can't reach the view model directly.
public struct LUTzyCommands: Commands {

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Image...") { post(.openImage) }
                .keyboardShortcut("o")

            Button("Import Images…") { post(.importImages) }
                .keyboardShortcut("i", modifiers: [.command, .shift, .option])

            Button("Import LUTs…") { post(.importLUTs) }
                .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Use a LUT Folder…") { post(.chooseLUTFolder) }
                .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            Button("Import from Photos...") { post(.importFromPhotos) }
                .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Open Source Folder...") { post(.openSourceFolder) }
                .keyboardShortcut("i", modifiers: [.command, .option])

            Button("Refresh Source Folder") { post(.refreshSourceFolder) }
                .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Button("Derive LUT from JPG…") { post(.deriveRecipe) }
                .keyboardShortcut("d")

            Divider()

            Button("Export...") { post(.exportImage) }
                .keyboardShortcut("s")

            Button("Export All...") { post(.exportAll) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

// MARK: - Receivers

/// Bridges the menu's notifications back to the view model.
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
            .onReceive(NotificationCenter.default.publisher(for: .importLUTs)) { _ in
                viewModel.importLUTs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importImages)) { _ in
                viewModel.importImages()
            }
            .onReceive(NotificationCenter.default.publisher(for: .chooseLUTFolder)) { _ in
                viewModel.chooseLUTFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importFromPhotos)) { _ in
                viewModel.importFromPhotos()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSourceFolder)) { _ in
                viewModel.chooseSourceFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .refreshSourceFolder)) { _ in
                viewModel.refreshSource()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deriveRecipe)) { _ in
                viewModel.presentRecipeExtractor()
            }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openImage = Notification.Name("LUTzy.openImage")
    static let exportImage = Notification.Name("LUTzy.exportImage")
    static let exportAll = Notification.Name("LUTzy.exportAll")
    static let chooseLUTFolder = Notification.Name("LUTzy.chooseLUTFolder")
    static let importLUTs = Notification.Name("LUTzy.importLUTs")
    static let importImages = Notification.Name("LUTzy.importImages")
    static let importFromPhotos = Notification.Name("LUTzy.importFromPhotos")
    static let openSourceFolder = Notification.Name("LUTzy.openSourceFolder")
    static let refreshSourceFolder = Notification.Name("LUTzy.refreshSourceFolder")
    static let deriveRecipe = Notification.Name("LUTzy.deriveRecipe")
}
