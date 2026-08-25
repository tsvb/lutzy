import SwiftUI

/// The app's five durable jobs. Browsing, organisation and transform editing
/// are deliberately separate destinations.
enum AppSection: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case viewer
    case mediaLibrary
    case lutLibrary
    case manager
    case editor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .viewer: return "Viewer"
        case .mediaLibrary: return "Media Library"
        case .lutLibrary: return "LUT Library"
        case .manager: return "LUT Manager"
        case .editor: return "LUT Editor"
        }
    }

    var symbol: String {
        switch self {
        case .viewer: return "photo"
        case .mediaLibrary: return "photo.on.rectangle.angled"
        case .lutLibrary: return "square.grid.2x2"
        case .manager: return "square.stack.3d.up"
        case .editor: return "slider.horizontal.3"
        }
    }

    /// `images` was briefly a fourth top-level section. It now belongs inside
    /// Viewer, but older project sessions must continue to decode rather than
    /// making the whole project disappear from the store.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stored = try container.decode(String.self)
        if stored == "images" { self = .mediaLibrary }
        else { self = AppSection(rawValue: stored) ?? .viewer }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Primary navigation intentionally has one kind of selection: app mode.
/// Scope controls live beside the content they filter, so choosing a LUT
/// folder can no longer steal the LUT Manager highlight.
struct NavigationSidebar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        List(selection: selection) {
            Section("Workspace") {
                ForEach(AppSection.allCases) { section in
                    Label(section.label, systemImage: section.symbol)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 170, idealWidth: 190, maxWidth: 240)
    }

    private var selection: Binding<AppSection?> {
        Binding(
            get: { viewModel.section },
            set: { section in
                guard let section else { return }
                viewModel.section = section
            }
        )
    }
}
