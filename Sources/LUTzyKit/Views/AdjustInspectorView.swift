import SwiftUI

/// Tone and colour adjustments — the nodes that run *after* the develop stage and *before* the LUT.
///
/// **One state, where `DevelopInspectorView` has three.** That asymmetry is the honest one: Develop's
/// three states exist because *the file* answers a question — is there a decode stage, and has the
/// capability probe landed yet — and here there is no question to ask. Adjustments are applied to an
/// already-developed image, so they mean the same thing for a RAW and a JPEG, and no row is ever
/// absent or gated.
///
/// Nine rows over five `AdjustmentNode` cases, one row per parameter. The list is not written out
/// here — it comes from `AdjustmentControl.allCases`, so which rows appear and in what order is a
/// value the tests can assert rather than a shape buried in a `ViewBuilder`.
struct AdjustInspectorView: View {
    let viewModel: AppViewModel
    /// Bumped per control on reset so its arrow bounces; the value itself is meaningless.
    @State private var resets: [AdjustmentControl: Int] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(AdjustmentControl.allCases, id: \.self) { control in
                    controlRow(control)
                }
            } header: {
                header
            }
        }
        .formStyle(.grouped)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var header: some View {
        HStack {
            Text("Adjustments")
            Spacer()
            Button("Reset") { viewModel.resetAllAdjustments() }
                .buttonStyle(.link)
                .disabled(!viewModel.hasAdjustments)
        }
    }

    @ViewBuilder
    private func controlRow(_ control: AdjustmentControl) -> some View {
        let value = viewModel.adjustmentValue(for: control)
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                HStack(spacing: 6) {
                    Text(readout(for: control))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: value))
                        .animation(.default, value: value)
                    Button {
                        resets[control, default: 0] += 1
                        viewModel.resetAdjustment(control)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .symbolEffect(.bounce, value: resets[control, default: 0])
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .help("Reset to neutral")
                }
            } label: {
                Text(control.title)
            }

            Slider(value: viewModel.adjustmentBinding(for: control), in: control.range)
                .labelsHidden()
        }
    }

    /// Kelvin reads as a whole number; everything else to two places. 5842.20 K is noise on a
    /// slider whose useful travel is thousands of degrees wide.
    private func readout(for control: AdjustmentControl) -> String {
        let value = viewModel.adjustmentValue(for: control)
        switch control {
        case .temperature:
            return String(format: "%.0f K", value)
        case .exposure, .brightness, .contrast, .saturation, .highlights, .shadows, .tint, .vibrance:
            return String(format: "%.2f", value)
        }
    }
}
