import SwiftUI
import AppKit
import LUTzyKit

// The whole app lives in LUTzyKit; this target is only the entry point, so the
// code can be unit-tested (`@testable` cannot import an executable target).

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
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 800)
        .commands { LUTzyCommands() }

        Settings {
            ContentView.settings
        }
        .windowResizability(.contentSize)
    }
}
