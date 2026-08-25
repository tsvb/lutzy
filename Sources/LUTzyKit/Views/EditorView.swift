import SwiftUI

/// Build a new look from one that already exists.
///
/// A panel of controls beside the picture, not on top of it: the whole job is
/// judging a change, and a change you cannot see at full size is one you cannot
/// judge. The preview is the ordinary viewer — same pipeline, same layouts —
/// so what is on screen here is what the saved LUT will do.
struct EditorView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var isSaving = false
    @State private var newName = ""

    var body: some View {
        HStack(spacing: 0) {
            PreviewView(viewModel: viewModel)
            Divider()
            controls
                .frame(width: 260)
        }
        // Set up on appearing, not on the navigation click: clicking a row that
        // is already selected is not a selection change, so a project restored
        // straight into the editor would arrive with nothing set up.
        .onAppear {
            if viewModel.editorBaseID == nil { viewModel.beginEditing() }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if viewModel.library.allLUTs.isEmpty {
            noLibrary
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    base
                    Divider()
                    adjustments
                    Divider()
                    stack
                    Divider()
                    actions
                }
                .padding(14)
            }
        }
    }

    private var noLibrary: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Import some LUTs first")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("The editor works by pushing an existing look around.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(14)
    }

    private var base: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Base")
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                ForEach(viewModel.library.allLUTs) { lut in
                    Button(lut.name) { viewModel.setEditorBase(lut) }
                }
            } label: {
                Text(viewModel.editorBase?.name ?? "Choose a LUT")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let base = viewModel.editorBase {
                Text(base.inputSpace == .vlog
                     ? "V-Log look — saves with the camera's V-Log tag"
                     : "Display look — saves without a Photo Style tag")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var adjustments: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Adjust")
                .font(.caption)
                .foregroundStyle(.secondary)

            slider("Exposure", value: viewModel.editorEdit.exposure, range: -2...2, unit: " EV") { new in
                viewModel.setEdit { $0.exposure = new }
            }
            slider("Contrast", value: viewModel.editorEdit.contrast, range: -1...1) { new in
                viewModel.setEdit { $0.contrast = new }
            }
            slider("Saturation", value: viewModel.editorEdit.saturation, range: 0...2) { new in
                viewModel.setEdit { $0.saturation = new }
            }
            slider("Temperature", value: viewModel.editorEdit.temperature, range: -1...1) { new in
                viewModel.setEdit { $0.temperature = new }
            }
            slider("Tint", value: viewModel.editorEdit.tint, range: -1...1) { new in
                viewModel.setEdit { $0.tint = new }
            }
            slider("Black lift", value: viewModel.editorEdit.blackLift, range: 0...0.15) { new in
                viewModel.setEdit { $0.blackLift = new }
            }
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stack after")
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                Button("None") { viewModel.setEditorStack(nil) }
                if viewModel.stackableLUTs.isEmpty {
                    Text("No display-input LUTs in the library")
                } else {
                    Divider()
                    ForEach(viewModel.stackableLUTs) { lut in
                        Button(lut.name) { viewModel.setEditorStack(lut) }
                    }
                }
            } label: {
                Text(viewModel.editorStack?.name ?? "None")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Only display-input LUTs are offered: a second V-Log LUT would be
            // handed the finished picture the base produced and read it as
            // scene light.
            Text("Only display-input LUTs can follow a camera look.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if viewModel.editorStack != nil {
                slider("Amount", value: viewModel.editorStackAmount, range: 0...1) { new in
                    viewModel.editorStackAmount = new
                    viewModel.scheduleEditedPreview()
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("Reset") { viewModel.resetEdit() }
                .disabled(viewModel.editorEdit.isNeutral && viewModel.editorStackID == nil)
            Spacer()
            Button("Save…") {
                newName = (viewModel.editorBase?.name).map { "\($0) edit" } ?? "New look"
                isSaving = true
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.editorBase == nil)
        }
        .sheet(isPresented: $isSaving) { saveSheet }
    }

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save look")
                .font(.headline)
            TextField("Name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitSave)
            Text("Saved into the library, under “Edited”.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { isSaving = false }
                Button("Save") { commitSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func commitSave() {
        viewModel.saveEditedLUT(named: newName)
        isSaving = false
    }

    private func slider(_ label: String, value: Float, range: ClosedRange<Float>,
                        unit: String = "", set: @escaping (Float) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: "%.2f", value) + unit)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { value }, set: set), in: range)
        }
    }
}
