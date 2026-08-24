import SwiftUI

/// Main image preview area. Supports side-by-side (original vs LUT)
/// and single-image mode. Hold Space to flash original in single mode.
struct PreviewView: View {
    @ObservedObject var viewModel: AppViewModel

    private let bgColor = Color(nsColor: NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1))

    var body: some View {
        ZStack {
            bgColor

            if viewModel.sourceImage != nil {
                switch viewModel.comparisonLayout {
                case .split:
                    // Split still needs something to compare against: with a
                    // neutral document both halves would be the same pixels.
                    if viewModel.isComparisonAvailable { sideBySideView } else { singleView }
                case .compare:
                    compareView
                case .single:
                    singleView
                default:
                    ComparisonGridView(viewModel: viewModel)
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(.circular)
            } else {
                emptyState
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Side-by-side

    private var sideBySideView: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                // Original
                panelView(
                    image: viewModel.originalPreviewNSImage,
                    label: "Original",
                    labelSide: .leading,
                    width: geo.size.width / 2
                )

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1)

                // LUT applied
                panelView(
                    image: viewModel.previewNSImage,
                    label: viewModel.selectedLUT?.name ?? "Adjusted",
                    labelSide: .trailing,
                    width: geo.size.width / 2
                )
            }
        }
        .padding(8)
    }

    private func panelView(image: NSImage?, label: String, labelSide: HorizontalAlignment, width: CGFloat) -> some View {
        ZStack(alignment: labelSide == .leading ? .topLeading : .topTrailing) {
            bgColor

            if let nsImage = image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: width, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.15), value: viewModel.selectedLUT)
            }

            ComparisonBadge(text: label)
                .padding(12)
        }
        .clipped()
    }

    // MARK: - Compare (chosen base vs current)

    /// Like split, except the left side is a LUT of the user's choosing rather
    /// than the ungraded original. This is the layout for telling two similar
    /// looks apart: against the same flat baseline they look alike, and against
    /// each other they do not.
    private var compareView: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ZStack(alignment: .bottom) {
                    bgColor
                    if let image = viewModel.cellImages.first ?? nil {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: geo.size.width / 2, maxHeight: .infinity)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    CompareBaseMenu(
                        name: viewModel.compareBaseLUT?.name ?? "No LUT",
                        luts: viewModel.library.allLUTs,
                        choose: { viewModel.setCell(0, to: $0) }
                    )
                    .padding(12)
                }
                .clipped()

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1)

                panelView(
                    image: viewModel.previewNSImage,
                    label: viewModel.selectedLUT?.name ?? "Adjusted",
                    labelSide: .trailing,
                    width: geo.size.width / 2
                )
            }
        }
        .padding(8)
    }

    // MARK: - Single image

    private var singleView: some View {
        ZStack {
            if let nsImage = viewModel.previewNSImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
                    .animation(.easeInOut(duration: 0.15), value: viewModel.isShowingOriginal)
                    .animation(.easeInOut(duration: 0.15), value: viewModel.selectedLUT)

                // Comparison badge
                if viewModel.isShowingOriginal && viewModel.isComparisonAvailable {
                    VStack {
                        HStack {
                            ComparisonBadge(text: "Original")
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(20)
                }

                // LUT name badge
                if !viewModel.isShowingOriginal, let lut = viewModel.selectedLUT {
                    VStack {
                        HStack {
                            Spacer()
                            ComparisonBadge(text: lut.name)
                        }
                        Spacer()
                    }
                    .padding(20)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Drop an image or folder here")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("⌘O open  \u{2022}  ⌘⇧I import from Photos  \u{2022}  ⌘⌥I source folder")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
    }

    // MARK: - Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    viewModel.openSourceFolder(url: url)
                } else {
                    viewModel.collection.clear()
                    viewModel.openImage(url: url)
                }
            }
        }
        return true
    }
}

/// The compare layout's base picker. Same idea as a grid cell's name plate: the
/// label you read to decide is the control you click to change it.
private struct CompareBaseMenu: View {
    let name: String
    let luts: [CubeLUT]
    let choose: (CubeLUT?) -> Void

    var body: some View {
        Menu {
            Button("No LUT (original)") { choose(nil) }
            Divider()
            ForEach(luts) { lut in
                Button(lut.name) { choose(lut) }
            }
        } label: {
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct ComparisonBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .foregroundColor(.primary)
    }
}
