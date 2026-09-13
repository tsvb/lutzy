import SwiftUI

/// One slider row, shared by the Adjust and Develop inspectors.
///
/// A title, a numeric field, a unit, a slider, and a reset that only appears when there is
/// something to reset — this is the whole vocabulary both panels' continuous controls need, so it
/// is written once rather than once per panel. `AdjustInspectorView` and `DevelopInspectorView`
/// differ in *which* rows they show and where the value comes from; neither differs in how a row
/// looks or behaves.
struct AdjustmentRow: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let neutral: Double
    let unit: String?
    /// 0 for Kelvin, 2 for everything else — the same precision `AdjustInspectorView.readout(for:)`
    /// used to hand-format before this row existed.
    let digits: Int
    let onReset: () -> Void

    @State private var isHovered = false

    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        neutral: Double,
        unit: String? = nil,
        digits: Int = 2,
        onReset: @escaping () -> Void
    ) {
        self.title = title
        self.value = value
        self.range = range
        self.neutral = neutral
        self.unit = unit
        self.digits = digits
        self.onReset = onReset
    }

    private var isAtNeutral: Bool {
        abs(value.wrappedValue - neutral) < 0.0005
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Button(action: onReset) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help("Reset")
                .opacity(isHovered && !isAtNeutral ? 1 : 0)
                .allowsHitTesting(isHovered && !isAtNeutral)

                TextField(
                    "",
                    value: Binding(
                        get: { value.wrappedValue },
                        set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
                    ),
                    format: .number.precision(.fractionLength(digits))
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .monospacedDigit()

                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Slider(value: value, in: range)
                .labelsHidden()
                .simultaneousGesture(
                    TapGesture().modifiers(.option).onEnded { onReset() }
                )
        }
        .onHover { isHovered = $0 }
    }
}
