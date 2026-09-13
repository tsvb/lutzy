import SwiftUI

// The bar along the bottom of the window: current status, centered.

struct StatusBar: View {
    let viewModel: AppViewModel
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Text(viewModel.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .opacity(appearsActive ? 1 : 0.6)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(.bar)
    }
}
