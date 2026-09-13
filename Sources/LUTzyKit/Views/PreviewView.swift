import SwiftUI

/// Main image preview area. Supports side-by-side (original vs LUT)
/// and single-image mode. Hold Space to flash original in single mode.
struct PreviewView: View {
    let viewModel: AppViewModel
    @State private var isDropTargeted = false

    private let bgColor = Color(nsColor: NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1))

    var body: some View {
        ZStack {
            bgColor

            if viewModel.sourceImage != nil {
                if viewModel.isSideBySide && viewModel.isComparisonAvailable {
                    sideBySideView
                } else {
                    singleView
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(.circular)
            } else {
                emptyState
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            open(dropped: url)
            return true
        } isTargeted: { isDropTargeted = $0 }
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

                // One glass container so the two badges blend if they ever overlap.
                GlassEffectContainer {
                    VStack {
                        HStack {
                            // Comparison badge
                            if viewModel.isShowingOriginal && viewModel.isComparisonAvailable {
                                ComparisonBadge(text: "Original")
                            }
                            Spacer()
                            // LUT name badge
                            if !viewModel.isShowingOriginal, let lut = viewModel.selectedLUT {
                                ComparisonBadge(text: lut.name)
                            }
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

    /// A folder becomes the source folder; a file replaces whatever set was loaded.
    private func open(dropped url: URL) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            viewModel.openSourceFolder(url: url)
        } else {
            viewModel.collection.clear()
            viewModel.openImage(url: url)
        }
    }
}

/// A Liquid Glass capsule over the image — it reads on any picture and follows the window's tint.
struct ComparisonBadge: View {
    let text: String
    /// Overlays step back with the window, like the system's own chrome does.
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(.primary)
            .glassEffect(.regular, in: .capsule)
            .opacity(appearsActive ? 1 : 0.6)
    }
}
