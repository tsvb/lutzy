import SwiftUI
import Charts

/// Compact analysis body shown after a successful recipe derivation.
/// Tone curve chart + stat rows + camera info from EXIF. The "Result" section
/// header (and its "Derive again" link) is owned by the presenting sheet, not
/// this view — this renders only the body of that section.
struct RecipeReportView: View {
    let report: RecipeReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 4) {
                    toneCurveChart
                        .frame(width: 130, height: 130)
                    Text("Tone curve, input to output")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Saturation") {
                        Text(String(format: "%.2f×", report.saturationRatio))
                    }
                    LabeledContent("Sharpening") {
                        Text(String(format: "%.1f×", report.sharpeningRatio))
                    }
                    LabeledContent("Cube coverage") {
                        Text(coverageText)
                    }
                    LabeledContent("Samples") {
                        Text(shortCount(report.sampleCount))
                    }
                    LabeledContent("Alignment") {
                        Text(alignmentText)
                    }
                }
            }

            Text("Sharpening is measured for reference. A LUT cannot sharpen, so it is not applied.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let cam = report.cameraInfo, !cam.make.isEmpty || !cam.model.isEmpty {
                Text(cameraInfoLine(cam))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    // MARK: - Stat text

    private var coverageText: String {
        let side = report.cubeCoveragePercent >= 30 ? "above" : "below"
        return String(format: "%.0f%%, %@ the 30%% floor", report.cubeCoveragePercent, side)
    }

    /// A shift of (0, 0) is the common case and reads better as a word than as coordinates.
    private var alignmentText: String {
        let (dx, dy) = report.alignmentShift
        return dx == 0 && dy == 0 ? "Aligned" : "\(dx > 0 ? "+" : "")\(dx), \(dy > 0 ? "+" : "")\(dy)"
    }

    private func shortCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1_000)k" }
        return "\(n)"
    }

    // MARK: - Camera info

    private func cameraInfoLine(_ cam: RecipeReport.CameraInfo) -> String {
        var parts: [String] = []
        let name = "\(cam.make) \(cam.model)".trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { parts.append(name) }
        if let v = cam.exifContrast { parts.append("Contrast: \(v)") }
        if let v = cam.exifSaturation { parts.append("Saturation: \(v)") }
        if let v = cam.exifSharpness { parts.append("Sharpness: \(v)") }
        if let v = cam.exifWhiteBalance { parts.append("WB: \(v)") }
        if let v = cam.exifCustomRendered, v != "Normal" { parts.append(v) }
        return parts.joined(separator: " · ")
    }
}
