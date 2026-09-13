import SwiftUI
import AppKit

//
// Plain-key shortcuts for the main window — Space, the arrows, V and the brackets.
//
// These arrive through SwiftUI's `.onKeyPress`, attached to the `NavigationSplitView` in
// `ContentView`. That modifier fires for the focused view *and every ancestor of it*, so a handler on
// the split view sees a key whichever pane holds focus: the sidebar list, the canvas, or the
// inspector. The one thing it needs is that *something* has focus, which is what the
// `.focusable()` canvas, `.defaultFocus` and the click-to-focus in `ContentView` guarantee. (An
// earlier version used an `NSEvent` local monitor because nothing in the detail pane was focusable
// and `.onKeyPress` never fired; making the canvas focusable is the fix, not a workaround.)
//
// ⌘-anything is left alone so it reaches the menu bar, and nothing fires while a text field, text
// view or slider has focus — the sidebar search field (tracked via `isSearchFocused`, a SwiftUI
// `@FocusState` that never sees the field editor AppKit actually installs) plus any TextField or
// Slider the inspector adds, checked with `KeyCommandMap.textInputHasFocus()`. The mapping itself is
// a pure table, `KeyCommandMap`, so it can be tested without a window.
//

/// What a plain key does. A value rather than a call so the mapping can be asserted.
enum KeyAction: Equatable, Sendable {
    /// Space: `true` on the way down, `false` on release.
    case compareOriginal(Bool)
    case previousLUT
    case nextLUT
    case previousImage
    case nextImage
    case toggleSideBySide
}

/// The table behind the main window's plain-key shortcuts.
enum KeyCommandMap {
    /// The keys `ContentView` subscribes to. Both cases of `v` because a held Shift changes the key.
    static var keys: Set<KeyEquivalent> {
        [.upArrow, .downArrow, .leftArrow, .rightArrow, .space, "v", "V", "[", "]"]
    }

    /// Down and up for Space; repeat so a held arrow keeps stepping, as it did under AppKit.
    static var phases: KeyPress.Phases { [.down, .repeat, .up] }

    /// True when the key window's first responder is a text-editing view or a slider.
    ///
    /// SwiftUI's `TextField`/`SecureField` install AppKit's shared field editor — an `NSTextView` —
    /// as first responder while being edited, not the `NSTextField` itself; `NSTextField` is checked
    /// too so a raw AppKit text field (or a `TextEditor`'s underlying view) is also caught. A
    /// `Slider` is included so arrow keys reach it — a slider takes focus but is not text input, and
    /// stepping it with the arrow keys must not also step the LUT/image selection underneath. This
    /// is a supplement to `isSearchFocused` in `ContentView`, not a replacement: the search field
    /// uses a SwiftUI `@FocusState`, which flips on before AppKit installs the field editor this
    /// checks, so relying on this alone would miss the first keystroke.
    @MainActor
    static func textInputHasFocus() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField || responder is NSSlider
    }

    /// - Returns: what `key` should do, or `nil` to let the press through untouched.
    static func action(
        for key: KeyEquivalent,
        modifiers: EventModifiers,
        phase: KeyPress.Phases,
        collectionActive: Bool
    ) -> KeyAction? {
        // ⌘ belongs to the menu bar.
        if modifiers.contains(.command) { return nil }

        let character = key.character

        // Space is the only key with an "up" meaning, and it does not repeat: the original is
        // already showing.
        if character == KeyEquivalent.space.character {
            switch phase {
            case .down: return .compareOriginal(true)
            case .up: return .compareOriginal(false)
            default: return nil
            }
        }

        switch phase {
        case .down:
            break
        case .repeat:
            // Stepping repeats; a toggle does not.
            if character == "v" || character == "V" { return nil }
        default:
            return nil
        }

        switch character {
        case KeyEquivalent.upArrow.character: return .previousLUT
        case KeyEquivalent.downArrow.character: return .nextLUT
        case KeyEquivalent.leftArrow.character, "[": return collectionActive ? .previousImage : nil
        case KeyEquivalent.rightArrow.character, "]": return collectionActive ? .nextImage : nil
        case "v", "V": return .toggleSideBySide
        default: return nil
        }
    }
}

extension AppViewModel {
    /// Dispatch for `KeyCommandMap`.
    func perform(_ action: KeyAction) {
        switch action {
        case .compareOriginal(let show): showOriginal(show)
        case .previousLUT: selectPreviousLUT()
        case .nextLUT: selectNextLUT()
        case .previousImage: selectPreviousImage()
        case .nextImage: selectNextImage()
        case .toggleSideBySide: toggleSideBySide()
        }
    }
}
