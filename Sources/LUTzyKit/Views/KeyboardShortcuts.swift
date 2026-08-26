import SwiftUI
import AppKit

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
                monitor?.stop()
                monitor = nil
            }
    }
}

/// Owns an NSEvent local monitor for the lifetime of the main content view.
@MainActor
final class KeyMonitor {
    private var token: Any?
    private weak var viewModel: AppViewModel?
    private let removeMonitor: (Any) -> Void

    /// True while a monitor is installed. Internal so the lifecycle that replaced `deinit` can be
    /// asserted at all.
    var isMonitoring: Bool { token != nil }

    /// - Parameter removeMonitor: how to tear the monitor down. Injectable **only** because there is
    ///   no way to observe from outside AppKit whether `NSEvent.removeMonitor` was actually called —
    ///   `isMonitoring` alone would pass against a `stop()` that dropped the token and leaked the
    ///   monitor, which is precisely the failure this step's teardown change could introduce. A
    ///   mutation demonstrated that gap. Same seam as `RenderEngine.init(context:)`.
    init(
        viewModel: AppViewModel,
        removeMonitor: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) }
    ) {
        self.viewModel = viewModel
        self.removeMonitor = removeMonitor
        self.token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            return self?.handle(event) ?? event
        }
    }

    /// Remove the monitor.
    ///
    /// **Explicit rather than in `deinit`, because Step 8 turned Swift 6 language mode on.** A
    /// `deinit` is `nonisolated` — it can run on any thread, so the compiler refuses to let it touch
    /// `token`, which is the `Any?` AppKit hands back and is not `Sendable`. The escape hatches are
    /// `nonisolated(unsafe)` or an `@unchecked Sendable` box, and this module does not use either.
    ///
    /// Losing the `deinit` safety net costs nothing real and fixes something: `NSEvent.removeMonitor`
    /// is an AppKit call that wants the main thread, and reaching it from a `deinit` that could run
    /// anywhere was already the wrong shape. `KeyboardShortcuts.onDisappear` owns the lifetime now,
    /// on the actor that owns the window. Idempotent, so calling it twice is harmless.
    func stop() {
        if let token { removeMonitor(token) }
        token = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let vm = viewModel else { return event }

        // If a sheet is up, let the sheet's text fields and buttons handle keys.
        if vm.derive.isSheetPresented { return event }

        // Don't hijack keys while editing text (the search field, etc.) — a
        // focused SwiftUI TextField makes the window's field editor (an NSText)
        // the first responder.
        if NSApp.keyWindow?.firstResponder is NSText { return event }

        // Don't consume Command-modified events — those belong to the menu bar.
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) { return event }

        let isDown = event.type == .keyDown

        // Hardware key codes (US layout independent for arrows/space).
        // ↑/↓ cycle LUTs; ←/→ step through the source files.
        switch event.keyCode {
        case 49:  // Space — hold to compare original
            guard vm.section == .viewer
                    || (vm.section == .lutLibrary && vm.isLUTDetailFocused && vm.selectedLibraryLUT != nil)
            else { return event }
            vm.showOriginal(isDown)
            return nil
        case 126: // Up arrow — previous LUT
            guard vm.section == .viewer else { return event }
            if isDown { vm.selectPreviousLUT() }
            return nil
        case 125: // Down arrow — next LUT
            guard vm.section == .viewer else { return event }
            if isDown { vm.selectNextLUT() }
            return nil
        case 123: // Left arrow — previous image
            guard vm.section == .viewer, vm.collection.isActive else { return event }
            if vm.isViewerWipeFocused { return event }
            if isDown { vm.selectPreviousImage() }
            return nil
        case 124: // Right arrow — next image
            guard vm.section == .viewer, vm.collection.isActive else { return event }
            if vm.isViewerWipeFocused { return event }
            if isDown { vm.selectNextImage() }
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
            guard vm.section == .viewer else { return event }
            vm.toggleSideBySide()
            return nil
        case "[":
            guard vm.section == .viewer, vm.collection.isActive else { return event }
            vm.selectPreviousImage()
            return nil
        case "]":
            guard vm.section == .viewer, vm.collection.isActive else { return event }
            vm.selectNextImage()
            return nil
        default:
            return event
        }
    }
}
