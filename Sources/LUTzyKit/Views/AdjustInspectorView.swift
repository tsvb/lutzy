import SwiftUI

/// Tone and colour adjustments — the nodes that run *after* the develop stage and *before* the LUT
/// — plus the LUT's own intensity, which used to live in the toolbar.
///
/// **One state, where `DevelopInspectorView` has three.** That asymmetry is the honest one: Develop's
/// three states exist because *the file* answers a question — is there a decode stage, and has the
/// capability probe landed yet — and here there is no question to ask. Adjustments are applied to an
/// already-developed image, so they mean the same thing for a RAW and a JPEG, and no row is ever
/// absent or gated.
///
/// Three sections rather than one flat list: "LUT" (just Intensity — the one adjustment that only
/// means anything with a look selected), "Light" (tone: exposure, brightness, contrast, highlights,
/// shadows) and "Color" (saturation, vibrance, temperature, tint). The row lists come from
/// `AdjustmentControl.allCases.filter { $0.group == … }`, so which rows appear and in what order is
/// a value the tests can assert rather than a shape buried in a `ViewBuilder`.
struct AdjustInspectorView: View {
    let viewModel: AppViewModel

    var body: some View {
        Form {
            Section("LUT") {
                AdjustmentRow(
                    title: "Intensity",
                    value: intensityPercentBinding,
                    range: 0...100,
                    neutral: 100,
                    unit: "%",
                    digits: 0,
                    onReset: { viewModel.setLUTIntensity(1) }
                )
            }
            .disabled(viewModel.selectedLUT == nil)

            Section {
                ForEach(AdjustmentControl.allCases.filter { $0.group == .light }, id: \.self) { control in
                    row(for: control)
                }
            } header: {
                groupHeader(.light)
            }

            Section {
                ForEach(AdjustmentControl.allCases.filter { $0.group == .color }, id: \.self) { control in
                    row(for: control)
                }
            } header: {
                groupHeader(.color)
            }
        }
        .formStyle(.grouped)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var intensityPercentBinding: Binding<Double> {
        Binding(
            get: { viewModel.lutIntensity * 100 },
            set: { viewModel.setLUTIntensity($0 / 100) }
        )
    }

    private func groupHeader(_ group: AdjustmentGroup) -> some View {
        HStack {
            Text(group.rawValue)
            Spacer()
            Button("Reset") { resetGroup(group) }
                .buttonStyle(.link)
                .disabled(!viewModel.hasAdjustments(in: group))
        }
    }

    private func resetGroup(_ group: AdjustmentGroup) {
        for control in AdjustmentControl.allCases where control.group == group {
            viewModel.resetAdjustment(control)
        }
    }

    private func row(for control: AdjustmentControl) -> some View {
        AdjustmentRow(
            title: control.title,
            value: viewModel.adjustmentBinding(for: control),
            range: control.range,
            neutral: control.sliderMapped(control.neutral),
            unit: control.unit,
            digits: control == .temperature ? 0 : 2,
            onReset: { viewModel.resetAdjustment(control) }
        )
    }
}
