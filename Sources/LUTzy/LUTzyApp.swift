import SwiftUI
import AppKit
import LUTzyKit

// The whole app lives in LUTzyKit; this target is only the entry point, so the
// code can be unit-tested (`@testable` cannot import an executable target).

private enum BuildIdentity {
    static var windowTitle: String {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let commit = info["LUTzyBuildCommit"] as? String,
              !commit.isEmpty else {
            return "LUTzy — unverified build"
        }

        let branch = (info["LUTzyBuildBranch"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "detached"
        let configuration = (info["LUTzyBuildConfiguration"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "unknown"
        let dirtySuffix = (info["LUTzyBuildDirty"] as? Bool) == true ? "+dirty" : ""
        return "LUTzy — \(branch) @ \(commit.prefix(8))\(dirtySuffix) · \(configuration)"
    }
}

/// Forces normal foreground-app activation. When LUTzy is launched as a bare
/// Swift Package executable (e.g. `swift run`, or running the SPM target from
/// Xcode), there is no app bundle / Info.plist, so macOS starts it as a
/// background process: no Dock icon, not in ⌘-Tab, and the window never comes
/// to the front. Setting `.regular` + activating makes the window appear
/// reliably. This is a no-op once LUTzy runs as a properly bundled `.app`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyBuildIdentityToWindow(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyBuildIdentityToWindow(_:)),
            name: NSWindow.didUpdateNotification,
            object: nil
        )
        for window in NSApp.windows {
            window.title = BuildIdentity.windowTitle
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func applyBuildIdentityToWindow(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.title != BuildIdentity.windowTitle else { return }
        window.title = BuildIdentity.windowTitle
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct LUTzyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(BuildIdentity.windowTitle) {
            ContentView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands { LUTzyCommands() }
    }
}
