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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(AdjustmentControl.allCases, id: \.self) { control in
                    controlRow(control)
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack {
            Text("Adjustments").font(.headline)
            Spacer()
            Button("Reset") { viewModel.resetAllAdjustments() }
                .buttonStyle(.link)
                .disabled(!viewModel.hasAdjustments)
        }
    }

    @ViewBuilder
    private func controlRow(_ control: AdjustmentControl) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(control.title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(readout(for: control))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.resetAdjustment(control)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help("Reset to neutral")
            }

            Slider(value: viewModel.adjustmentBinding(for: control), in: control.range)
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
