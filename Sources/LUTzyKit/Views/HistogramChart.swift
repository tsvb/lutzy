import SwiftUI

// Lived at the bottom of `InfoInspectorView.swift`, a file about a different thing — the last open
// bullet in `docs/CODE_REVIEW.md` §3. Moved here rather than into `Models/Histogram.swift`, which is
// where the review pointed: that file is the *data*, and `LUTzyKit`'s Models layer does not import
// SwiftUI. Keeping the tally and the drawing in separate layers is the reason the histogram is
// testable without a view in the first place.

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
