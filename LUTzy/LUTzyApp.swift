import SwiftUI
import AppKit

/// Forces normal foreground-app activation. When LUTzy is launched as a bare
/// Swift Package executable (e.g. `swift run`, or running the SPM target from
/// Xcode), there is no app bundle / Info.plist, so macOS starts it as a
/// background process: no Dock icon, not in ⌘-Tab, and the window never comes
/// to the front. Setting `.regular` + activating makes the window appear
/// reliably. This is a no-op once LUTzy runs as a properly bundled `.app`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct LUTzyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Replace default file menu items
            CommandGroup(replacing: .newItem) {
                Button("Open Image...") {
                    NotificationCenter.default.post(name: .openImage, object: nil)
                }
                .keyboardShortcut("o")

                Button("Choose LUT Folder...") {
                    NotificationCenter.default.post(name: .chooseLUTFolder, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("Import from Photos...") {
                    NotificationCenter.default.post(name: .importFromPhotos, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Import Folder...") {
                    NotificationCenter.default.post(name: .importFolder, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Divider()

                Button("Derive LUT from JPG…") {
                    NotificationCenter.default.post(name: .deriveRecipe, object: nil)
                }
                .keyboardShortcut("d")

                Divider()

                Button("Export...") {
                    NotificationCenter.default.post(name: .exportImage, object: nil)
                }
                .keyboardShortcut("s")

                Button("Export All...") {
                    NotificationCenter.default.post(name: .exportAll, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}
