import Foundation
import CoreImage
import AppKit
import Observation

/// Owns everything about writing images to disk: the single export, the batch
/// run, and the naming rules both share.
///
/// Each operation is split in two — a `perform…` core that takes an explicit
/// destination, and a thin `…Dialog` wrapper that runs the panel and calls it.
/// The panels can't run headless, so that seam is what makes export testable
/// at all.
///
/// Status and error text goes out through `onStatus`/`onError` rather than
/// being written here: the status bar and the alert belong to `AppViewModel`,
/// and this type has no business deciding how a failure is presented.
///
/// **Step 6 cut both paths over to `RenderEngine`.** Neither one takes a `CIImage` any more: they
/// take the `ImageSource` and the `EditDocument` and ask the engine to encode at `.full`. That is
/// what makes an export honour develop and adjustments — before, the single path graded a
/// full-resolution neutral decode with only the LUT, and the batch path independently reproduced the
/// same omission with its own `loadImage` + `apply`. Two places to forget the same thing is exactly
/// why the fix is "hand the document to the one funnel" rather than "remember to grade twice".
///
/// It also removes the `[processor]` capture into `Task.detached` that §2 of the spec flags: the
/// non-`Sendable` singleton is gone from both loops, and the work now happens inside the actor that
/// owns the context.
@Observable
@MainActor
final class ExportCoordinator {

    var format: ExportFormat = .jpeg
    private(set) var isExporting: Bool = false
    /// Progress (0...1) during a multi-image "Export All" run.
    private(set) var batchProgress: Double = 0

    @ObservationIgnored var onStatus: ((String) -> Void)?
    @ObservationIgnored var onError: ((String) -> Void)?

    /// The renderer. `any RenderEngining` rather than the concrete actor for the same reason
    /// `AppViewModel` holds one: a test can then assert *what was asked to be encoded* — which
    /// document, at which scale, in which format — without a GPU or a file on disk.
    private let engine: any RenderEngining

    init(engine: any RenderEngining = RenderEngine.shared) {
        self.engine = engine
        // Launch default from Settings (⌘,). Read once: see `AppPreference`.
        if let raw = UserDefaults.standard.string(forKey: AppPreference.defaultExportFormat),
           let format = ExportFormat(rawValue: raw) {
            self.format = format
        }
    }

    /// Quality for the lossy encoders. Hardcoded as it always was; a UI for it is Step 12's
    /// export descriptor.
    private static let exportQuality: CGFloat = 0.95

    // MARK: - Types

    /// One image to export, reduced to the `Sendable` bits. Deliberately not
    /// `ImageCollection.Item`: that carries an `NSImage` thumbnail we don't
    /// want crossing an actor boundary.
    struct BatchItem: Sendable {
        let url: URL?
        let data: Data?
        let name: String

        init(url: URL?, data: Data?, name: String) {
            self.url = url
            self.data = data
            self.name = name
        }
    }

    struct BatchOutcome: Equatable {
        let exported: Int
        let failed: Int
        let total: Int
    }

    // MARK: - Naming

    // Pure and `nonisolated`: the batch loop needs them off the main actor.

    /// `‹photo›_‹LUT name›` — the shared stem for both export paths. Spaces in
    /// the LUT name become underscores so the result is shell-friendly.
    nonisolated static func exportBaseName(source: String, lut: CubeLUT?) -> String {
        let suffix = lut.map { "_" + $0.name.replacingOccurrences(of: " ", with: "_") } ?? ""
        return source + suffix
    }

    nonisolated static func defaultFileName(
        source: String,
        lut: CubeLUT?,
        format: ExportFormat
    ) -> String {
        exportBaseName(source: source, lut: lut) + "." + format.fileExtension
    }

    // MARK: - Single export

    /// Ask for a destination, then export. `suggestedBaseName` is the stem; the
    /// extension comes from the current format.
    func exportDialog(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        suggestedBaseName: String
    ) {
        let panel = NSSavePanel()
        panel.title = "Export"
        panel.nameFieldStringValue = suggestedBaseName + "." + format.fileExtension
        panel.allowedContentTypes = [format.utType]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        performExport(source: source, document: document, lut: lut, to: url)
    }

