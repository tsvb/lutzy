import SwiftUI
import Charts

/// Compact analysis card shown after a successful recipe derivation.
/// Tone curve chart + stat badges + camera info from EXIF.
struct RecipeReportView: View {
    let report: RecipeReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analysis")
                .font(.headline)

            toneCurveChart
                .frame(height: 130)

            statRow

            if let cam = report.cameraInfo, !cam.make.isEmpty || !cam.model.isEmpty {
                Divider()
                cameraInfoRow(cam)
            }
        }
    }

    // MARK: - Tone curve

    private var toneCurveChart: some View {
        Chart {
            // Identity reference line (two explicit endpoints — Charts' ForEach
            // overload requires Identifiable, so a Range<Int> won't work)
            LineMark(
                x: .value("In", Float(0)),
                y: .value("Out", Float(0)),
                series: .value("Series", "identity")
            )
            .foregroundStyle(.gray.opacity(0.4))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            LineMark(
                x: .value("In", Float(1)),
                y: .value("Out", Float(1)),
                series: .value("Series", "identity")
            )
            .foregroundStyle(.gray.opacity(0.4))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            ForEach(Array(report.toneCurve.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("In", point.input),
                    y: .value("R", point.outputR),
                    series: .value("Series", "R")
                )
                .foregroundStyle(.red)
                .interpolationMethod(.monotone)
            }
            ForEach(Array(report.toneCurve.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("In", point.input),
                    y: .value("G", point.outputG),
                    series: .value("Series", "G")
                )
                .foregroundStyle(.green)
                .interpolationMethod(.monotone)
            }
            ForEach(Array(report.toneCurve.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("In", point.input),
                    y: .value("B", point.outputB),
                    series: .value("Series", "B")
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: 0...1)
        .chartYScale(domain: 0...1)
        .chartXAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { _ in
                AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { _ in
                AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartLegend(.hidden)
    }

    // MARK: - Stat badges

    private var statRow: some View {
        HStack(spacing: 10) {
            StatBadge(
                label: "Saturation",
                value: String(format: "%.2f×", report.saturationRatio),
                tint: .orange
            )
            StatBadge(
                label: "Sharpening",
                value: String(format: "%.1f×", report.sharpeningRatio),
                tint: .purple,
                // "applied separately, not in LUT" promised a second stage that does not exist:
                // `sharpeningRatio` is measured, carried on the report and shown here, and has no
                // consumer anywhere in the render path. It is a diagnostic about the pair.
                hint: "measured, not applied"
            )
            StatBadge(
                label: "Coverage",
                value: String(format: "%.0f%%", report.cubeCoveragePercent),
                tint: report.cubeCoveragePercent >= 30 ? .green : .yellow
            )
            StatBadge(
                label: "Samples",
                value: shortCount(report.sampleCount),
                tint: .blue
            )
            // Shown rather than dropped (docs/CODE_REVIEW.md §2): of everything on this report it is
            // the one number that says the *pair* was wrong rather than the fit. Every other stat
            // stays plausible under a mis-registered pair — the cube still fits, just to the wrong
            // pixels — so a silent non-zero shift here was the failure nothing on screen could
            // explain. Tinted on magnitude for that reason: 0 is the expected reading.
            StatBadge(
                label: "Alignment",
                value: alignmentText,
                tint: isWellAligned ? .green : .yellow,
                hint: isWellAligned ? nil : "the pair may be mis-registered"
            )
        }
    }

    /// A shift of (0, 0) is the common case and reads better as a word than as coordinates.
    private var alignmentText: String {
        let (dx, dy) = report.alignmentShift
        return dx == 0 && dy == 0 ? "aligned" : "\(dx > 0 ? "+" : "")\(dx), \(dy > 0 ? "+" : "")\(dy)"
    }

    /// One pixel of play: the search is integer-pixel and a ±1 result on a real pair is rounding,
    /// not a crop difference.
    private var isWellAligned: Bool {
        let (dx, dy) = report.alignmentShift
        return abs(dx) <= 1 && abs(dy) <= 1
    }

    private func shortCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1_000)k" }
        return "\(n)"
    }

    // MARK: - Camera info

    @ViewBuilder
    private func cameraInfoRow(_ cam: RecipeReport.CameraInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(cam.make) \(cam.model)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let v = cam.exifContrast    { tag("Contrast: \(v)") }
                if let v = cam.exifSaturation  { tag("Saturation: \(v)") }
                if let v = cam.exifSharpness   { tag("Sharpness: \(v)") }
                if let v = cam.exifWhiteBalance { tag("WB: \(v)") }
                if let v = cam.exifCustomRendered, v != "Normal" { tag(v) }
            }
        }
    }

    private func tag(_ s: String) -> some View {
        Text(s)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Stat badge

private struct StatBadge: View {
    let label: String
    let value: String
    let tint: Color
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .help(hint ?? "")
    }
}
