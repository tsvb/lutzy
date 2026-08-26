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
/// It stays compact as an icon rail; destination names remain available from
/// hover labels and accessibility labels. Scope controls live beside the
/// content they filter, so choosing a LUT folder can no longer steal the LUT
/// Manager highlight.
struct NavigationSidebar: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var hoveredSection: AppSection?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(AppSection.allCases) { section in
                let isSelected = viewModel.section == section
                let isHovered = hoveredSection == section

                Button {
                    viewModel.section = section
                } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 23, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            isSelected
                                ? Color.white
                                : Color.primary.opacity(isHovered ? 0.95 : 0.70)
                        )
                        .frame(width: 48, height: 48)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    isSelected
                                        ? Color.accentColor
                                        : Color.primary.opacity(isHovered ? 0.10 : 0)
                                )
                        }
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .popover(
                    isPresented: hoverPresentation(for: section),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .leading
                ) {
                    Text(section.label)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .fixedSize()
                }
                .accessibilityLabel(Text(section.label))
                .accessibilityValue(Text(isSelected ? "Selected" : ""))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .onHover { hovering in
                    hoveredSection = hovering ? section : nil
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(minWidth: 70, idealWidth: 76, maxWidth: 84, maxHeight: .infinity)
        .navigationSplitViewColumnWidth(min: 70, ideal: 76, max: 84)
        .animation(.easeOut(duration: 0.12), value: hoveredSection)
        .animation(.easeOut(duration: 0.12), value: viewModel.section)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace")
    }

    private func hoverPresentation(for section: AppSection) -> Binding<Bool> {
        Binding(
            get: { hoveredSection == section },
            set: { presented in
                if presented == false, hoveredSection == section {
                    hoveredSection = nil
                }
            }
        )
    }
}
