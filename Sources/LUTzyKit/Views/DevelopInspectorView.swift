import SwiftUI

/// RAW develop controls, gated per image on what the file's decoder actually supports.
///
/// The control list is not written out here — it comes from `RAWCapabilities.availableControls`, so
/// which knobs appear is a value the tests can assert rather than a shape buried in a `ViewBuilder`.
/// An unsupported adjustment is **absent**, not greyed out: absence reads as "this camera's decoder
/// does not do that", where a disabled slider reads as "you did something wrong".
///
/// **Three states, and the middle one is why this switches on `developPanelState`.** This used to be
/// `if let capabilities = viewModel.rawCapabilities { … } else { notRAW }`, which read the probe's
/// in-flight `nil` as "this file has no develop stage" and said exactly that, out loud, about a RAW —
/// for the 25–170 ms the probe takes, on every ←/→ step through a folder of them, since
/// `inspectorTab` is not reset on open. The distinction is drawn in the view model
/// (`AppViewModel.DevelopPanelState`) rather than here: this repo has no SwiftUI view tests, so a
/// state that exists only inside a `ViewBuilder` cannot be asserted.
struct DevelopInspectorView: View {
    let viewModel: AppViewModel

    var body: some View {
        Group {
            switch viewModel.developPanelState {
            case .ready(let capabilities):
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        ForEach(capabilities.availableControls, id: \.self) { control in
                            controlRow(control)
                        }
                    }
                    .padding(16)
                }
            case .probing:
                probing
            case .noDevelopStage:
                notRAW
            }
        }
    }

    private var header: some View {
        HStack {
            Text("RAW Develop").font(.headline)
            Spacer()
            Button("Reset") { viewModel.resetAllDevelop() }
                .buttonStyle(.link)
                .disabled(viewModel.document.rawDevelop.isNeutral)
        }
    }

    /// Shown for a RAW whose capability probe is still running.
    ///
    /// The header stays put — this file *does* have a develop stage, and the panel's identity should
    /// not blink out and back while a 25–170 ms question is answered — and only the control list is
    /// replaced, by a spinner. The alternative considered was keeping the previous image's controls
    /// on screen; it was rejected because their *values* are the previous file's per-image seeds
    /// (as-shot white balance, sharpening amount), so the panel would show numbers that are wrong
    /// for the picture on screen. A spinner claims nothing.
    private var probing: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the decoder's develop controls\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shown for a standard image. `RenderPipeline.developedSource` switches on `source.kind` and
    /// drops `rawDevelop` entirely for one, so offering the controls would be offering a lie.
    ///
    /// **Only ever reached once the answer is known.** Reaching it while the probe is in flight is
    /// the defect `developPanelState` exists to prevent — see this type's doc comment.
    private var notRAW: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.aperture")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No develop stage")
                .font(.headline)
            Text("Develop controls come from the RAW decoder. This image is already rendered.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func controlRow(_ control: DevelopControl) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(control.title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !control.isToggle {
                    Text(String(format: "%.2f", viewModel.developValue(for: control)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Button {
                    viewModel.resetDevelop(control)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help("Reset to the decoder's default")
            }

            if control.isToggle {
                Toggle(control.title, isOn: Binding(
                    get: { viewModel.developValue(for: control) != 0 },
                    set: { viewModel.developBinding(for: control).wrappedValue = $0 ? 1 : 0 }
                ))
                .labelsHidden()
            } else {
                Slider(
                    value: viewModel.developBinding(for: control),
                    in: control.range
                )
                if control == .whiteBalance {
                    HStack {
                        Text("Tint").font(.caption2).foregroundStyle(.secondary)
                        Slider(value: viewModel.developTintBinding(), in: DevelopControl.tintRange)
                    }
                }
            }
        }
    }
}
