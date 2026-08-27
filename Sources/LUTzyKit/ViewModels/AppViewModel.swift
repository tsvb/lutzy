import Foundation
import CoreImage
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Central state for the LUTzy app.
/// One LUT as the manager lists it. A named type rather than a tuple because
/// `Table` needs `Identifiable` rows, and the identity is the LUT's.
struct LibraryRow: Identifiable, Hashable {
    let lut: CubeLUT
    let category: String
    var id: LUTID { lut.lutID }
}

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

    /// **Shim.** The document stores a durable `LUTID`; views still want the LUT. Resolution is a
    /// fresh registry/scan/catalog lookup so rescans and external saved LUTs resolve through the
    /// same identity contract.
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
    @Published var comparisonLayout: ComparisonLayout = .split {
        didSet {
            if comparisonLayout != .wipe { setViewerWipeFocused(false) }
            scheduleSessionSave()
        }
    }
    /// One LUT reference per cell, in cell order. `nil` is a deliberate choice —
    /// the ungraded picture — not an empty slot.
    @Published var cellLUTIDs: [LUTID?] = []
    /// The rasterized cells, index-parallel to `cellLUTIDs`.
    @Published var cellImages: [NSImage?] = []
    /// The grid cell that receives a click from the LUT contact sheet. Dragging
    /// directly onto a cell bypasses this target and uses the drop destination.
    /// This is transient workspace focus, not project data.
    @Published var activeGridCellIndex: Int?
    /// Invalidates the lazily-rendered LUT contact sheet without tying it to
    /// the currently selected LUT. Picking a card changes the main preview,
    /// but should not make every other card render again.
    @Published private(set) var lutGalleryRevision = 0
    /// The amplified difference between the base cell and the current look.
    /// Only built while the difference layout is on screen.
    @Published var diffNSImage: NSImage?
    /// One in-flight render per cell, so re-picking one cell cancels one render
    /// rather than the whole sheet.
    var cellTasks: [Int: Task<Void, Never>] = [:]
    /// Coalesces workspace saves. The state a project remembers changes on
    /// every click in the sidebar, and each one rewriting the project file
    /// would be the only slow thing about clicking.
    private var sessionSaveTask: Task<Void, Never>?
    /// True while a project's workspace is being put back.
    ///
    /// Restoring is not a user action, and letting it save would let a *failed*
    /// restore overwrite what it failed to restore — which is what happened:
    /// selecting a LUT the library had not finished scanning yet resolved to
    /// nothing, and the resulting save erased the LUT from the project for
    /// good.
    /// A counter, not a flag: a restore runs one synchronous pass and two
    /// asynchronous ones that finish independently, and whichever finished
    /// first would clear a boolean while the others were still restoring.
    var restoreDepth = 0
    private var pendingSessionSaveAfterRestore = false
    var isRestoringSession: Bool { restoreDepth > 0 }
    /// What V returns to. Remembered so a glance at the single view does not
    /// cost the user their 3×3.
    var lastComparisonLayout: ComparisonLayout = .split

    // MARK: - Editor (see AppViewModel+Editor)

    /// The LUT being edited, the adjustments on it, and an optional second LUT
    /// stacked after them.
    @Published var editorBaseID: LUTID?
    @Published var editorEdit: LookEdit = .neutral
    @Published var editorStackID: LUTID?
    @Published var editorStackAmount: Float = 1
    /// The baked result, held so the editor can save exactly what is on screen.
    @Published var editedLUT: CubeLUT?
    var editorPreviewTask: Task<Void, Never>?
    var editorMaterializeTask: Task<Void, Never>?
    var editorBaseMaterialized: CubeLUT?
    var editorStackMaterialized: CubeLUT?

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
        case info, lut, develop, adjust
        var title: String {
            switch self {
            case .info: return "Info"
            case .lut: return "LUT"
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
    /// The current content-metric pass. Import review awaits the scan-owned
    /// pass instead of launching a second full-library measurement.
    private var tagIndexTask: Task<Void, Never>?
    /// One window owns one complete import pipeline. Serialising only the file
    /// copy is insufficient: a later scan can cancel an earlier scan before it
    /// has identified and measured the LUTs needed by its review.
    private var lutImportPipelineTail: Task<Void, Never>?

    @Published var isLoading: Bool = false
    @Published var statusMessage: String = "Open an image to get started"

    /// Non-nil when a hard failure should be surfaced as a dismissible alert.
    /// Bound to an `.alert` in ContentView; cleared when the user dismisses it.
    @Published var errorMessage: String?

    /// Read-only recommendations produced after a successful LUT import.
    /// Dismissing this review changes no LUT metadata or organisation.
    @Published var lutImportReview: LUTImportReview?

    @Published var isPhotosPickerPresented: Bool = false

    // MARK: - Owned state

    /// Projects, and which one is open. The LUT library is global; images and
    /// the workspace belong to a project — see `Project`.
    let projects: ProjectStore

    /// Project-free global media manifest. `ProjectStore` remains only as a
    /// compatibility source for old images and session files.
    let media: MediaLibrary

    let library: LUTLibrary

    /// Durable per-file identity and user-authored organisation metadata.
    var catalog: LUTCatalog { library.catalog }

    /// Measured and typed tags for the library, keyed by LUT content.
    let tags: LUTTagStore

    /// Tags a LUT must carry to be listed. Empty means no filtering.
    @Published var tagFilter: Set<String> = [] { didSet { scheduleSessionSave() } }

    /// Which folder the sidebar is showing, or `nil` for all of them. Set by
    /// the folder browser; independent of the tag filter, which composes with
    /// it.
    @Published var browsedCategory: String? { didSet { scheduleSessionSave() } }

    /// Whether the sidebar is showing only starred LUTs.
    @Published var showingFavouritesOnly = false { didSet { scheduleSessionSave() } }

    @Published var viewerLUTSource: LUTSource = .all
    @Published var libraryLUTSource: LUTSource = .all
    @Published var managerLUTSource: LUTSource = .all
    @Published var managerSelection: Set<LUTRecordID> = []
    @Published var selectedMediaFolder: String?
    @Published var selectedLibraryLUTID: LUTRecordID?
    @Published var selectedLibrarySampleID: String = LUTLibrarySample.all[0].id {
        didSet { lutGalleryRevision &+= 1 }
    }
    @Published var isShowingLibraryOriginal = false
    @Published private(set) var isLUTDetailFocused = false
    @Published private(set) var isViewerWipeFocused = false

    var librarySamples: [LUTLibrarySample] { LUTLibrarySample.all }
    var selectedLibrarySample: LUTLibrarySample {
        librarySamples.first(where: { $0.id == selectedLibrarySampleID }) ?? librarySamples[0]
    }

    var selectedLibraryLUT: CubeLUT? {
        selectedLibraryLUTID.flatMap { library.allLUTs.first(matching: $0) }
    }

    func selectLibraryLUT(_ lut: CubeLUT) {
        selectedLibraryLUTID = lut.lutID
    }

    func openLibraryLUTInViewer(_ lut: CubeLUT) {
        selectLUT(lut)
        section = .viewer
    }

    /// Which of the five top-level jobs owns the detail column.
    @Published var section: AppSection = .viewer {
        didSet {
            if section == .manager && oldValue != .manager { managerLUTSource = .all }
            if oldValue == .viewer && section != .viewer && isShowingOriginal {
                isShowingOriginal = false
                schedulePreview(refreshGallery: false)
            }
            if oldValue == .viewer && section != .viewer {
                setViewerWipeFocused(false)
            }
            if oldValue == .lutLibrary && section != .lutLibrary {
                setLUTDetailFocused(false)
            }
            if oldValue == .editor && section != .editor {
                editorMaterializeTask?.cancel()
            }
            scheduleSessionSave()
        }
    }

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
    private let lutGalleryPreviewCache = LUTGalleryPreviewCache()
    let lutMaterializationCache = LUTMaterializationCache()
    private var cancellables: [AnyCancellable] = []

    // MARK: - Init

    /// The stores are injectable so a test can point them at a scratch
    /// directory. Without that, `lutcheck` built a view model against the
    /// user's own projects and tags — it inherited their workspace, and worse,
    /// its own actions wrote back into them.
    init(engine: any RenderEngining = RenderEngine.shared,
         projects projectStore: ProjectStore? = nil,
         tags tagStore: LUTTagStore? = nil,
         media mediaLibrary: MediaLibrary? = nil,
         library lutLibrary: LUTLibrary? = nil) {
        self.engine = engine
        self.projects = projectStore ?? ProjectStore()
        self.tags = tagStore ?? LUTTagStore()
        self.media = mediaLibrary ?? MediaLibrary()
        self.library = lutLibrary ?? LUTLibrary()
        self.export = ExportCoordinator(engine: engine)

        // Project switching is no longer exposed, but its on-disk layout is a
        // safe compatibility seam for existing images. A fresh install gets
        // one implicit destination so Import Images works immediately.
        if self.projects.current == nil {
            self.projects.create(named: "Image Library")
        }

        // Forward nested ObservableObject changes so SwiftUI views update.
        for child in [
            library.objectWillChange.eraseToAnyPublisher(),
            library.catalog.objectWillChange.eraseToAnyPublisher(),
            collection.objectWillChange.eraseToAnyPublisher(),
            export.objectWillChange.eraseToAnyPublisher(),
            derive.objectWillChange.eraseToAnyPublisher(),
            // Without this the tag filter row never appears: the store
            // publishes its counts, but the sidebar observes this view model,
            // and an unforwarded child leaves the UI showing pre-scan state
            // forever.
            tags.objectWillChange.eraseToAnyPublisher(),
            projects.objectWillChange.eraseToAnyPublisher(),
            media.objectWillChange.eraseToAnyPublisher(),
        ] {
            cancellables.append(child.sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            })
        }

        wireCoordinators()
        library.restoreFolder()
        media.migrateLegacyProjects(projects)

        // A project owns the images and the workspace, so opening one is what
        // fills the window. Falling back to a loose source folder covers
        // libraries made before projects existed.
        if let project = projects.current {
            loadProjectImages()
            restoreSession(project.session)
        } else {
            collection.loadMediaRecords(media.records)
        }
    }

    /// Point the coordinators' status/error output at this view model, which
    /// owns the status bar and the alert. They report *what* happened; deciding
    /// how to show it stays here.
    private func wireCoordinators() {
        // A rescan can mean the bytes behind an unchanged durable record have changed — a `.cube`
        // replaced at the same locator keeps its record identity. Drop the engine's cube filters
        // rather than go on serving the old cube. Wired here, before `restoreFolder()` runs below,
        // so the launch scan is covered too.
        library.onScanned = { [weak self] in
            guard let self else { return }
            self.catalog.migrateLegacyMetadata(for: self.library.allLUTs, from: self.tags)
            self.migrateLegacyLUTReferences()
            self.lutGalleryRevision &+= 1
            let engine = self.engine
            Task { await engine.invalidateLUTCache() }
            // Measure whatever the scan found that has not been measured
            // before. Typed tags are never disturbed by this — see LUTTagStore.
            // Objective measured tags and similarity metrics are required for
            // every renderable LUT, including curated corpora. The store runs
            // this in cancellable persisted batches so discovery can publish
            // first without launching overlapping whole-library profilers.
            let scannedLUTs = self.library.allLUTs
            self.tagIndexTask?.cancel()
            self.tagIndexTask = Task { await self.tags.index(scannedLUTs) }
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
        derive.onWillSave = { [weak self] destination, transient, fingerprint in
            guard let self else { return false }
            let access = self.securityBookmark(forSavedLUT: destination)
            guard self.savedLUTRequiresBookmark(destination) == false || access.data != nil else {
                self.presentError("The selected external location could not be retained for relaunch recovery. Choose a location inside the LUT library or grant access and try again.")
                return false
            }
            guard self.catalog.beginSaveRecovery(
                for: destination, replacing: transient,
                expectedFingerprint: fingerprint, bookmark: access.data,
                bookmarkRelativePath: access.relativePath
            ) else {
                self.presentError("The LUT could not be prepared for a recoverable save. Check the library location and try again.")
                return false
            }
            return true
        }
        derive.onSaveFailed = { [weak self] destination in
            self?.catalog.cancelSaveRecovery(for: destination)
        }
        derive.onSaved = { [weak self] destination in
            guard let self else { return false }
            guard self.adoptSavedLUT(at: destination) else { return false }
            // Re-scan so the new entry appears in the sidebar.
            if let folder = self.library.folderURL { self.library.scan(folder) }
            return true
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
    @discardableResult
    private func adoptSavedLUT(at destination: URL) -> Bool {
        // Save-panel access is temporary. The durable catalog keeps a bookmark
        // for relaunch, while this live registry value must remain renderable
        // after the panel/security scope has closed.
        guard let saved = try? CubeLUT(
            url: destination, category: "Derived", retainTableData: true
        ) else {
            presentError("The saved LUT could not be read back for registration. Try saving again.")
            return false
        }
        let access = securityBookmark(forSavedLUT: destination)
        guard savedLUTRequiresBookmark(destination) == false || access.data != nil else {
            presentError("The LUT file was saved, but access to its external location could not be retained. Grant access and try saving again.")
            return false
        }
        let transientID = derive.derivedLUT?.lutID
        guard let recordID = catalog.adoptSavedLUT(
            saved, bookmark: access.data, bookmarkRelativePath: access.relativePath,
            replacing: transientID
        ) else {
            presentError("The LUT file was saved, but it could not be registered in the library. Try saving again.")
            return false
        }
        let durable = saved.withRecordID(recordID)
        derivedRegistry.register(durable)
        lutGalleryRevision &+= 1
        Task { await tags.index([durable]) }

        guard let current = document.lut.lutID, current == derive.derivedLUT?.lutID else { return true }
        document.lut.lutID = recordID
        Task { await engine.invalidateLUTCache() }
        schedulePreview()
        scheduleSessionSave()
        return true
    }

    /// A Save panel can authorize a brand-new filename before that file exists,
    /// but bookmark creation for the file URL is not guaranteed until after the
    /// write. Fall back to a bookmark for its existing parent and remember the
    /// filename relative to that scope.
    private func securityBookmark(forSavedLUT destination: URL) -> (data: Data?, relativePath: String?) {
        if let data = try? destination.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
        ) {
            return (data, nil)
        }
        let parent = destination.deletingLastPathComponent()
        if let data = try? parent.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
        ) {
            return (data, destination.lastPathComponent)
        }
        return (nil, nil)
    }

    private func savedLUTRequiresBookmark(_ destination: URL) -> Bool {
        guard let root = library.folderURL else { return true }
        let path = destination.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path != rootPath && path.hasPrefix(rootPath + "/") == false
    }

    /// Replace exact legacy path references only after the catalog knows the
    /// file. Missing paths remain non-destructive unresolved references.
    func migrateLegacyLUTReferences() {
        let previousDocumentID = document.lut.lutID
        let previousCells = cellLUTIDs
        let previousEditorBaseID = editorBaseID
        let previousEditorStackID = editorStackID
        if let id = document.lut.lutID { document.lut.lutID = library.migratedRecordID(for: id) }
        cellLUTIDs = cellLUTIDs.map { $0.map(library.migratedRecordID(for:)) }
        if let id = editorBaseID { editorBaseID = library.migratedRecordID(for: id) }
        if let id = editorStackID { editorStackID = library.migratedRecordID(for: id) }
        if document.lut.lutID != previousDocumentID || cellLUTIDs != previousCells {
            scheduleMigratedSessionSave()
        }
        if section == .editor,
           editorBaseID != previousEditorBaseID || editorStackID != previousEditorStackID {
            prepareEditorLUTsAndRefresh()
        }
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
        let priorIDs = Set(media.records.map(\.id))
        let result = media.importImageData(items)
        collection.loadMediaRecords(media.records)
        statusMessage = Self.mediaImportSummary(result)
        if let first = media.records.first(where: { priorIDs.contains($0.id) == false }) {
            openMedia(first)
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
        // Which image is open is workspace state; without this it was only
        // saved when something *else* happened to trigger a save afterwards.
        scheduleSessionSave()
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

    func selectLUT(_ lut: CubeLUT?, renderGridCells: Bool = true) {
        // A derived LUT is in no library, so nothing but the registry can resolve it later. Remember
        // it rather than replacing the last one: a document made now must still resolve after the
        // user derives again.
        if let lut, lut.lutID.isDerived { derivedRegistry.register(lut) }
        document.lut.lutID = lut?.lutID
        applyLUT(renderGridCells: renderGridCells)
        scheduleSessionSave()
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
    func resolvedLUT(_ id: LUTID?) -> CubeLUT? {
        guard let id else { return nil }
        if let registered = derivedRegistry.lut(for: id) { return registered }
        if let scanned = library.allLUTs.first(matching: id) { return scanned }
        if let external = catalog.loadLUT(for: id) {
            derivedRegistry.register(external)
            return external
        }
        return nil
    }

    func selectPreviousLUT() {
        guard let current = selectedLUT,
              let idx = library.allLUTs.firstIndex(of: current),
              idx > 0 else { return }
        chooseLUTFromGallery(library.allLUTs[idx - 1])
    }

    func selectNextLUT() {
        guard let current = selectedLUT else {
            if let first = library.allLUTs.first { chooseLUTFromGallery(first) }
            return
        }
        guard let idx = library.allLUTs.firstIndex(of: current),
              idx < library.allLUTs.count - 1 else { return }
        chooseLUTFromGallery(library.allLUTs[idx + 1])
    }

    // MARK: - LUT application

    private func applyLUT(renderGridCells: Bool = true) {
        schedulePreview(refreshGallery: false, renderGridCells: renderGridCells)
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
    /// Whether the picture is going through the display-to-V-Log conversion.
    ///
    /// Worth saying out loud, because that path is the approximate one and the
    /// V-Log path is not.
    var isConvertingToVLog: Bool {
        guard isSourceSpaceRelevant else { return false }
        switch document.sourceSpace {
        case .display: return true
        case .vlog: return false
        case .auto: return imageSource.flatMap { source in
            sourceImage.map { _ in autoSourceSpaceIsDisplay(source) }
        } ?? false
        }
    }

    private func autoSourceSpaceIsDisplay(_ source: ImageSource) -> Bool {
        if let finding = SourceSpaceMetadata.read(source), finding.space != .auto {
            return finding.space == .display
        }
        // The measurement is the engine's; a mismatch here would only ever be
        // in what the caption says, never in what is rendered.
        return true
    }

    /// What to warn about the conversion, or `nil` when none is happening.
    ///
    /// These LUTs are built to be fed V-Log straight off the camera. Feeding
    /// them a finished picture means undoing a render first, and the render
    /// being undone is a generic neutral one — not the Photo Style that
    /// actually made this file, which nothing here has. Worth stating, because
    /// the result looks plausible enough to be mistaken for the real thing.
    var conversionCaveat: String? {
        guard isConvertingToVLog else { return nil }
        return "Approximate: this picture is already rendered, so the render is undone before the LUT sees it — exactly, but against a generic neutral curve rather than the Photo Style that actually made this file, which nothing here has. Shoot V-Log for a result with no assumption in it."
    }

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

    func lutSource(for context: LUTWorkspaceContext) -> LUTSource {
        switch context {
        case .viewer: return viewerLUTSource
        case .library: return libraryLUTSource
        case .manager: return managerLUTSource
        }
    }

    func setLUTSource(_ source: LUTSource, for context: LUTWorkspaceContext) {
        switch context {
        case .viewer: viewerLUTSource = source
        case .library: libraryLUTSource = source
        case .manager: managerLUTSource = source
        }
        scheduleSessionSave()
    }

    @discardableResult
    func createCollection(named name: String, from recordIDs: Set<LUTRecordID>) -> LUTCollectionRecord? {
        catalog.createCollection(named: name, containing: recordIDs)
    }

    func luts(for source: LUTSource) -> [CubeLUT] {
        let values: [CubeLUT]
        switch source {
        case .all:
            values = library.allLUTs
        case .folder(let path):
            values = library.categories
                .filter { LUTFolderHierarchy.contains(categoryPath: $0.name, in: path) }
                .flatMap(\.luts)
        case .collection(let id):
            let members = catalog.members(of: id)
            values = library.allLUTs.filter { members.contains($0.lutID) }
        case .starred:
            values = library.allLUTs.filter(isStarred)
        }
        return values.sorted {
            catalog.effectiveName(for: $0).localizedStandardCompare(catalog.effectiveName(for: $1)) == .orderedAscending
        }
    }

    func title(for source: LUTSource) -> String {
        switch source {
        case .all: return "All LUTs"
        case .folder(let path): return path
        case .collection(let id):
            return catalog.collections.first(where: { $0.id == id })?.name ?? "Collection"
        case .starred: return "Starred"
        }
    }

    func thumbnail(for record: MediaRecord) -> NSImage? {
        collection.items.first(where: { $0.id == record.id.rawValue })?.thumbnail
    }

    var galleryLUTs: [CubeLUT] {
        luts(for: section == .lutLibrary ? libraryLUTSource : viewerLUTSource)
    }

    /// Build the visual Library's discovery shelves from the active local
    /// source. No inference happens here: an Unknown origin stays Unknown, and
    /// every row is backed by metadata that Manager already owns.
    func libraryDiscoveryShelves(for grouping: LUTLibraryGrouping) -> [LUTLibraryShelf] {
        let scoped = luts(for: libraryLUTSource)

        switch grouping {
        case .folder:
            let selectedFolder: String?
            if case .folder(let path) = libraryLUTSource { selectedFolder = path }
            else { selectedFolder = nil }
            return LUTLibraryDiscovery.folderShelves(
                from: scoped,
                selectedFolder: selectedFolder
            )

        case .collectionAndStar:
            let scopedIDs = Set(scoped.map(\.lutID))
            var shelves: [LUTLibraryShelf] = []
            let starred = scoped.filter(isStarred)
            if starred.isEmpty == false {
                shelves.append(LUTLibraryShelf(
                    id: "starred", title: "Starred", luts: starred
                ))
            }
            shelves.append(contentsOf: catalog.collections.compactMap { collection in
                let members = catalog.members(of: collection.id).intersection(scopedIDs)
                let values = scoped.filter { members.contains($0.lutID) }
                guard values.isEmpty == false else { return nil }
                return LUTLibraryShelf(
                    id: "collection:\(collection.id.uuidString)",
                    title: collection.name,
                    luts: values
                )
            })
            return shelves

        case .brand:
            var groups: [String: (title: String, luts: [CubeLUT])] = [:]
            for lut in scoped {
                let origin = catalog.origin(for: lut)
                let key = origin.discoveryID
                if groups[key] == nil { groups[key] = (origin.label, []) }
                groups[key]?.luts.append(lut)
            }
            return groups.map { id, group in
                LUTLibraryShelf(
                    id: "brand:\(id)",
                    title: group.title,
                    luts: group.luts
                )
            }
            .sorted { lhs, rhs in
                let leftRank = lhs.title == "Unknown" ? 1 : 0
                let rightRank = rhs.title == "Unknown" ? 1 : 0
                if leftRank != rightRank { return leftRank < rightRank }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

        case .tag:
            var groups: [String: [CubeLUT]] = [:]
            for lut in scoped {
                let tags = LUTGalleryMetadata.browsableTags(
                    typed: typedTags(for: lut),
                    measured: visibleMeasuredTags(for: lut)
                )
                for tag in Set(tags).filter({ $0.isEmpty == false }) {
                    groups[tag, default: []].append(lut)
                }
            }
            return groups.map { tag, values in
                LUTLibraryShelf(id: "tag:\(tag)", title: tag, luts: values)
            }
            .sorted {
                if $0.luts.count != $1.luts.count { return $0.luts.count > $1.luts.count }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }

        }
    }

    // MARK: - Record metadata

    func typedTags(for lut: CubeLUT) -> [String] { catalog.typedTags(for: lut) }
    func measuredTags(for lut: CubeLUT) -> [String] { tags.measuredTags(for: lut) }
    func visibleMeasuredTags(for lut: CubeLUT) -> [String] {
        let excluded = Set(catalog.excludedMeasuredTags(for: lut))
        return measuredTags(for: lut).filter { excluded.contains($0) == false }
    }
    func allTags(for lut: CubeLUT) -> [String] {
        Array(Set(typedTags(for: lut) + visibleMeasuredTags(for: lut))).sorted()
    }
    func isStarred(_ lut: CubeLUT) -> Bool { catalog.isStarred(lut) }
    var starredCount: Int { library.allLUTs.filter(isStarred).count }

    func toggleStarred(_ lut: CubeLUT) {
        catalog.toggleStarred(lut.lutID)
        objectWillChange.send()
    }

    func removeTag(_ tag: String, from lut: CubeLUT) {
        removeTag(tag, from: [lut])
    }

    func removeTag(_ tag: String, from luts: [CubeLUT]) {
        let selectedIDs = Set(luts.map(\.lutID))
        let measuredIDs = Set(luts.filter { measuredTags(for: $0).contains(tag) }.map(\.lutID))
        catalog.removeTag(tag, from: selectedIDs, hidingMeasuredFor: measuredIDs)
        objectWillChange.send()
    }

    var tagCounts: [(tag: String, count: Int)] {
        var tally: [String: Int] = [:]
        for lut in library.allLUTs {
            for tag in Set(allTags(for: lut)) { tally[tag, default: 0] += 1 }
        }
        return tally.map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.tag < $1.tag : $0.count > $1.count }
    }

    /// Note that the workspace moved, and write it out shortly.
    func scheduleSessionSave() {
        guard isRestoringSession == false else { return }
        sessionSaveTask?.cancel()
        sessionSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard Task.isCancelled == false else { return }
            self?.captureSession()
        }
    }

    /// Unlike ordinary restoration setters, a successful identity migration
    /// must be written after the restore guard is released. Keeping this
    /// explicit prevents an unresolved legacy reference from being erased just
    /// because unrelated restored properties fired their `didSet` hooks.
    func scheduleMigratedSessionSave() {
        if isRestoringSession {
            pendingSessionSaveAfterRestore = true
        } else {
            scheduleSessionSave()
        }
    }

    /// Release one synchronous/asynchronous restore hold. Mutations made while
    /// restoring are coalesced and written only after every hold is gone, so a
    /// failed lookup cannot erase a reference while successful identity
    /// migrations still become durable.
    func finishSessionRestore() {
        precondition(restoreDepth > 0)
        restoreDepth -= 1
        guard restoreDepth == 0, pendingSessionSaveAfterRestore else { return }
        pendingSessionSaveAfterRestore = false
        scheduleSessionSave()
    }

    /// Put the viewer back to having nothing open. Used when switching or
    /// deleting a project, where the previous project's picture must not stay
    /// on screen under the new project's name.
    func clearImage() {
        imageSource = nil
        sourceImage = nil
        sourceURL = nil
        sourceName = ""
        previewNSImage = nil
        originalPreviewNSImage = nil
        diffNSImage = nil
        cellImages = Array(repeating: nil, count: cellLUTIDs.count)
        lutGalleryRevision &+= 1
        statusMessage = "Open an image to get started"
    }

    /// The library, less anything the filters exclude.
    ///
    /// Three filters compose rather than override — a folder, a set of tags,
    /// and the star — because "the warm ones I starred, in Fuji" is a question
    /// this library is big enough to be asked. Categories that end up empty
    /// drop out rather than showing as empty folders.
    var filteredCategories: [LUTLibrary.Category] {
        let allowed = Set(luts(for: managerLUTSource).map(\.lutID))
        return library.categories.compactMap { category in
            let kept = category.luts.filter { lut in
                guard allowed.contains(lut.lutID) else { return false }
                if showingFavouritesOnly && isStarred(lut) == false { return false }
                return tagFilter.isSubset(of: Set(allTags(for: lut)))
            }
            return kept.isEmpty ? nil : LUTLibrary.Category(id: category.id, name: category.name, luts: kept)
        }
    }

    /// Folder tiles for the browser: every folder with how many LUTs it holds.
    var folderTiles: [(name: String, count: Int)] {
        library.categories
            .map { (name: $0.name, count: $0.luts.count) }
            .sorted { $0.name < $1.name }
    }

    /// The folder column shown in Viewer. Counts include descendant folders,
    /// matching the set of LUT cards that selecting the row will reveal.
    var lutFolderTree: [LUTFolderNode] {
        let counts = Dictionary(
            library.categories.map { ($0.name, $0.luts.count) },
            uniquingKeysWith: +
        )
        return LUTFolderHierarchy.tree(from: counts)
    }

    /// Every LUT below the selected folder, independent of Manager-only tag
    /// filters. Folder selection is the Viewer's primary organisation model.
    var viewerFolderLUTs: [CubeLUT] {
        luts(for: viewerLUTSource)
    }

    func browse(_ category: String?) {
        browsedCategory = category
    }

    /// Render one contact-sheet card through the same engine and document as
    /// the main Viewer. The only substitution is the LUT being auditioned.
    /// SwiftUI tasks call this lazily for visible cards and cancel it when a
    /// card scrolls away.
    func makeLUTGalleryPreview(for lut: CubeLUT, maxSize: CGSize) async -> NSImage? {
        let renderSource: ImageSource
        var request: EditDocument
        let context: String
        let sampleID: String?
        if section == .lutLibrary {
            guard let source = selectedLibrarySample.imageSource else { return nil }
            renderSource = source
            context = "library"
            sampleID = selectedLibrarySampleID
            request = EditDocument(
                rawDevelop: .neutral, adjustments: [],
                lut: LUTSettings(lutID: lut.lutID, intensity: 1),
                sourceSpace: selectedLibrarySample.sourceSpace
            )
        } else {
            guard let imageSource else { return nil }
            renderSource = imageSource
            context = "viewer"
            sampleID = nil
            request = document
        }
        request.lut.lutID = lut.lutID
        request.lut.intensity = section == .lutLibrary ? 1 : request.lut.intensity

        let key = LUTGalleryPreviewCacheKey(
            lutID: lut.lutID,
            revision: lutGalleryRevision,
            sampleID: sampleID,
            context: context,
            width: Int(maxSize.width.rounded()),
            height: Int(maxSize.height.rounded())
        )
        let engine = self.engine
        return await lutGalleryPreviewCache.image(for: key) {
            let cgImage = await engine.makeCGImage(
                source: renderSource,
                document: request,
                lut: lut,
                scale: .preview(maxSize: maxSize),
                space: .current
            )
            guard Task.isCancelled == false, let cgImage else { return nil }
            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
        }
    }

    func makeLUTLibraryDetailImages(
        for lut: CubeLUT, sample: LUTLibrarySample, maxSize: CGSize
    ) async -> LUTLibraryRenderPair? {
        guard let source = sample.imageSource else { return nil }
        let originalDocument = EditDocument(
            rawDevelop: .neutral, adjustments: [], lut: .none, sourceSpace: sample.sourceSpace
        )
        let gradedDocument = EditDocument(
            rawDevelop: .neutral, adjustments: [],
            lut: LUTSettings(lutID: lut.lutID, intensity: 1), sourceSpace: sample.sourceSpace
        )
        async let originalCG = engine.makeCGImage(
            source: source, document: originalDocument, lut: nil,
            scale: .preview(maxSize: maxSize), space: .current
        )
        async let gradedCG = engine.makeCGImage(
            source: source, document: gradedDocument, lut: lut,
            scale: .preview(maxSize: maxSize), space: .current
        )
        guard let original = await originalCG, let graded = await gradedCG, !Task.isCancelled else { return nil }
        return LUTLibraryRenderPair(
            original: NSImage(cgImage: original, size: NSSize(width: original.width, height: original.height)),
            graded: NSImage(cgImage: graded, size: NSSize(width: graded.width, height: graded.height))
        )
    }

    /// Every LUT the current filters leave, with the folder it is in.
    ///
    /// The manager works on a flat list because that is what bulk actions need:
    /// "these nine, into Fuji" does not care which folders they came from.
    var visibleLUTs: [LibraryRow] {
        filteredCategories.flatMap { category in
            category.luts.map { LibraryRow(lut: $0, category: category.name) }
        }
    }

    /// The Manager's user-facing Brand column. This is the catalog's persisted
    /// Brand value. A one-time legacy migration may seed it from
    /// unambiguous folder/name evidence; the UI never performs live inference.
    func managerBrandLabel(for lut: CubeLUT) -> String {
        catalog.origin(for: lut).label
    }

    func managerInputLabel(for lut: CubeLUT) -> String {
        catalog.inputProfile(for: lut)
    }

    /// Star or unstar a whole selection.
    ///
    /// One decision for the group rather than a per-LUT toggle: toggling nine
    /// LUTs of which four are starred leaves five starred and four not, which
    /// is never what was meant. If any are unstarred, star them all.
    func setFavourite(_ luts: [CubeLUT]) {
        let shouldStar = luts.contains { isStarred($0) == false }
        catalog.setStarred(shouldStar, for: Set(luts.map(\.lutID)))
        statusMessage = shouldStar ? "Starred \(luts.count)" : "Unstarred \(luts.count)"
    }

    func addTag(_ tag: String, to luts: [CubeLUT]) {
        catalog.addTag(tag, to: Set(luts.map(\.lutID)))
        statusMessage = "Tagged \(luts.count) with “\(tag)”"
    }

    func move(_ luts: [CubeLUT], toCategory category: String) {
        var moved = 0
        for lut in luts where library.move(lut, toCategory: category) { moved += 1 }
        statusMessage = moved == luts.count
            ? "Moved \(moved) to \(category.isEmpty ? "the top level" : category)"
            : "Moved \(moved) of \(luts.count) — the rest are not in the app's library"
    }

    func remove(_ luts: [CubeLUT]) {
        var removed = 0
        for lut in luts where library.removeFromLibrary(lut) { removed += 1 }
        statusMessage = removed == luts.count
            ? "Moved \(removed) to the Trash"
            : "Removed \(removed) of \(luts.count) — the rest are not in the app's library"
    }

    /// Move a LUT into another folder of the app's own library.
    @discardableResult
    func moveLUT(_ lut: CubeLUT, toCategory category: String) -> Bool {
        if library.move(lut, toCategory: category) {
            statusMessage = "Moved \(lut.name) to \(category.isEmpty ? "the top level" : category)"
            return true
        } else {
            statusMessage = "\(lut.name) is not in the app's library — move it where it lives"
            return false
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
    private func schedulePreview(refreshGallery: Bool = true, renderGridCells: Bool = true) {
        previewTask?.cancel()

        if refreshGallery { lutGalleryRevision &+= 1 }

        // Difference is assembled from two independently-rendered pictures. Invalidate the pair
        // before either replacement task can land, otherwise a quick B render can be subtracted
        // from the previous A while a slow RAW/develop render is still in flight. A false flash is
        // worse than a short pending state because it looks like a real measured difference.
        prepareDifferencePreviewRender(rerenderBase: renderGridCells)

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
            // The difference needs *this* render, not the one on screen when
            // the task started. Composing outside the task used whatever was
            // still displayed, so switching LUT showed the difference against
            // the previous one — a picture full of colour where black was the
            // right answer.
            self.refreshDifference()
        }

        // The grid shows the same frame under other LUTs, so anything that
        // changes the frame — a new image, develop, an adjustment, intensity —
        // invalidates every cell. `renderAllCells` returns immediately unless a
        // multi-cell layout is actually on screen.
        if renderGridCells { renderAllCells() }
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
        if section == .lutLibrary {
            guard isLUTDetailFocused, selectedLibraryLUT != nil else { return }
            isShowingLibraryOriginal = show
            return
        }
        guard section == .viewer else { return }
        guard show != isShowingOriginal else { return }
        isShowingOriginal = show
        schedulePreview(refreshGallery: false)
    }

    func setLUTDetailFocused(_ focused: Bool) {
        isLUTDetailFocused = focused
        if focused == false { isShowingLibraryOriginal = false }
    }

    func setViewerWipeFocused(_ focused: Bool) {
        isViewerWipeFocused = focused && section == .viewer && comparisonLayout == .wipe
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

    /// Export a chosen subset rather than the whole filmstrip.
    ///
    /// The manager's reason to exist: "these six, with this look" is the
    /// ordinary way a set gets used, and Export All could only ever say "all of
    /// them". Names rather than indices, because the table is filtered and
    /// sorted independently of the collection's own order.
    func batchExportDialog(named names: Set<String>) {
        guard names.isEmpty == false else { return }
        let items = collection.items
            .filter { names.contains($0.displayName) }
            .map { ExportCoordinator.BatchItem(url: $0.url, data: $0.imageData, name: $0.displayName) }
        guard items.isEmpty == false else {
            statusMessage = "Nothing selected to export"
            return
        }
        export.batchExportDialog(items: items, document: document, lut: selectedLUT)
    }

    /// Remove images from the open project.
    ///
    /// Moves the files to the Trash, the same rule LUT removal follows: they
    /// are inside the project, and the project is the app's to manage.
    func removeImages(named names: Set<String>) {
        var removed = 0
        for item in collection.items where names.contains(item.displayName) {
            guard let url = item.url,
                  let folder = projects.currentImagesFolder,
                  url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
            else { continue }
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil { removed += 1 }
        }
        guard removed > 0 else {
            statusMessage = "Nothing removed — those images are not in the image library"
            return
        }
        loadProjectImages()
        statusMessage = "Moved \(removed) image\(removed == 1 ? "" : "s") to the Trash"
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
        let predecessor = lutImportPipelineTail
        let work = Task { [weak self] in
            await predecessor?.value
            guard let self else { return }
            await self.performLUTImport(from: urls)
        }
        lutImportPipelineTail = work
    }

    private func performLUTImport(from urls: [URL]) async {
        statusMessage = "Importing LUTs…"
        let result = await library.importLUTs(from: urls)
        await library.scanCompletion()
        let importedPaths = Set(result.importedURLs.map {
            $0.standardizedFileURL.resolvingSymlinksInPath().path
        })
        let imported = library.allLUTs.filter {
            importedPaths.contains($0.url.standardizedFileURL.resolvingSymlinksInPath().path)
        }

        // The scan owns one full-library index pass. Await that exact task
        // rather than racing it with a duplicate measurement pass.
        await tagIndexTask?.value
        statusMessage = Self.importSummary(result)
        if imported.isEmpty == false {
            presentImportReview(makeImportReview(
                imported: imported,
                excludingPaths: importedPaths,
                result: result
            ))
        }
    }

    /// A second queued import may finish while the first review sheet is still
    /// open. Preserve both batches instead of replacing the user's first set
    /// of recommendations before it can be inspected.
    private func presentImportReview(_ review: LUTImportReview) {
        guard let pending = lutImportReview else {
            lutImportReview = review
            return
        }
        lutImportReview = LUTImportReview(
            imported: pending.imported + review.imported,
            duplicates: pending.duplicates + review.duplicates,
            failed: pending.failed + review.failed,
            comparedAgainst: max(pending.comparedAgainst, review.comparedAgainst),
            recommendations: pending.recommendations + review.recommendations
        )
    }

    private func makeImportReview(
        imported: [CubeLUT],
        excludingPaths: Set<String>,
        result: LUTLibrary.ImportResult
    ) -> LUTImportReview {
        let existing = library.allLUTs.filter {
            excludingPaths.contains($0.url.standardizedFileURL.resolvingSymlinksInPath().path) == false
        }
        let existingCandidates = existing.compactMap { lut -> LUTSimilarityCandidate? in
            guard let metrics = tags.metrics(for: lut) else { return nil }
            return LUTSimilarityCandidate(
                id: lut.lutID,
                name: catalog.effectiveName(for: lut),
                fingerprint: lut.contentHash,
                inputSpace: lut.inputSpace,
                metrics: metrics,
                measuredTags: tags.measuredTags(for: lut)
            )
        }
        let recommendations = imported.sorted {
            catalog.effectiveName(for: $0).localizedStandardCompare(catalog.effectiveName(for: $1)) == .orderedAscending
        }.map { candidate in
            let candidateMetrics = tags.metrics(for: candidate)
            let candidateTags = tags.measuredTags(for: candidate)
            let similarityCandidate = candidateMetrics.map {
                LUTSimilarityCandidate(
                    id: candidate.lutID,
                    name: catalog.effectiveName(for: candidate),
                    fingerprint: candidate.contentHash,
                    inputSpace: candidate.inputSpace,
                    metrics: $0,
                    measuredTags: candidateTags
                )
            }
            let matches = similarityCandidate.map {
                LUTImportRecommender.matches(for: $0, among: existingCandidates)
            } ?? []

            return LUTImportRecommendation(
                id: candidate.lutID,
                name: catalog.effectiveName(for: candidate),
                inputSpace: candidate.inputSpace,
                tags: candidateTags.filter { $0.hasPrefix("input:") == false },
                matches: matches
            )
        }
        return LUTImportReview(
            imported: result.imported,
            duplicates: result.duplicates,
            failed: result.failed,
            comparedAgainst: existing.count,
            recommendations: recommendations
        )
    }

    func inspectLUTFromImportReview(_ id: LUTID) {
        guard library.allLUTs.first(matching: id) != nil else { return }
        libraryLUTSource = .all
        selectedLibraryLUTID = id
        section = .lutLibrary
        lutImportReview = nil
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

    static func mediaImportSummary(_ result: MediaLibrary.ImportResult) -> String {
        var parts: [String] = []
        if result.imported > 0 { parts.append("Imported \(result.imported) media item\(result.imported == 1 ? "" : "s")") }
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
