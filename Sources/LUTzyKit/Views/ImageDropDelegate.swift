import SwiftUI
import AppKit

/// Routes a drop on the preview canvas to `AppViewModel.handleDrop`.
///
/// SwiftUI's `DropInfo` exposes item providers, and a Photos file promise cannot be redeemed through
/// one. The drag pasteboard is a process-wide object, though, so the delegate reads
/// `NSPasteboard(name: .drag)` directly — the same pasteboard AppKit would hand an `NSView` — and
/// lets `ImageDrop` classify it.
struct ImageDropDelegate: DropDelegate {
    let viewModel: AppViewModel
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        ImageDrop.canAccept(NSPasteboard(name: .drag))
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let payload = ImageDrop.payload(from: NSPasteboard(name: .drag)) else { return false }
        viewModel.handleDrop(payload)
        return true
    }
}
