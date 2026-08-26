import SwiftUI

/// Visual local LUT browser. Selecting a card opens detail here; it does not
/// silently mutate the Viewer document.
struct LUTLibraryView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VSplitView {
            detail
                .frame(maxWidth: .infinity, minHeight: 250, idealHeight: 390)
            LUTPreviewGalleryView(viewModel: viewModel)
                .frame(maxWidth: .infinity, minHeight: 250, idealHeight: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    @State private var rendered: LUTLibraryRenderPair?
    @State private var split = 0.5
    @FocusState private var comparisonFocused: Bool

    private struct RenderKey: Hashable {
        let lutID: LUTID
        let sampleID: String
        let revision: Int
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                comparison
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focusable()
                    .focused($comparisonFocused)
                    .onChange(of: comparisonFocused) { _, focused in
                        viewModel.setLUTDetailFocused(focused)
                    }
                Divider()
                sampleStrip
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        viewModel.setLUTDetailFocused(false)
                        viewModel.selectedLibraryLUTID = nil
                    } label: {
                        Label("Back to Gallery", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)

                    Text(viewModel.catalog.effectiveName(for: lut))
                        .font(.title2.weight(.semibold))
                    LabeledContent("Origin", value: viewModel.catalog.origin(for: lut).label)
                    LabeledContent("Input", value: lut.inputSpace == .vlog ? "V-Log" : "Display")
                    LabeledContent("Size", value: "\(lut.size)³")
                    LabeledContent("Sample", value: viewModel.selectedLibrarySample.name)
                    Text(viewModel.selectedLibrarySample.note)
                        .font(.caption).foregroundStyle(.secondary)
                    Text(viewModel.selectedLibrarySample.colorProfile)
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(viewModel.selectedLibrarySample.provenance)
                        .font(.caption2).foregroundStyle(.tertiary)

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
        .task(id: RenderKey(
            lutID: lut.lutID,
            sampleID: viewModel.selectedLibrarySampleID,
            revision: viewModel.lutGalleryRevision
        )) {
            rendered = nil
            rendered = await viewModel.makeLUTLibraryDetailImages(
                for: lut,
                sample: viewModel.selectedLibrarySample,
                maxSize: CGSize(width: 1400, height: 900)
            )
        }
        .onAppear {
            Task { @MainActor in comparisonFocused = true }
        }
        .onDisappear {
            viewModel.setLUTDetailFocused(false)
        }
    }

    private var comparison: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.9)
                if let rendered {
                    // Keep comparison semantics consistent with Viewer:
                    // Before is always on the left and After is on the right.
                    Image(nsImage: rendered.graded)
                        .resizable().scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                    if viewModel.isShowingLibraryOriginal == false {
                        Image(nsImage: rendered.original)
                            .resizable().scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: geo.size.width * split)
                            }

                        Rectangle()
                            .fill(Color.white.opacity(0.95))
                            .frame(width: 2, height: geo.size.height)
                            .offset(x: geo.size.width * split - 1)
                            .shadow(color: .black.opacity(0.6), radius: 2)

                        Image(systemName: "arrow.left.and.right.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.black.opacity(0.55))
                            .offset(x: geo.size.width * split - 11)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    comparisonFocused = true
                    split = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                }
            )
            .overlay(alignment: .top) {
                HStack {
                    comparisonLabel("Before")
                    Spacer()
                    if viewModel.isShowingLibraryOriginal == false {
                        comparisonLabel("After")
                    }
                }
                .padding(12)
            }
            .help("Drag to compare. Hold Space to show the complete original.")
        }
    }

    private func comparisonLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var sampleStrip: some View {
        HStack(spacing: 10) {
            ForEach(viewModel.librarySamples) { sample in
                Button {
                    viewModel.selectedLibrarySampleID = sample.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Group {
                            if let url = sample.url, let image = NSImage(contentsOf: url) {
                                Image(nsImage: image).resizable().scaledToFill()
                            } else {
                                Color.primary.opacity(0.07)
                            }
                        }
                        .frame(width: 86, height: 52)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(viewModel.selectedLibrarySampleID == sample.id
                                        ? Color.accentColor : Color.primary.opacity(0.1),
                                        lineWidth: viewModel.selectedLibrarySampleID == sample.id ? 2 : 1)
                        }
                        Text(sample.name).font(.caption2).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use \(sample.name) sample")
            }
            Spacer()
            Text("Fixed samples")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
