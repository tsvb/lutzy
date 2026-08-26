import Foundation
import AppKit
import UniformTypeIdentifiers

/// Owns the "Derive LUT from JPG" flow: the sheet's presentation, the
/// long-running extraction, and the scratch-until-saved lifecycle of the
/// result.
///
/// The derived LUT is deliberately *not* written into the user's library on
/// completion. It lives as a scratch file until they explicitly Save, so an
/// experiment doesn't litter the LUT folder.
///
/// Like `ExportCoordinator`, the save is split into a panel-free
/// `performSave(to:)` core and a `saveDialog` wrapper, and status/error text
/// leaves through closures so presentation stays with `AppViewModel`.
@MainActor
final class DeriveCoordinator: ObservableObject {

    @Published var isSheetPresented: Bool = false
    @Published private(set) var isDeriving: Bool = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var stage: String = ""
    @Published private(set) var derivedLUT: CubeLUT?
    @Published private(set) var report: RecipeReport?

    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?
    /// Fired when a derive succeeds, so the app can preview the new look.
    var onDerived: ((CubeLUT) -> Void)?
    /// Where the Save panel should open, and what to re-scan afterwards.
    var libraryFolder: (() -> URL?)?
    /// Bracket the atomic file write with durable catalog recovery/adoption.
    /// Returning false prevents a write or reports that registration did not
    /// complete, so "Saved" is never published ahead of the catalog.
    /// The transient ID and fingerprint describe the exact serialized scratch
    /// bytes, not the higher-precision in-memory cube, so launch recovery can
    /// distinguish a completed atomic replacement from an untouched old file.
    var onWillSave: ((URL, LUTRecordID?, String) -> Bool)?
    var onSaved: ((URL) -> Bool)?
    var onSaveFailed: ((URL) -> Void)?

    /// The in-memory cube serialized to a temp .cube, so saving later is a
    /// single `FileManager.copy`. Cleared when a new derive starts.
    private var scratchURL: URL?
    private var task: Task<Void, Never>?

    // MARK: - Sheet

    func present() {
        isSheetPresented = true
    }

    /// Close the sheet. A derive still in flight is cancelled — it can run for
    /// tens of seconds and hold several hundred MB, so leaving it running after
    /// the user has walked away is never what they want.
    ///
    /// A *finished* result is kept: the user may re-open the sheet to inspect
    /// the report or save the LUT. The scratch file is cleaned up when a new
    /// derive starts.
    func dismiss() {
        isSheetPresented = false
        guard isDeriving else { return }
        task?.cancel()
        task = nil
        isDeriving = false
        progress = 0
        stage = ""
        onStatus?("Derive cancelled")
    }

    // MARK: - Deriving

    /// Name given to the derived cube, and to its scratch file. Pure and
    /// `nonisolated` — the extraction task needs it off the main actor.
    nonisolated static func derivedName(forJPG jpgURL: URL, size: Int) -> String {
        jpgURL.deletingPathExtension().lastPathComponent + "_recipe_\(size)_Rec709"
    }

    /// Build the `CubeLUT` for a completed derive.
    ///
    /// **Extracted so a test cannot build one differently.** This construction used to live inline in
    /// `derive`, and two tests stood up their own version of it with `CubeLUT(cube:size:name:)` — no
    /// `sourceURL`, and therefore a `derived://` ID where production produced a temp-file path. Both
    /// passed, and both passed *because* the fixture differed from production in exactly the field
    /// under test. One function used by both sides makes that drift impossible rather than merely
    /// discouraged.
    ///
    /// **No `sourceURL`, and that is the fix.** The scratch `.cube` is still written and still kept —
    /// that is what this coordinator's `scratchURL` is for — but the temp path must not *name* the
    /// LUT. When it did, `LUTID.isDerived` read false, the document held a path no library contains,
    /// and a finished derive resolved to nothing: the user got an ungraded preview. Worse for
    /// anything that persists a document, after the OS temp sweep that path can be reused by an
    /// unrelated file, so a stale reference resolves to the *wrong* LUT rather than to none.
    nonisolated static func makeDerivedLUT(
        cube: [SIMD3<Float>], size: Int, name: String
    ) -> CubeLUT {
        CubeLUT(cube: cube, size: size, name: name, category: "Derived")
    }

