import SwiftUI

// The bar along the bottom of the window: current status on the left, a
// reminder of the keys that do something on the right.

struct StatusBar: View {
    let viewModel: AppViewModel
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        HStack(spacing: 0) {
            // Status message
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            // Hints, on one glass capsule rather than one per key — five capsules read as buttons.
            HStack(spacing: 12) {
                KeyHint(key: "↑↓", label: "cycle LUTs")
                if viewModel.collection.isActive {
                    KeyHint(key: "←→", label: "cycle images")
                }
                KeyHint(key: "V", label: viewModel.isSideBySide ? "single view" : "side-by-side")
                KeyHint(key: "Space", label: "compare")
                KeyHint(key: "⌘S", label: "export")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: .capsule)
            .opacity(appearsActive ? 1 : 0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            // One step up the label hierarchy from tertiary/quaternary, which on the glass capsule
            // in dark mode was close to invisible.
            Text(key)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