    /// Encode `document` over `source` at full resolution and write it to `url`.
    /// Panel-free, so tests can drive it directly.
    ///
    /// The encode happens inside the engine; the *write* deliberately does not. File I/O is not the
    /// GPU's business, and keeping it out here means the actor never touches the sandbox or a
    /// half-written file (`RenderEngining.encode` returns `Data` for exactly this reason).
    func performExport(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        to url: URL
    ) {
        isExporting = true
        onStatus?("Exporting...")

        Task { [engine, format] in
            do {
                let data = try await engine.encode(
                    source: source, document: document, lut: lut, scale: .full,
                    format: format, quality: Self.exportQuality, space: .current
                )
                try await Self.write(data, to: url)
                self.isExporting = false
                self.onStatus?("Exported: \(url.lastPathComponent)")
            } catch {
                self.isExporting = false
                self.onError?("Export failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Batch export

    /// Ask for a folder, then render `document` over every item and write the
    /// results into it.
    func batchExportDialog(items: [BatchItem], document: EditDocument, lut: CubeLUT?) {
        guard !items.isEmpty else {
            onStatus?("Import a set of images first (Export All works on the filmstrip)")
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.prompt = "Export Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        Task { await performBatchExport(items, document: document, lut: lut, to: folder) }
    }

    /// The batch core. Renders each item through the engine with progress; an
    /// image that fails to decode or encode is counted and skipped, never
    /// aborting the run. Returns the tally so callers (and tests) can assert on it.
    ///
    /// The same `document` for every image, which is what the app means today: one look auditioned
    /// across a folder (§8.4). Per-image documents arrive with the `EditDocumentStore` in Step 11,
    /// and this loop is the one place that will have to look them up.
    ///
    /// **Not memoized, deliberately.** The engine's developed-source memo only covers preview
    /// scales; a batch renders N *different* images at `.full`, so a memo would hold one
    /// full-resolution intermediate per item and never see a hit. See §6.
    @discardableResult
    func performBatchExport(
        _ items: [BatchItem],
        document: EditDocument,
        lut: CubeLUT?,
        to folder: URL
    ) async -> BatchOutcome {
        isExporting = true
        batchProgress = 0
        let total = items.count
        onStatus?("Exporting 0 of \(total)…")

        let fmt = format
        var exported = 0
        var failed = 0

        for (index, item) in items.enumerated() {
            if let source = Self.source(for: item) {
                let base = Self.exportBaseName(source: item.name, lut: lut)
                let dest = uniqueExportURL(in: folder, base: base, ext: fmt.fileExtension)
                do {
                    let data = try await engine.encode(
                        source: source, document: document, lut: lut, scale: .full,
                        format: fmt, quality: Self.exportQuality, space: .current
                    )
                    try await Self.write(data, to: dest)
                    exported += 1
                } catch {
                    failed += 1
                }
            } else {
                failed += 1
            }

            let done = index + 1
            batchProgress = Double(done) / Double(total)
            onStatus?("Exporting \(done) of \(total)…")
        }

        let outcome = BatchOutcome(exported: exported, failed: failed, total: total)
        isExporting = false
        batchProgress = 0
        onStatus?(Self.summary(for: outcome, folder: folder))
        return outcome
    }

    /// Write off the main actor.
    ///
    /// Both loops are `@MainActor` now that the encode happens inside `RenderEngine` rather than in a
    /// detached task — but a full-resolution 16-bit TIFF is hundreds of megabytes, and handing that
    /// to the main thread would stutter the window for exactly as long as the disk takes. `Data` and
    /// `URL` are `Sendable`, so getting it off costs nothing.
    private static func write(_ data: Data, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) { try data.write(to: url) }.value
    }

    /// How to reproduce a batch item, as an `ImageSource`.
    ///
    /// `nativeExtent` is `.zero` because a batch export never measures one: the extent exists so a
    /// *preview* can compute a downscale factor without decoding twice, and `RenderScale.full`
    /// returns 1.0 regardless. The pipeline reads the decoder's own size anyway, never this field
    /// (`RenderPipeline.developedSource`), so decoding every file up front just to fill it in would
    /// be pure cost.
    private static func source(for item: BatchItem) -> ImageSource? {
        if let url = item.url { return ImageSource(url: url, nativeExtent: .zero) }
        if let data = item.data { return ImageSource(data: data, nativeExtent: .zero) }
        return nil
    }

    /// The line shown when a batch finishes.
    nonisolated static func summary(for outcome: BatchOutcome, folder: URL) -> String {
        let destination = folder.lastPathComponent
        if outcome.failed == 0 {
            let plural = outcome.exported == 1 ? "" : "s"
            return "Exported \(outcome.exported) image\(plural) to \(destination)"
        }
        return "Exported \(outcome.exported) of \(outcome.total) (\(outcome.failed) failed) to \(destination)"
    }
}

// MARK: - Naming helpers

/// A non-colliding `base.ext` URL inside `folder`, appending " 2", " 3", …
/// when a file of that name already exists. Free function (not `@MainActor`)
/// so it can be called from the off-actor batch export task.
func uniqueExportURL(in folder: URL, base: String, ext: String) -> URL {
    let fm = FileManager.default
    var candidate = folder.appendingPathComponent("\(base).\(ext)")
    var n = 2
    while fm.fileExists(atPath: candidate.path) {
        candidate = folder.appendingPathComponent("\(base) \(n).\(ext)")
        n += 1
    }
    return candidate
}
