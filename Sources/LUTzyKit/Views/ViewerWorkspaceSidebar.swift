import SwiftUI

/// Viewer-local navigation: media stays at the top, while LUT sources remain
/// grouped below it. Neither becomes a top-level mode switch.
struct ViewerWorkspaceSidebar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            mediaSection
                .frame(minHeight: 150, idealHeight: 230, maxHeight: 330)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text("LUTs").font(.headline)
                    Spacer()
                    Text("\(viewModel.galleryLUTs.count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                LUTSourceList(viewModel: viewModel, context: .viewer)
            }
        }
        .frame(minWidth: 220, idealWidth: 270, maxWidth: 390)
    }

    private var mediaSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Media").font(.headline)
                Spacer()
                Button { viewModel.importImages() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Import Images or Videos")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            if viewModel.media.records.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled").foregroundStyle(.tertiary)
                    Text("Import media to start").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.media.records.filter(\.isAvailable)) { record in
                            Button { viewModel.openMedia(record) } label: {
                                HStack(spacing: 8) {
                                    mediaThumbnail(record)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(record.displayName).lineLimit(1)
                                        Text(record.kind == .video ? "Video" : (record.logicalFolder.isEmpty ? "Media Library" : record.logicalFolder))
                                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(viewModel.media.selectedID == record.id
                                            ? Color.accentColor.opacity(0.2) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.bottom, 7)
                }
            }
        }
    }

    @ViewBuilder
    private func mediaThumbnail(_ record: MediaRecord) -> some View {
        if let thumbnail = viewModel.thumbnail(for: record) {
            Image(nsImage: thumbnail).resizable().scaledToFill()
                .frame(width: 42, height: 30).clipped().cornerRadius(3)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.07))
                Image(systemName: record.kind == .video ? "play.fill" : "photo")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 42, height: 30)
        }
    }
}
