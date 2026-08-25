import AppKit
import SwiftUI

/// A contact sheet for auditioning every LUT below the selected folder on the
/// photograph that is currently open.
struct LUTPreviewGalleryView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var searchText = ""
    @AppStorage("lutzy.viewerLUTCardWidth") private var cardWidth = 220.0

    private var visibleLUTs: [CubeLUT] {
        guard searchText.isEmpty == false else { return viewModel.viewerFolderLUTs }
        let query = searchText.localizedLowercase
        return viewModel.viewerFolderLUTs.filter {
            $0.name.localizedLowercase.contains(query)
        }
    }

    private var folderName: String { viewModel.browsedCategory ?? "All LUTs" }

    var body: some View {
        VStack(spacing: 0) {
            galleryHeader
            Divider()

            if visibleLUTs.isEmpty {
                emptyState
            } else {
                gallery
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var galleryHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.accentColor)
            Text(folderName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("\(visibleLUTs.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if viewModel.comparisonLayout.isGrid {
                Rectangle()
                    .fill(Color.primary.opacity(0.16))
                    .frame(width: 1, height: 16)
                Label(
                    "Assigning to Cell \((viewModel.activeGridCellIndex ?? 0) + 1)",
                    systemImage: "scope"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                Text("Click a look or drag it onto any cell")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search this folder", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
                if searchText.isEmpty == false {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            Image(systemName: "rectangle.grid.3x2")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $cardWidth, in: 150...320)
                .frame(width: 105)
                .help("Preview size")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var gallery: some View {
        let columns = [
            GridItem(
                .adaptive(
                    minimum: CGFloat(cardWidth),
                    maximum: CGFloat(cardWidth) * 1.35
                ),
                spacing: 8
            )
        ]

        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(visibleLUTs) { lut in
                    LUTPreviewCard(
                        lut: lut,
                        viewModel: viewModel
                    )
                }
            }
            .padding(10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "folder" : "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "No LUTs in this folder" : "No matching LUTs")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if searchText.isEmpty == false {
                Button("Clear Search") { searchText = "" }
                    .buttonStyle(.borderless)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LUTPreviewCard: View {
    let lut: CubeLUT
    @ObservedObject var viewModel: AppViewModel

    @State private var preview: NSImage?
    @State private var isHovering = false

    private var isSelected: Bool { viewModel.selectedLUT?.lutID == lut.lutID }
    private var isFavourite: Bool { viewModel.tags.isFavourite(lut) }

    private var renderIdentity: RenderIdentity {
        RenderIdentity(
            lutID: lut.lutID,
            revision: viewModel.lutGalleryRevision
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1))

                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFill()
                } else if viewModel.sourceImage != nil {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "cube.transparent")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .clipped()
            .overlay(alignment: .topTrailing) {
                Button {
                    viewModel.tags.toggleFavourite(lut)
                } label: {
                    Image(systemName: isFavourite ? "star.fill" : "star")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isFavourite ? Color.yellow : Color.white)
                        .padding(6)
                        .background(Color.black.opacity(0.42), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(7)
                .opacity(isFavourite || isHovering ? 1 : 0.72)
                .help(isFavourite ? "Unstar \(lut.name)" : "Star \(lut.name)")
            }

            HStack(spacing: 6) {
                Text(lut.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if lut.inputSpace == .vlog {
                    Text("V-LOG")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(isHovering ? 0.18 : 0.07),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { viewModel.chooseLUTFromGallery(lut) }
        .draggable(lut.lutID.raw) {
            Label(lut.name, systemImage: "cube.fill")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        }
        .onHover { isHovering = $0 }
        .help(
            viewModel.comparisonLayout.isGrid
                ? "Click to assign to Cell \((viewModel.activeGridCellIndex ?? 0) + 1), or drag onto another cell"
                : "Apply \(lut.name)"
        )
        .contextMenu {
            Button(isFavourite ? "Unstar" : "Star") {
                viewModel.tags.toggleFavourite(lut)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([lut.url])
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lut.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { viewModel.chooseLUTFromGallery(lut) }
        .task(id: renderIdentity) {
            preview = nil
            guard viewModel.sourceImage != nil else { return }
            preview = await viewModel.makeLUTGalleryPreview(
                for: lut,
                maxSize: CGSize(width: 640, height: 400)
            )
        }
    }

    private struct RenderIdentity: Hashable {
        let lutID: LUTID
        let revision: Int
    }
}
