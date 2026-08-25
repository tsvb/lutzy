import SwiftUI

/// Visual local LUT browser. Selecting a card opens detail here; it does not
/// silently mutate the Viewer document.
struct LUTLibraryView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VSplitView {
            detail
                .frame(minHeight: 250, idealHeight: 390)
            LUTPreviewGalleryView(viewModel: viewModel)
                .frame(minHeight: 250, idealHeight: 360)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let lut = viewModel.selectedLibraryLUT {
            LUTLibraryDetailView(lut: lut, viewModel: viewModel)
        } else {
            ContentUnavailableView {
                Label("Choose a LUT", systemImage: "cube.transparent")
            } description: {
                Text("Select a card below to inspect it on the fixed sample set.")
            }
        }
    }
}

private struct LUTLibraryDetailView: View {
    let lut: CubeLUT
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black.opacity(0.88)
                if let image = viewModel.previewNSImage {
                    Image(nsImage: image).resizable().scaledToFit().padding(16)
                } else {
                    Image(systemName: "photo").font(.system(size: 48)).foregroundStyle(.tertiary)
                }
                Text("Before  |  After")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(viewModel.catalog.effectiveName(for: lut))
                        .font(.title2.weight(.semibold))
                    LabeledContent("Origin", value: viewModel.catalog.origin(for: lut).label)
                    LabeledContent("Input", value: lut.inputSpace == .vlog ? "V-Log" : "Display")
                    LabeledContent("Size", value: "\(lut.size)³")

                    if viewModel.allTags(for: lut).isEmpty == false {
                        Text("Tags").font(.subheadline.weight(.semibold))
                        FlowLayout(spacing: 5, lineSpacing: 5) {
                            ForEach(viewModel.allTags(for: lut), id: \.self) { tag in
                                Text(tag).font(.caption2)
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.08), in: Capsule())
                            }
                        }
                    }

                    Button("Open in Viewer") { viewModel.openLibraryLUTInViewer(lut) }
                        .buttonStyle(.borderedProminent)
                    Button(viewModel.isStarred(lut) ? "Unstar" : "Star") {
                        viewModel.toggleStarred(lut)
                    }
                    Menu("Add to Collection") {
                        ForEach(viewModel.catalog.collections) { collection in
                            Button(collection.name) {
                                viewModel.catalog.setMembership(
                                    true, collectionID: collection.id, recordIDs: [lut.lutID]
                                )
                            }
                        }
                    }
                    .disabled(viewModel.catalog.collections.isEmpty)
                }
                .padding(18)
            }
            .frame(minWidth: 250, idealWidth: 300, maxWidth: 380)
        }
    }
}
