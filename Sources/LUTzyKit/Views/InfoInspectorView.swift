import SwiftUI

/// Docked inspector pane: histogram of the displayed image up top, EXIF/TIFF
/// metadata listed below. Toggled from the toolbar (and ⌘I).
struct InfoInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // No image, no tabs. Both halves describe *a picture*: with nothing open, the switcher
            // offers a trip to Develop to be told "this image is already rendered" about an image
            // that does not exist. The empty state alone is the honest answer.
            if viewModel.sourceImage == nil {
                emptyState
            } else {
                tabSwitcher

                Divider()

                switch viewModel.inspectorTab {
                case .lut:
                    LUTInspectorView(viewModel: viewModel)
                case .info:
                    infoContent
                case .develop:
                    DevelopInspectorView(viewModel: viewModel)
                case .adjust:
                    AdjustInspectorView(viewModel: viewModel)
                }
            }
        }
        .frame(minWidth: 240, idealWidth: 280)
    }

    private var tabSwitcher: some View {
        Picker("", selection: $viewModel.inspectorTab) {
            ForEach(AppViewModel.InspectorTab.allCases, id: \.self) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// The original histogram + EXIF column. Only reached with an image open — the no-image case is
    /// handled one level up, before the tab switcher exists.
    private var infoContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                histogramSection
                metadataSection
            }
            .padding(16)
        }
    }

    // MARK: - Histogram

    private var histogramSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Histogram")
                    .font(.headline)
                Spacer()
                Text(histogramSourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15), in: Capsule())
            }

            if let histogram = viewModel.histogram {
                HistogramChart(data: histogram, channel: channel)
                    .frame(height: 120)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.25))
                    .frame(height: 120)
                    .overlay(ProgressView().controlSize(.small))
            }

            Picker("Channel", selection: $channel) {
                Text("RGB").tag(HistogramChart.Mode.rgb)
                Text("Luma").tag(HistogramChart.Mode.luma)
                Text("R").tag(HistogramChart.Mode.red)
                Text("G").tag(HistogramChart.Mode.green)
                Text("B").tag(HistogramChart.Mode.blue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @State private var channel: HistogramChart.Mode = .rgb

    private var histogramSourceLabel: String {
        if viewModel.isShowingOriginal { return "Original" }
        return viewModel.selectedLUT != nil ? "Graded" : "Original"
    }

    // MARK: - Metadata

    @ViewBuilder
    private var metadataSection: some View {
        let sections = viewModel.metadata.sections
        if sections.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Info")
                    .font(.headline)
                Text("No metadata available for this image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                        ForEach(section.rows) { row in
                            metadataRow(row)
                        }
                    }
                }
            }
        }
    }

    private func metadataRow(_ row: ImageMetadata.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(row.value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 28, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Open an image to see its\nhistogram and EXIF data")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Histogram chart

/// Canvas-drawn histogram. RGB mode overlays the three channels with additive
/// blending (overlaps brighten toward white, the classic look); single-channel
/// and luma modes draw one filled curve.
struct HistogramChart: View {
    enum Mode: Hashable {
        case rgb, luma, red, green, blue
    }

    let data: HistogramData
    let channel: Mode

    var body: some View {
        Canvas { context, size in
            switch channel {
            case .rgb:
                fill(.red,   Color.red,   in: context, size: size, blend: .plusLighter)
                fill(.green, Color.green, in: context, size: size, blend: .plusLighter)
                fill(.blue,  Color.blue,  in: context, size: size, blend: .plusLighter)
            case .luma:
                fill(.luma, Color.white.opacity(0.85), in: context, size: size, blend: .normal)
            case .red:
                fill(.red, Color.red, in: context, size: size, blend: .normal)
            case .green:
                fill(.green, Color.green, in: context, size: size, blend: .normal)
            case .blue:
                fill(.blue, Color.blue, in: context, size: size, blend: .normal)
            }
        }
    }

    private func fill(
        _ ch: HistogramData.Channel,
        _ color: Color,
        in context: GraphicsContext,
        size: CGSize,
        blend: GraphicsContext.BlendMode
    ) {
        let norm = data.normalized(ch)
        guard norm.count > 1 else { return }
        let w = size.width
        let h = size.height
        let step = w / CGFloat(norm.count - 1)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        for (i, v) in norm.enumerated() {
            let x = CGFloat(i) * step
            let y = h - v * h
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()

        var ctx = context
        ctx.blendMode = blend
        ctx.fill(path, with: .color(color.opacity(channel == .rgb ? 0.75 : 0.9)))
    }
}
