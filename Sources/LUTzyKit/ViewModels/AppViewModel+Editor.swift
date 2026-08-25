import Foundation
import AppKit
import UniformTypeIdentifiers

/// The editor: take a look that exists, push it around, save what comes out.
@MainActor
extension AppViewModel {

    /// The LUT being edited. Defaults to whatever is selected when the editor
    /// is opened, because that is almost always the one the user just decided
    /// was nearly right.
    var editorBase: CubeLUT? {
        editorBaseID.flatMap { id in library.allLUTs.first(matching: id) }
    }

    var editorStack: CubeLUT? {
        editorStackID.flatMap { id in library.allLUTs.first(matching: id) }
    }

    /// LUTs that may be stacked *after* the base.
    ///
    /// Only display-input ones. A second V-Log LUT would be handed the finished
    /// picture the first produced and read it as scene light — the same mistake
    /// as applying a camera LUT to a JPEG, and one worth making impossible
    /// rather than documenting.
    var stackableLUTs: [CubeLUT] {
        library.allLUTs.filter { $0.inputSpace == .display }
    }

    /// Open the editor on a LUT, defaulting to the current selection.
    func beginEditing(_ lut: CubeLUT? = nil) {
        let base = lut ?? selectedLUT
        editorBaseID = base?.lutID
        editorEdit = .neutral
        editorStackID = nil
        editorStackAmount = 1
        section = .editor
        // The comparison that matters here is the edit against the look it
        // started from — not against the ungraded frame, and certainly not
        // against eight other LUTs, which is what a grid left over from the
        // viewer would show.
        showBaseAgainstEdit()
        refreshEditedPreview()
    }

    func setEdit(_ transform: (inout LookEdit) -> Void) {
        transform(&editorEdit)
        scheduleEditedPreview()
    }

    func setEditorBase(_ lut: CubeLUT?) {
        editorBaseID = lut?.lutID
        showBaseAgainstEdit()
        refreshEditedPreview()
    }

    /// Put the unedited base on the left and the edit on the right.
    private func showBaseAgainstEdit() {
        cellLUTIDs = [editorBaseID]
        cellImages = [nil]
        activeGridCellIndex = nil
        comparisonLayout = .compare
        renderAllCells()
    }

    func setEditorStack(_ lut: CubeLUT?) {
        editorStackID = lut?.lutID
        refreshEditedPreview()
    }

    func resetEdit() {
        editorEdit = .neutral
        editorStackID = nil
        editorStackAmount = 1
        refreshEditedPreview()
    }

    /// Debounced, because every slider tick asks for a fresh 33³ bake plus a
    /// render. The bake itself is cheap; the render is not.
    func scheduleEditedPreview() {
        editorPreviewTask?.cancel()
        editorPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard Task.isCancelled == false else { return }
            self?.refreshEditedPreview()
        }
    }

    /// Bake the edit and show it.
    ///
    /// The baked LUT is registered like a derived one, so the ordinary render
    /// path resolves it: the editor previews through exactly the pipeline the
    /// viewer uses, rather than a second one that could disagree with it.
    func refreshEditedPreview() {
        guard section == .editor, let base = editorBase else { return }
        let entries = LookBaker.bake(base: base, edit: editorEdit,
                                     stacked: editorStack, stackAmount: editorStackAmount)
        let edited = CubeLUT(
            cube: entries,
            size: LookBaker.size,
            name: editedName(from: base),
            category: "Edited",
            inputSpace: base.inputSpace
        )
        editedLUT = edited
        // `selectLUT` is the one path that registers an in-memory LUT and
        // re-renders, so the editor previews through exactly the pipeline the
        // viewer uses rather than a second one that could disagree with it.
        selectLUT(edited)
    }

    /// A name that says what it came from without pretending to be it.
    private func editedName(from base: CubeLUT) -> String {
        editorEdit.isNeutral && editorStackID == nil ? base.name : "\(base.name) edit"
    }

    // MARK: - Saving

    /// Write the edited look into the app's own library.
    ///
    /// Into the library rather than to a chosen folder: the point of editing is
    /// to end up with a look you can use, and one that lands outside the
    /// library is one you have to import before you can.
    func saveEditedLUT(named name: String) {
        guard let base = editorBase else {
            statusMessage = "Nothing to save — choose a LUT to edit first"
            return
        }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return }

        let entries = LookBaker.bake(base: base, edit: editorEdit,
                                     stacked: editorStack, stackAmount: editorStackAmount)
        let folder = LUTLibrary.managedFolder.appendingPathComponent("Edited", isDirectory: true)
        let destination = folder.appendingPathComponent("\(cleaned).cube")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try CubeWriter.write(
                entries: entries,
                size: LookBaker.size,
                title: cleaned,
                // The tag the camera reads. A look built on a V-Log base is
                // still a V-Log look; one built on a display LUT is not, and
                // declaring V-Log for it would tell the camera a lie.
                photoStyle: base.inputSpace == .vlog ? "VLOG" : nil,
                to: destination
            )
            library.useManagedFolder()
            statusMessage = "Saved \(cleaned).cube to the library"
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }
}