    /// Derive a LUT from a (RAW, JPG) pair. The result lives in `derivedLUT`
    /// and `report` until the user explicitly saves it.
    func derive(rawURL: URL, jpgURL: URL) {
        guard !isDeriving else { return }
        isDeriving = true
        progress = 0
        stage = "Starting…"
        derivedLUT = nil
        report = nil
        onStatus?("Deriving recipe…")

        // Clean up any previous scratch file.
        if let previous = scratchURL {
            try? FileManager.default.removeItem(at: previous)
            scratchURL = nil
        }

        task = Task.detached {
            do {
                let result = try RecipeExtractor.derive(
                    rawURL: rawURL,
                    jpgURL: jpgURL,
                    progress: { progress, stage in
                        Task { @MainActor in
                            self.progress = progress
                            self.stage = stage
                        }
                    },
                    isCancelled: { Task.isCancelled }
                )

                let name = Self.derivedName(forJPG: jpgURL, size: result.size)
                let scratch = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(name).cube")
                try CubeLUT.write(cube: result.cube, size: result.size, title: name, to: scratch)

                let lut = Self.makeDerivedLUT(cube: result.cube, size: result.size, name: name)

                await MainActor.run {
                    self.derivedLUT = lut
                    self.report = result.report
                    self.scratchURL = scratch
                    self.isDeriving = false
                    self.progress = 1.0
                    self.stage = "Done"
                    self.onStatus?("Recipe derived (\(result.report.sampleCount) samples)")
                    self.onDerived?(lut)
                }
            } catch is CancellationError {
                // Nothing to undo: the scratch .cube is only written after
                // `derive` returns, and `dismiss()` — the only thing that
                // cancels — has already reset the UI state.
                return
            } catch {
                await MainActor.run {
                    self.isDeriving = false
                    self.progress = 0
                    self.stage = ""
                    self.onError?("Derive failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Saving

    /// Ask where to put the derived LUT, defaulting to the configured LUT
    /// folder so the library picks it up on the next scan.
    func saveDialog() {
        guard let lut = derivedLUT, scratchURL != nil else {
            onStatus?("No derived LUT to save")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Save Derived LUT"
        if let cubeType = UTType(filenameExtension: "cube") {
            panel.allowedContentTypes = [cubeType]
        }
        panel.nameFieldStringValue = lut.name + ".cube"
        if let folder = libraryFolder?() {
            panel.directoryURL = folder
        }

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            if try save(to: destination) {
                onStatus?("Saved: \(destination.lastPathComponent)")
            }
        } catch {
            onError?("Save failed: \(error.localizedDescription)")
        }
    }

    /// Complete the save contract: persist recovery intent, atomically write
    /// the file, then publish success only if catalog adoption also succeeds.
    @discardableResult
    func save(to destination: URL) throws -> Bool {
        guard let scratchURL else { throw SaveError.nothingToSave }
        let serialized = try CubeLUT(url: scratchURL, category: "Derived")
        if let onWillSave,
           onWillSave(destination, derivedLUT?.lutID, serialized.contentHash) == false {
            return false
        }
        do {
            try performSave(to: destination)
        } catch {
            onSaveFailed?(destination)
            throw error
        }
        return onSaved?(destination) ?? true
    }

    /// Atomically replace `destination` with the scratch bytes. `Data.write`
    /// stages a sibling temporary file and renames it into place, avoiding the
    /// delete-then-copy gap that could lose a known LUT on interruption.
    /// Panel-free, so tests can drive it directly.
    func performSave(to destination: URL) throws {
        guard let scratch = scratchURL else { throw SaveError.nothingToSave }
        let data = try Data(contentsOf: scratch)
        try data.write(to: destination, options: .atomic)
    }

    enum SaveError: LocalizedError {
        case nothingToSave

        var errorDescription: String? {
            switch self {
            case .nothingToSave: return "No derived LUT to save"
            }
        }
    }

    // MARK: - Testing seam

    /// Install a derived result without running the extractor, so the save path
    /// can be tested without a RAW fixture.
    func setScratchResult(lut: CubeLUT, report: RecipeReport?, scratchURL: URL) {
        self.derivedLUT = lut
        self.report = report
        self.scratchURL = scratchURL
    }
}
