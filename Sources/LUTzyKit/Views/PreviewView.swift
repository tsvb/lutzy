import SwiftUI

/// Main image preview area. Supports side-by-side (original vs LUT)
/// and single-image mode. Hold Space to flash original in single mode.
struct PreviewView: View {
    let viewModel: AppViewModel

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
