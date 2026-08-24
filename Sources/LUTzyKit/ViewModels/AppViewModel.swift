import Foundation
import CoreImage
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Central state for the LUTzy app.
@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - Published state

    @Published var sourceImage: CIImage?
    @Published var sourceName: String = ""
    @Published var sourceSize: CGSize = .zero
    @Published var sourceURL: URL?

    /// **The look, as a value.** Phase 2's spine: everything the user has chosen lives here, and the
    /// preview is rebuilt from it rather than from a baked image (`docs/PHASE2_SPEC.md` §3).
    ///
    /// Kept across image opens rather than reset, per §8.4 — auditioning one look across a folder is
    /// the common case, and that is what the app already did.
    ///
    /// That reasoning covers the LUT and its intensity; it does not cover `rawDevelop`, whose fields
    /// are per-file decoder defaults, not a portable look. Step 10a is the first thing that writes to
    /// `rawDevelop`, and carrying it forward means a value set on one RAW silently overrides the next
    /// RAW's own probed as-shot seed. Known, and deliberately deferred to Step 11 — see §8.4 for the
    /// worked example and why that step is the right place to settle it.
    @Published private(set) var document = EditDocument()

    /// How to reproduce the open image. Held instead of a decoded `CIImage` because a RAW has to be
    /// re-developed to honour `document.rawDevelop` (§4.2).
    /// Internal rather than private only because `AppViewModel+Compare` renders the
    /// same source into its grid cells, and `private` does not cross a file.
    var imageSource: ImageSource?

    /// What the open image's RAW decoder can do, and where its own defaults sit. `nil` for a
    /// standard image, which has no develop stage at all — **and also `nil` while the probe is still
    /// running on a RAW**, which is why the panel switches on `developPanelState` rather than on
    /// this. See that property.
    ///
    /// Probed once per open rather than per render: the probe builds a `CIRAWFilter`, which measures
    /// ~25 ms on a 30 MB DNG. Not memoized across images — one entry would save that on returning to
    /// an image, at the cost of another cache whose invalidation nobody will remember.
    @Published private(set) var rawCapabilities: RAWCapabilities?

    /// What the develop panel should be showing right now. **Three states, not two.**
    ///
    /// `rawCapabilities` is `nil` in two situations that mean opposite things, and the panel used to
    /// treat them as one. `refreshCapabilities()` clears it **synchronously** on every open and
    /// refills it 25–170 ms later, so a RAW opened with the Develop tab already showing spent the
    /// whole probe reading "No develop stage — Develop controls come from the RAW decoder. This image
    /// is already rendered." That is a false statement about the file, and because `inspectorTab` is
    /// not reset on open it was shown again on every ←/→ step through a folder of RAWs.
    ///
    /// Deriving the state here rather than in the view is what makes it testable: this repo has no
    /// SwiftUI view tests, so a distinction that lives only in a `ViewBuilder` cannot be asserted.
    /// `DevelopInspectorView` is a `switch` over this value and nothing else.
    ///
    /// This — rather than a widened `imageSource` — is the whole of what the panel needs from the
    /// source: not the backing bytes, not the native extent, only whether a develop stage exists at
    /// all. See `sourceIsRAW` for the widening that does happen, and why it is a `Bool`.
    var developPanelState: DevelopPanelState {
        DevelopPanelState(sourceIsRAW: sourceIsRAW, capabilities: rawCapabilities)
    }

    /// Whether the open image goes through the RAW decoder at all.
    ///
    /// **Widened from `private` deliberately, and narrowly.** `imageSource` itself stays `private`:
    /// the develop panel has no business with the backing bytes or the native extent, and the one
    /// fact it needs — is there a decode stage that could offer develop controls — is a `Bool`.
    /// Publishing the `Bool` instead of the struct keeps the reason for the widening legible and
    /// stops anything else reaching through it. It is also the input the state mapping is tested
    /// against directly.
    ///
    /// Not `@Published`: it only ever changes inside `load()`, which writes several `@Published`
    /// properties in the same main-actor turn (`sourceImage` among them), so any view observing this
    /// view model is already being invalidated when it moves.
    var sourceIsRAW: Bool { imageSource?.kind == .raw }

    /// The three states of the develop panel. See `AppViewModel.developPanelState`.
    enum DevelopPanelState: Equatable, Sendable {
        /// Not a RAW (or nothing open): there is no develop stage to offer, and saying so is honest.
        case noDevelopStage
        /// A RAW whose capability probe has not landed yet. The controls are coming, so the panel
        /// must not claim there are none.
        case probing
        /// A RAW, probed. The panel draws `capabilities.availableControls`.
        case ready(RAWCapabilities)

        /// **The mapping, in one place, as a pure function of two inputs.** Written as an
        /// initializer rather than inlined into the computed property so the whole table — two
        /// inputs, three outcomes — can be asserted on any machine, including CI, which has no RAW
        /// to open (`DevelopInspectorTests.testThePanelStateMappingCoversAllThreeStates`).
        init(sourceIsRAW: Bool, capabilities: RAWCapabilities?) {
            if let capabilities {
                self = .ready(capabilities)
            } else {
                self = sourceIsRAW ? .probing : .noDevelopStage
            }
        }
    }

    private var capabilitiesTask: Task<Void, Never>?
    private var developTask: Task<Void, Never>?

    /// Whether any call since the last fired render changed `rawDevelop`.
    ///
    /// A coalesced burst of `updateDocument(debounced:)` calls shares one `developTask` — only the
    /// last call in the burst survives to fire. If that flag were captured per call (as it was
    /// before this existed), an earlier call in the burst that touched `rawDevelop` would have its
    /// `developChanged == true` thrown away the moment a later call in the same burst cancelled its
    /// task, even though the comparison baseline genuinely needs to move. Accumulating the flag here
    /// instead — OR'd in by every call, read and cleared by whichever call actually fires the render —
    /// means the baseline re-renders if *any* call in the burst touched develop, not just the last.
    private var pendingDevelopChange = false

    /// LUTs a document can reference that no folder scan produces — a freshly derived LUT, and the
    /// file it becomes once saved. See `DerivedLUTRegistry`; this is the Step 9 replacement for the
    /// single `scratchLUT` slot that stood here.
    private var derivedRegistry = DerivedLUTRegistry()

    /// **Shim.** The document stores a `LUTID`; views still want the LUT. Resolution is deliberately
    /// a fresh lookup rather than a cached object — `LUTID` is a file path precisely so a rescan
    /// cannot break it (§4.3).
    var selectedLUT: CubeLUT? { resolvedLUT(document.lut.lutID) }

    /// **Shim.** Reads through to the document so the toolbar slider keeps working unchanged.
    var lutIntensity: Double { document.lut.intensity }

    /// Whether the A/B comparison — the split view and the Space-hold — has anything to show.
    ///
    /// **Not `selectedLUT != nil`**, which is what this was until Step 10b. That was defensible while
    /// a LUT was the only thing that could change the picture; the Adjust panel made it wrong, and an
    /// image with exposure pushed two stops and no LUT selected had a dead V key and a dead Space bar.
    /// `docs/PHASE2_SPEC.md` §8.5 recorded this as open.
    ///
    /// **Not `document != document.originalForComparison` either**, which is what Step 10b first
    /// reached for: compare the document against its own baseline rather than enumerate the
    /// look-bearing fields, and the rule "stays correct the next time the document grows a field."
    /// That reasoning is wrong for a LUT at 0% intensity — `LUTSettings.isIdentity` treats it as
    /// contributing nothing, but the plain `!=` sees `lutID` still set and calls the document
    /// non-neutral, so the gate opened a split view of two pixel-identical halves. Exactness beat the
    /// "survives a new field" property. The cost is real: the next look-bearing field added to
    /// `EditDocument` must be added to this expression by hand, or this comment starts lying the same
    /// way the old one did.
    ///
    /// A **develop-only** edit correctly reads `false` — `originalForComparison` keeps `rawDevelop`
    /// and strips only `adjustments` and the LUT, so both halves would render the same picture.
    ///
    /// `adjustments.isEmpty` would have been a sound stand-in for "no adjustment is active" only
    /// because the array is sparse — `AdjustmentControl.setting(_:in:)` never stores an identity node, a
    /// claim `AdjustmentControlTests` pins. `adjustments.allSatisfy(\.isIdentity)` needs no such
    /// precondition: a stray identity node reads exactly the same as no node at all, so it is written
    /// this exact way, rather than the cheaper `isEmpty`, for the same exactness reason as the
    /// paragraph above — it stays correct even if the sparse invariant is ever violated, which matters
    /// once Step 11's undo path can restore a document that arrived by decoding rather than by a
    /// slider write.
    var isComparisonAvailable: Bool {
        !document.adjustments.allSatisfy(\.isIdentity) || !document.lut.isIdentity
    }

    @Published var previewNSImage: NSImage?
    @Published var originalPreviewNSImage: NSImage?
    @Published var isShowingOriginal: Bool = false
    @Published var isSideBySide: Bool = true

    // MARK: - Comparison grid (see AppViewModel+Compare)

    /// How the preview area is divided. Stored here rather than in the
    /// extension because Swift extensions cannot hold stored properties.
    @Published var comparisonLayout: ComparisonLayout = .split
    /// One LUT reference per cell, in cell order. `nil` is a deliberate choice —
    /// the ungraded picture — not an empty slot.
    @Published var cellLUTIDs: [LUTID?] = []
    /// The rasterized cells, index-parallel to `cellLUTIDs`.
    @Published var cellImages: [NSImage?] = []
    /// The amplified difference between the base cell and the current look.
    /// Only built while the difference layout is on screen.
    @Published var diffNSImage: NSImage?
    /// One in-flight render per cell, so re-picking one cell cancels one render
    /// rather than the whole sheet.
    var cellTasks: [Int: Task<Void, Never>] = [:]
    /// What V returns to. Remembered so a glance at the single view does not
    /// cost the user their 3×3.
    var lastComparisonLayout: ComparisonLayout = .split

    /// Inspector visibility. Computing the histogram is gated on this — plus on the Info tab being
    /// the one on screen — so we don't tally pixels for a panel nobody's looking at.
    @Published var isInspectorPresented: Bool = false {
        didSet { if isInspectorPresented { updateHistogram() } }
    }

    /// Which half of the inspector is showing.
    ///
    /// The histogram lives on `.info` only, so this gates it exactly as `isInspectorPresented` does:
    /// an open inspector showing Develop is as much "a panel nobody's looking at" as a closed one,
    /// and without this every settled render of a develop drag would tally an off-screen histogram.
    /// Switching **back** recomputes, or the panel would return blank (or stale) after a detour
    /// through Develop.
    @Published var inspectorTab: InspectorTab = .info {
        didSet { if inspectorTab == .info { updateHistogram() } }
    }

    enum InspectorTab: String, CaseIterable, Sendable {
        case info, develop, adjust
        var title: String {
            switch self {
            case .info: return "Info"
            case .develop: return "Develop"
            case .adjust: return "Adjust"
            }
        }
    }
    /// Source-folder file browser panel visibility.
    @Published var isSourceBrowserPresented: Bool = false
    /// EXIF/TIFF/GPS metadata of the loaded image, read at load time.
    @Published var metadata: ImageMetadata = ImageMetadata()
    /// Histogram of the currently displayed image (graded result, or original
    /// while comparing). `nil` until computed / when no image is loaded.
    @Published var histogram: HistogramData?
    private var histogramTask: Task<Void, Never>?

    @Published var isLoading: Bool = false
    @Published var statusMessage: String = "Open an image to get started"

    /// Non-nil when a hard failure should be surfaced as a dismissible alert.
    /// Bound to an `.alert` in ContentView; cleared when the user dismisses it.
    @Published var errorMessage: String?

    @Published var isPhotosPickerPresented: Bool = false

    // MARK: - Owned state

    let library = LUTLibrary()

    /// Measured and typed tags for the library, keyed by LUT content.
    let tags = LUTTagStore()

    /// Tags a LUT must carry to be listed. Empty means no filtering.
    @Published var tagFilter: Set<String> = []
    let collection = ImageCollection()
    /// Writing images to disk — the single export, the batch run, and naming.
    /// Shares this view model's engine, so an export renders through the same funnel the preview does.
    let export: ExportCoordinator
    /// The "Derive LUT from JPG" flow and its scratch-until-saved result.
    let derive = DeriveCoordinator()

    // Convenience passthroughs so views and the menu don't have to know which
    // collaborator owns a given piece of state.
    var isExporting: Bool { export.isExporting }
    var exportFormat: ExportFormat {
        get { export.format }
        set { export.format = newValue }
    }

    /// The renderer. An `any RenderEngining` rather than the concrete actor so a test can drive the
    /// preview flow without a GPU — the reason Step 4 introduced the protocol.
    /// See `imageSource` — the comparison grid renders through the same engine.
    let engine: any RenderEngining
    private var loadTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var originalPreviewTask: Task<Void, Never>?
    private var intensityTask: Task<Void, Never>?
    private var cancellables: [AnyCancellable] = []

    // MARK: - Init

    init(engine: any RenderEngining = RenderEngine.shared) {
        self.engine = engine
        self.export = ExportCoordinator(engine: engine)

        // Forward nested ObservableObject changes so SwiftUI views update.
        for child in [
            library.objectWillChange.eraseToAnyPublisher(),
            collection.objectWillChange.eraseToAnyPublisher(),
            export.objectWillChange.eraseToAnyPublisher(),
            derive.objectWillChange.eraseToAnyPublisher(),
        ] {
            cancellables.append(child.sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            })
        }

        wireCoordinators()
        library.restoreFolder()

        // Restore a previously-chosen source folder and open its first image.
        // Both the LUT scan above and this one run asynchronously, so the
        // window paints immediately and fills in as the scans land.
        if collection.restoreSourceFolder() {
            isSourceBrowserPresented = true
            openFirstImageWhenScanned()
        }
    }

    /// Point the coordinators' status/error output at this view model, which
    /// owns the status bar and the alert. They report *what* happened; deciding
    /// how to show it stays here.
    private func wireCoordinators() {
        // A rescan can mean the bytes behind an unchanged `LUTID` have changed — a path is the
        // identity, so a `.cube` replaced in place keeps it. Drop the engine's cube filters rather
        // than go on serving the old cube. Wired here, before `restoreFolder()` runs below, so the
        // launch scan is covered too.
        library.onScanned = { [weak self] in
            guard let self else { return }
            let engine = self.engine
            Task { await engine.invalidateLUTCache() }
            // Measure whatever the scan found that has not been measured
            // before. Typed tags are never disturbed by this — see LUTTagStore.
            Task { await self.tags.index(self.library.allLUTs) }
        }

        export.onStatus = { [weak self] in self?.statusMessage = $0 }
        export.onError = { [weak self] in self?.presentError($0) }

        derive.onStatus = { [weak self] in self?.statusMessage = $0 }
        derive.onError = { [weak self] in self?.presentError($0) }
        derive.onDerived = { [weak self] lut in
            // Preview the new look immediately, if there's something to see.
            guard let self, self.sourceImage != nil else { return }
            self.selectLUT(lut)
        }
        derive.libraryFolder = { [weak self] in self?.library.folderURL }
        derive.onSaved = { [weak self] destination in
            guard let self else { return }
            self.adoptSavedLUT(at: destination)
            // Re-scan so the new entry appears in the sidebar.
            guard let folder = self.library.folderURL else { return }
            self.library.scan(folder)
        }
    }

    /// Follow a derived LUT from memory onto disk.
    ///
    /// Saving is the moment a derived LUT becomes durable, so it is the moment its reference should
    /// become durable too. A `derived://` ID resolves only through the registry and cannot survive a
    /// relaunch; the path the user just chose is what a fresh launch would resolve and what the next
    /// library scan will hold. So the document is re-pointed at it.
    ///
    /// **The saved LUT is re-parsed from the file rather than aliased from memory.** `cubeFileContents`
    /// writes `%.6f`, so what landed on disk is a rounded copy of the in-memory table. Aliasing the
    /// full-precision cube to the saved path would leave the app rendering something a fresh launch
    /// could not reproduce from that same file — a divergence of exactly the kind this migration
    /// exists to close. The file is authoritative because the file is what persists.
    ///
    /// It is registered as well as re-pointed, because `onSaved` only triggers a rescan when the
    /// destination is inside the configured LUT folder. Saving anywhere else would otherwise re-point
    /// the document at something nothing can resolve.
    ///
    /// Only the LUT that was *just saved* moves. The user can derive, pick something else from the
    /// sidebar, and then save the derive from the still-open sheet; that must not steal the selection.
    private func adoptSavedLUT(at destination: URL) {
        guard let saved = try? CubeLUT(url: destination, category: "Derived") else { return }
        derivedRegistry.register(saved)

        guard let current = document.lut.lutID, current == derive.derivedLUT?.lutID else { return }
        document.lut.lutID = saved.lutID
        schedulePreview()
    }

    /// Open the first image of the source folder once its scan completes.
    private func openFirstImageWhenScanned() {
        Task {
            await collection.scanCompletion()
            guard let first = collection.items.first, let fileURL = first.url else { return }
            openImage(url: fileURL)
        }
    }

    // MARK: - Error presentation

    /// Surface a user-facing error both as a dismissible alert and in the
    /// status bar. Used for hard failures (load / export / derive / save);
    /// transient preview hiccups stay status-bar-only to avoid alert spam.
    private func presentError(_ message: String) {
        statusMessage = message
        errorMessage = message
    }

    // MARK: - Image loading

    func openImage(url: URL) {
        load(name: url.lastPathComponent, url: url, data: nil)
    }

    /// Decode on the cooperative background executor, then transfer the newly-created Core Image
    /// graph to the main actor. `sending` describes that one-way ownership transfer without lying
    /// that `CIImage` is generally safe to share between isolation domains.
    private nonisolated static func decode(
        name: String,
        url: URL?,
        data: Data?
    ) async throws -> sending CIImage {
        if let url {
            return try ImageDecoder.load(from: url)
        }
        if let data {
            return try ImageDecoder.load(from: data, name: name)
        }
        throw ImageError.cannotLoad(name)
    }

    /// Decode an image **off the main actor**, then publish it and render the
    /// previews. RAW demosaicing is expensive enough (hundreds of ms) that
    /// doing it inline would freeze the window on every ←/→ step.
    private func load(name: String, url: URL?, data: Data?) {
        loadTask?.cancel()
        previewTask?.cancel()
        originalPreviewTask?.cancel()
        intensityTask?.cancel()
        capabilitiesTask?.cancel()
        developTask?.cancel()
        // A pending develop flag describes the image being left; it must not survive onto whatever
        // opens next, or an unrelated first edit on the new image would render a comparison baseline
        // for develop settings that were never actually touched on it.
        pendingDevelopChange = false

        isLoading = true
        statusMessage = "Loading \(name)..."

        loadTask = Task {
            do {
                let ci = try await Self.decode(name: name, url: url, data: data)
                guard !Task.isCancelled else { return }

                self.sourceImage = ci
                self.sourceURL = url
                self.sourceName = name
                self.sourceSize = ci.extent.size
                // The renderer works from the file, not the decoded image, so a RAW can be
                // re-developed per render. `nativeExtent` comes from the decode we just did.
                if let url {
                    self.imageSource = ImageSource(url: url, nativeExtent: ci.extent.size)
                    self.metadataFinding = nil
                } else if let data {
                    self.imageSource = ImageSource(data: data, nativeExtent: ci.extent.size)
                    self.metadataFinding = nil
                } else {
                    self.imageSource = nil
                }
                self.statusMessage = "\(name)  \(Int(ci.extent.width))\u{00D7}\(Int(ci.extent.height))"
                self.isLoading = false

                self.scheduleOriginalPreview()
                self.schedulePreview()
                self.refreshMetadata(url: url, data: data)
                self.refreshCapabilities()
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoading = false
                self.presentError("Error: \(error.localizedDescription)")
            }
        }
    }

    func openImageDialog() {
        let panel = NSOpenPanel()
        panel.title = "Open Image"
        panel.allowedContentTypes = ImageDecoder.supportedTypes
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            collection.clear()
            openImage(url: url)
        }
    }

    // MARK: - Photo import

    func openImage(data: Data, name: String) {
        load(name: name, url: nil, data: data)
    }

    func importFromPhotos() {
        isPhotosPickerPresented = true
    }

    func importPhotosData(_ items: [(name: String, data: Data)]) {
        collection.addFromData(items)
        if let first = items.first {
            openImage(data: first.data, name: first.name)
        }
    }

    /// Choose a folder to use as the persistent image source, scan it (incl.
    /// subfolders), reveal the file browser, and open the first image.
    func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Source Folder"
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            openSourceFolder(url: url)
        }
    }

    /// Adopt `url` as the source folder (persisted), reveal the browser, and
    /// open its first image. Shared by the menu/toolbar action and folder drops.
    func openSourceFolder(url: URL) {
        collection.setSourceFolder(url)
        isSourceBrowserPresented = true
        openFirstImageWhenScanned()
    }

    func toggleSourceBrowser() {
        isSourceBrowserPresented.toggle()
    }

    /// Re-scan the current source folder for added/removed files.
    func refreshSource() {
        collection.refresh()
    }

    func selectCollectionImage(at index: Int) {
        guard collection.items.indices.contains(index) else { return }
        collection.selectedIndex = index
        let item = collection.items[index]

        if let url = item.url {
            openImage(url: url)
        } else if let data = item.imageData {
            openImage(data: data, name: item.displayName)
        }
    }

    func selectPreviousImage() {
        guard collection.isActive else { return }
        let prev = collection.selectedIndex
        collection.selectPrevious()
        if collection.selectedIndex != prev {
            selectCollectionImage(at: collection.selectedIndex)
        }
    }

    func selectNextImage() {
        guard collection.isActive else { return }
        let prev = collection.selectedIndex
        collection.selectNext()
        if collection.selectedIndex != prev {
            selectCollectionImage(at: collection.selectedIndex)
        }
    }

    // MARK: - LUT selection

    func selectLUT(_ lut: CubeLUT?) {
        // A derived LUT is in no library, so nothing but the registry can resolve it later. Remember
        // it rather than replacing the last one: a document made now must still resolve after the
        // user derives again.
        if let lut, lut.lutID.isDerived { derivedRegistry.register(lut) }
        document.lut.lutID = lut?.lutID
        applyLUT()
    }

    /// Mutate the document and re-render.
    ///
    /// The only way to reach `rawDevelop` and `adjustments` today. The inspector that will drive them
    /// from the UI is Step 10; until it exists this is the seam those fields are tested through, and
    /// it is what the inspector will call. Keeping `document` `private(set)` behind it means every
    /// mutation goes through one place that knows to re-render.
    func updateDocument(_ transform: (inout EditDocument) -> Void) {
        updateDocument(debounced: false, transform)
    }

    /// Mutate the document and re-render, optionally coalescing a burst of edits into one render.
    ///
    /// **`debounced: true` is for continuous controls only** — a slider drag, where the user
    /// produces tens of values per second and only the one they settle on matters. `PHASE2_SPEC.md`
    /// §6 is explicit that open and filmstrip navigation must stay immediate, and discrete controls
    /// (toggles, resets) should too: a checkbox that lagged 60 ms would feel broken.
    ///
    /// The document itself is updated **immediately** either way. Only the render is deferred, so
    /// the control stays glued to the pointer and `document` is always the truth. Deferring the
    /// document as well would mean a read-back mid-drag saw a stale value.
    ///
    /// Worth the machinery because a develop change costs *two* renders — `scheduleOriginalPreview`
    /// as well as `schedulePreview`, since the comparison baseline moves with develop.
    func updateDocument(debounced: Bool, _ transform: (inout EditDocument) -> Void) {
        var updated = document
        transform(&updated)
        guard updated != document else { return }

        let developChanged = updated.rawDevelop != document.rawDevelop
        document = updated
        // OR'd in rather than assigned: a call earlier in a coalesced burst may have changed
        // `rawDevelop` even though *this* call didn't, and only the last call's task survives to
        // fire (see `pendingDevelopChange`'s doc comment).
        pendingDevelopChange = pendingDevelopChange || developChanged

        developTask?.cancel()

        guard debounced else {
            let shouldRenderBaseline = pendingDevelopChange
            pendingDevelopChange = false
            if shouldRenderBaseline { scheduleOriginalPreview() }
            schedulePreview()
            return
        }

        developTask = Task {
            try? await Task.sleep(for: .milliseconds(Self.intensityDebounceMs))
            guard !Task.isCancelled else { return }
            if self.pendingDevelopChange {
                self.pendingDevelopChange = false
                self.scheduleOriginalPreview()
            }
            self.schedulePreview()
        }
    }

    /// Resolve a document's LUT reference: the registry first, then the library. A miss returns
    /// `nil`, and the render simply comes out ungraded — see `RenderPipeline.buildImage`.
    ///
    /// Registry first because it is the narrower answer. Its only entries are derived LUTs and the
    /// files they were saved to, so a hit there is always the more specific one; for a saved LUT the
    /// library holds an identical value under the same ID, and `CubeLUT` compares by ID, so which
    /// copy wins is not observable.
    private func resolvedLUT(_ id: LUTID?) -> CubeLUT? {
        guard let id else { return nil }
        if let registered = derivedRegistry.lut(for: id) { return registered }
        return library.allLUTs.first(matching: id)
    }

    func selectPreviousLUT() {
        guard let current = selectedLUT,
              let idx = library.allLUTs.firstIndex(of: current),
              idx > 0 else { return }
        selectLUT(library.allLUTs[idx - 1])
    }

    func selectNextLUT() {
        guard let current = selectedLUT else {
            if let first = library.allLUTs.first { selectLUT(first) }
            return
        }
        guard let idx = library.allLUTs.firstIndex(of: current),
              idx < library.allLUTs.count - 1 else { return }
        selectLUT(library.allLUTs[idx + 1])
    }

    // MARK: - LUT application

    private func applyLUT() {
        schedulePreview()
    }

    /// What space the open image is treated as, for a V-Log LUT.
    var sourceSpace: SourceSpace { document.sourceSpace }

    /// Whether the source-space control is worth showing at all: only a V-Log
    /// LUT consults it, so an ordinary creative LUT leaves it hidden rather
    /// than offering a setting that changes nothing.
    var isSourceSpaceRelevant: Bool { selectedLUT?.inputSpace == .vlog }

    /// What the file itself says about its space, if anything. Read once per
    /// opened image — it is a header read, but it is also on the path of a UI
    /// that redraws freely.
    private var metadataFinding: SourceSpaceMetadata.Finding??

    private var sourceFinding: SourceSpaceMetadata.Finding? {
        if let cached = metadataFinding { return cached }
        let found = imageSource.flatMap { SourceSpaceMetadata.read($0) }
        metadataFinding = .some(found)
        return found
    }

    /// One line explaining what `Auto` is going on, shown under the picker.
    ///
    /// Only for `.auto`: once the user has picked, the picker already says what
    /// is happening and a second explanation would just be noise. When the file
    /// says nothing this reports that the pixels were measured — the honest
    /// answer, and the cue that an override may be worth trying.
    var sourceSpaceEvidence: String? {
        guard isSourceSpaceRelevant, document.sourceSpace == .auto else { return nil }
        guard let finding = sourceFinding else { return "Auto: measured from the image" }
        switch finding.space {
        case .auto: return "Auto: \(finding.evidence)"
        default: return "Auto: \(finding.space.label) — \(finding.evidence)"
        }
    }

    // MARK: - Tag filtering

    /// Turn one tag on or off in the filter.
    func toggleTagFilter(_ tag: String) {
        if tagFilter.contains(tag) { tagFilter.remove(tag) } else { tagFilter.insert(tag) }
    }

    func clearTagFilter() { tagFilter.removeAll() }

    /// The library, less anything the filter excludes. Categories that end up
    /// empty drop out rather than showing as empty folders.
    var filteredCategories: [LUTLibrary.Category] {
        guard tagFilter.isEmpty == false else { return library.categories }
        return library.categories.compactMap { category in
            let kept = category.luts.filter { tags.matches($0, required: tagFilter) }
            return kept.isEmpty ? nil : LUTLibrary.Category(id: category.id, name: category.name, luts: kept)
        }
    }

    /// Override how the source is interpreted, and re-render.
    ///
    /// No debounce: this is a discrete pick, not a drag, and it changes the
    /// picture completely rather than by a degree.
    func setSourceSpace(_ value: SourceSpace) {
        guard value != document.sourceSpace else { return }
        document.sourceSpace = value
        schedulePreview()
    }

    /// Set the LUT strength (0...1) and re-render the preview. Safe to call on
    /// every slider tick: the re-render is debounced and the previous one is
    /// cancelled, so a full-travel drag costs a handful of renders, not one per
    /// pixel of travel.
    func setLUTIntensity(_ value: Double) {
        let clamped = max(0, min(1, value))
        guard clamped != document.lut.intensity else { return }
        document.lut.intensity = clamped

        intensityTask?.cancel()
        intensityTask = Task {
            try? await Task.sleep(for: .milliseconds(Self.intensityDebounceMs))
            guard !Task.isCancelled else { return }
            self.schedulePreview()
        }
    }

    // MARK: - Preview

    let maxPreview = CGSize(width: 1600, height: 1200)
    private static let intensityDebounceMs = 60

    /// What the main preview panel should currently show, as a render request.
    ///
    /// While Space is held that is the **comparison baseline** — the same document with the look
    /// removed and develop kept (§8.5). Both sides therefore share a `rawDevelop`, so the swap reuses
    /// the engine's developed source instead of re-developing the RAW.
    ///
    /// One accessor rather than the same ternary at each call site: the histogram is supposed to
    /// describe the pixels on screen, and it stopped doing so precisely because it derived its image
    /// separately. Reading the request from one place is what makes that structural.
    private var displayRequest: (document: EditDocument, lut: CubeLUT?) {
        isShowingOriginal ? (document.originalForComparison, nil) : (document, selectedLUT)
    }

    /// Render the document for display.
    ///
    /// **This is the Step 5 cutover.** The preview no longer grades a baked `CIImage` on the main
    /// actor and rasterizes it through the old `ImageProcessor`; it hands the whole document to
    /// `RenderEngine`, which builds the graph and evaluates it inside the actor that owns the one
    /// `CIContext`. Develop, adjustments, LUT and intensity all reach the screen through one call.
    ///
    /// Nothing here touches `CIImage` any more — only `Sendable` values cross to the engine and a
    /// `CGImage` comes back, which is wrapped for AppKit on this actor.
    ///
    /// Any in-flight render is cancelled first, so a slider drag drops stale work rather than
    /// queueing it.
    private func schedulePreview() {
        previewTask?.cancel()

        guard let imageSource else {
            previewNSImage = nil
            return
        }

        let (requested, lut) = displayRequest
        let box = maxPreview

        previewTask = Task { [engine] in
            let cgImage = await engine.makeCGImage(
                source: imageSource, document: requested, lut: lut,
                scale: .preview(maxSize: box), space: .current
            )
            guard !Task.isCancelled else { return }
            guard let cgImage else {
                // Not per-LUT validation — a bad cube is caught and reported at parse time (§7).
                // This is the render itself failing, which means the source stopped being readable.
                self.statusMessage = "Could not render \(self.sourceName)"
                return
            }
            self.previewNSImage = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            self.updateHistogram()
        }

        // The grid shows the same frame under other LUTs, so anything that
        // changes the frame — a new image, develop, an adjustment, intensity —
        // invalidates every cell. `renderAllCells` returns immediately unless a
        // multi-cell layout is actually on screen.
        renderAllCells()
        refreshDifference()
    }

    /// Rasterize the comparison baseline for the side-by-side left panel. Only needs to re-run when
    /// the image or the develop settings change — not when the look does.
    private func scheduleOriginalPreview() {
        originalPreviewTask?.cancel()

        guard let imageSource else {
            originalPreviewNSImage = nil
            return
        }
        let baseline = document.originalForComparison
        let box = maxPreview

        originalPreviewTask = Task { [engine] in
            let cgImage = await engine.makeCGImage(
                source: imageSource, document: baseline, lut: nil,
                scale: .preview(maxSize: box), space: .current
            )
            guard !Task.isCancelled, let cgImage else { return }
            self.originalPreviewNSImage = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
        }
    }

    /// Toggle between original and LUT preview (for Space-hold comparison).
    func showOriginal(_ show: Bool) {
        guard show != isShowingOriginal else { return }
        isShowingOriginal = show
        schedulePreview()
    }

    /// The V shortcut. With seven layouts a boolean toggle is no longer the
    /// whole story, so this flips between single and whatever comparison layout
    /// was last used — the two states a keystroke is actually for.
    func toggleSideBySide() {
        if comparisonLayout == .single {
            setLayout(lastComparisonLayout)
        } else {
            lastComparisonLayout = comparisonLayout
            setLayout(.single)
        }
    }

    // MARK: - Info inspector (EXIF + histogram)

    func toggleInspector() {
        isInspectorPresented.toggle()
    }

    /// Recompute the histogram for the currently displayed image. No-op unless the Info tab of an
    /// open inspector is on screen. Cancellable, so dragging the intensity slider stays smooth.
    ///
    /// **Step 6 cut this over with export.** It used to tally `processedImage` — a full-resolution
    /// neutral decode with only the LUT on it — while the screen showed develop and adjustments as
    /// well. Deleting `processedImage` forced the choice, and describing the wrong image is not a
    /// state worth carrying to Step 7: the histogram now renders the *same document at the same
    /// scale* the preview does, which is what `document(forDisplay:)` exists to guarantee.
    ///
    /// Passing the preview box rather than a histogram-sized scale is deliberate — see
    /// `RenderEngine.histogram`, which shares the developed-source memo with the on-screen render
    /// instead of evicting it every tally.
    private func updateHistogram() {
        // Both halves of the gate: an inspector parked on Develop shows no histogram, so tallying
        // one on every settled render of a slider drag is pure waste.
        guard isInspectorPresented, inspectorTab == .info else { return }
        guard let imageSource else {
            histogram = nil
            return
        }
        let (requested, lut) = displayRequest
        let box = maxPreview

        histogramTask?.cancel()
        histogramTask = Task { [engine] in
            let result = await engine.histogram(
                source: imageSource, document: requested, lut: lut,
                scale: .preview(maxSize: box), space: .current, maxDimension: 512
            )
            guard !Task.isCancelled else { return }
            self.histogram = result
        }
    }

    /// Read EXIF/TIFF/GPS metadata off the main actor and publish it.
    private func refreshMetadata(url: URL?, data: Data?) {
        Task.detached {
            let meta: ImageMetadata
            if let url {
                meta = ImageMetadata.read(from: url)
            } else if let data {
                meta = ImageMetadata.read(from: data)
            } else {
                meta = ImageMetadata()
            }
            await MainActor.run { self.metadata = meta }
        }
    }

    /// Ask the engine what this image's decoder supports.
    ///
    /// Runs alongside the preview render rather than in front of it: the panel can appear a frame
    /// late, but first pixels should not wait on a capability question.
    private func refreshCapabilities() {
        capabilitiesTask?.cancel()
        rawCapabilities = nil

        guard let imageSource else { return }
        capabilitiesTask = Task { [engine] in
            let capabilities = await engine.rawCapabilities(for: imageSource)
            guard !Task.isCancelled else { return }
            self.rawCapabilities = capabilities
        }
    }

    // MARK: - Export

    /// Export the open image at full resolution.
    ///
    /// **The Step 6 cutover.** What goes to disk is now the same `EditDocument` the screen is
    /// rendering, at `.full` instead of `.preview` — one argument apart, through one funnel. Before,
    /// this handed over a baked `CIImage` that carried the LUT and nothing else, so develop and
    /// adjustments reached the preview and silently did not reach the file.
    ///
    /// Note it exports `document`, not `displayRequest` — holding Space to compare should not change
    /// what ⌘S writes.
    func exportDialog() {
        guard let request = exportRequest else {
            statusMessage = "Open an image first"
            return
        }
        export.exportDialog(
            source: request.source,
            document: request.document,
            lut: request.lut,
            suggestedBaseName: request.baseName
        )
    }

    /// What ⌘S would export, without running a panel.
    ///
    /// Internal rather than private because `NSSavePanel` cannot run headless, so this is the only
    /// way to assert the part of `exportDialog` that has content — *which* document goes to disk. The
    /// wrapper around it is the two lines the panel makes untestable, which is the same trade
    /// `docs/CODE_REVIEW.md` §5 already records for every other panel in the app.
    var exportRequest: (source: ImageSource, document: EditDocument, lut: CubeLUT?, baseName: String)? {
        guard let imageSource else { return nil }
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "image"
        return (
            source: imageSource,
            document: document,
            lut: selectedLUT,
            baseName: ExportCoordinator.exportBaseName(source: base, lut: selectedLUT)
        )
    }

    /// Apply the current look to every imported image and export them all to a
    /// chosen folder.
    ///
    /// Cut over with the single export, and for the same reason: `performBatchExport` used to load
    /// and grade each file itself, so fixing only the single path would have left Export All writing
    /// the old, develop-less render.
    func batchExportDialog() {
        let request = batchExportRequest
        export.batchExportDialog(items: request.items, document: request.document, lut: request.lut)
    }

    /// What Export All would write, without running a panel. Internal for the same reason
    /// `exportRequest` is.
    var batchExportRequest: (items: [ExportCoordinator.BatchItem], document: EditDocument, lut: CubeLUT?) {
        // Snapshot only the Sendable bits — avoid carrying NSImage thumbnails
        // across the actor boundary.
        let items = collection.items.map {
            ExportCoordinator.BatchItem(url: $0.url, data: $0.imageData, name: $0.displayName)
        }
        return (items: items, document: document, lut: selectedLUT)
    }

    // MARK: - Recipe extractor

    func presentRecipeExtractor() {
        derive.present()
    }

    func dismissRecipeExtractor() {
        derive.dismiss()
    }

    func deriveRecipe(rawURL: URL, jpgURL: URL) {
        derive.derive(rawURL: rawURL, jpgURL: jpgURL)
    }

    func saveDerivedLUT() {
        derive.saveDialog()
    }

    // MARK: - LUT folder

    /// Import LUTs into the app's own library, from a panel.
    ///
    /// Files and folders both: dropping a whole vendor folder in is the common
    /// case, and making the user select 46 files individually to do it would be
    /// the reason they never bother.
    func importLUTs() {
        let panel = NSOpenPanel()
        panel.title = "Import LUTs"
        panel.message = "Choose .cube files or folders of them."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.folder, UTType(filenameExtension: "cube")].compactMap { $0 }
        guard panel.runModal() == .OK, panel.urls.isEmpty == false else { return }
        importLUTs(from: panel.urls)
    }

    /// The same import, for a drop.
    func importLUTs(from urls: [URL]) {
        statusMessage = "Importing LUTs…"
        Task {
            let result = await library.importLUTs(from: urls)
            statusMessage = Self.importSummary(result)
        }
    }

    /// Say what happened, including the nothing-happened cases — an import that
    /// silently does nothing because every file was already there is the one
    /// most likely to be read as a bug.
    static func importSummary(_ result: LUTLibrary.ImportResult) -> String {
        var parts: [String] = []
        if result.imported > 0 { parts.append("Imported \(result.imported) LUT\(result.imported == 1 ? "" : "s")") }
        if result.duplicates > 0 { parts.append("\(result.duplicates) already in the library") }
        if result.failed > 0 { parts.append("\(result.failed) could not be read") }
        return parts.isEmpty ? "Nothing to import" : parts.joined(separator: " · ")
    }

    /// Remove a LUT from the app's own library. Refused for LUTs that live in a
    /// folder the user pointed the library at — see `LUTLibrary.removeFromLibrary`.
    func removeLUT(_ lut: CubeLUT) {
        if selectedLUT == lut { selectLUT(nil) }
        if library.removeFromLibrary(lut) {
            statusMessage = "Moved \(lut.name) to the Trash"
        } else {
            statusMessage = "\(lut.name) is not in the app's library — remove it where it lives"
        }
    }

    func chooseLUTFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select LUT Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            library.setFolder(url)
        }
    }
}
