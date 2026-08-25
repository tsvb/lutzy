import SwiftUI

/// What a LUT does, drawn and numbered.
///
/// The tag row says a look is 高對比; this says by how much, and where the
/// contrast is — which is the difference between choosing a look and knowing
/// one. Everything here is the measurement the tags were derived from, so the
/// panel and the tags can never disagree.
struct LUTInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        // Scrolled and pinned to the top, like the other tabs. A bare stack
        // gets centred in the inspector, which reads as the panel having
        // drifted rather than as content that happens to be short.
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let lut = viewModel.selectedLUT {
                    header(lut)
                    curve(lut)
                    if let metrics = viewModel.tags.metrics(for: lut) {
                        numbers(metrics)
                    }
                    tags(lut)
                } else {
                    Text("LUT").font(.headline)
                    Text("No LUT selected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func header(_ lut: CubeLUT) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.catalog.effectiveName(for: lut))
                .font(.headline)
                .lineLimit(2)
            Text("\(lut.size)³ · \(lut.inputSpace == .vlog ? "V-Log input" : "Display input")"
                 + (lut.photoStyleTag.map { " · \($0)" } ?? ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The neutral axis: what the LUT does to grey, per channel.
    ///
    /// One line each rather than a single luma curve, because the gap between
    /// them *is* the colour cast — a warm look shows as red above blue, which a
    /// combined curve would average away.
    private func curve(_ lut: CubeLUT) -> some View {
        let steps = 64
        let probe = (0...steps).flatMap { step -> [Float] in
            let v = Float(step) / Float(steps)
            return [v, v, v]
        }
        let sampled = lut.sample(probe)

        return VStack(alignment: .leading, spacing: 6) {
            Text("Response on grey")
                .font(.subheadline.weight(.semibold))
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.25))
                GeometryReader { geo in
                    // The identity, for reference: anything above this line is
                    // being brightened, anything below darkened.
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    }
                    .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    ForEach(Array(channels.enumerated()), id: \.offset) { index, channel in
                        Path { path in
                            for step in 0...steps {
                                let x = geo.size.width * CGFloat(step) / CGFloat(steps)
                                let value = CGFloat(sampled[step * 3 + index])
                                let point = CGPoint(x: x, y: geo.size.height * (1 - value))
                                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                            }
                        }
                        .stroke(channel, lineWidth: 1.5)
                    }
                }
                .padding(6)
            }
            .frame(height: 140)
            if lut.inputSpace == .vlog {
                Text("Input is V-Log: black sits at 0.125, mid grey at 0.42.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var channels: [Color] {
        [Color.red.opacity(0.9), Color.green.opacity(0.9), Color.blue.opacity(0.9)]
    }

    private func numbers(_ m: LUTMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Measured")
                .font(.subheadline.weight(.semibold))
            // Ratios against a neutral rendering of the same input, so 1.00
            // means "leaves this alone" for every one of them.
            row("Contrast", m.contrast, reference: 1)
            row("Saturation", m.saturation, reference: 1)
            row("Skin", m.skinRatio, reference: 1)
            Divider().padding(.vertical, 2)
            row("Black", m.blackLevel, reference: 0)
            row("White", m.whiteLevel, reference: 1)
            if m.shadowChroma > 0.004 || m.highlightChroma > 0.004 {
                row("Split", m.splitAngle, suffix: "°")
                row("Shadow hue", m.shadowHue, suffix: "°")
                row("Highlight hue", m.highlightHue, suffix: "°")
            }
        }
    }

    private func row(_ label: String, _ value: Double, reference: Double? = nil, suffix: String = "") -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: suffix.isEmpty ? "%.2f" : "%.0f", value) + suffix)
                .font(.system(.caption, design: .monospaced))
                // Dim the ones that are not doing anything, so the ones that
                // are stand out without having to read every number.
                .foregroundStyle(reference.map { abs(value - $0) < 0.02 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary) }
                                 ?? AnyShapeStyle(.primary))
        }
    }

    private func tags(_ lut: CubeLUT) -> some View {
        let all = viewModel.allTags(for: lut).filter { $0.hasPrefix("input:") == false }
        return VStack(alignment: .leading, spacing: 6) {
            if all.isEmpty == false {
                Text("Tags")
                    .font(.subheadline.weight(.semibold))
                FlowLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(all, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
    }
}
