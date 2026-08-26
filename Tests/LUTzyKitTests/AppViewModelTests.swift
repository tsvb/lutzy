import XCTest
import CoreImage
import simd
@testable import LUTzyKit

/// The coordinators report *what* happened; `AppViewModel` decides how it's
/// shown. That wiring is a set of closures assigned in `init`, and a closure
/// left unassigned fails silently — the status bar simply stops updating and
/// errors never reach the alert. These tests pin it down.
@MainActor
final class AppViewModelTests: TempDirectoryTestCase {

    func testWorkspaceSourcesStayIndependentAndTransientOriginalClearsOnExit() {
        let viewModel = AppViewModel()
        let collectionID = UUID()
        viewModel.viewerLUTSource = .folder("Fuji/Classic")
        viewModel.libraryLUTSource = .collection(collectionID)
        viewModel.managerLUTSource = .starred

        viewModel.section = .lutLibrary
        viewModel.isShowingLibraryOriginal = true
        viewModel.section = .manager

        XCTAssertEqual(viewModel.viewerLUTSource, .folder("Fuji/Classic"))
        XCTAssertEqual(viewModel.libraryLUTSource, .collection(collectionID))
        XCTAssertEqual(viewModel.managerLUTSource, .all)
        XCTAssertFalse(viewModel.isShowingLibraryOriginal)

        viewModel.section = .viewer
        viewModel.isShowingOriginal = true
        viewModel.section = .mediaLibrary
        XCTAssertFalse(viewModel.isShowingOriginal)
    }

    func testCreatingCollectionFromManagerSelectionCapturesExactlyThoseRecords() throws {
        let catalog = LUTCatalog(fileURL: tempDirectory.appendingPathComponent("collection-catalog.json"))
        let firstURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "First.cube", in: tempDirectory
        )
        let secondURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 3), named: "Second.cube", in: tempDirectory
        )
        let first = try XCTUnwrap(catalog.adoptSavedLUT(try CubeLUT(url: firstURL)))
        let second = try XCTUnwrap(catalog.adoptSavedLUT(try CubeLUT(url: secondURL)))
        let viewModel = AppViewModel(
            engine: FakeRenderEngine(), library: LUTLibrary(catalog: catalog)
        )

        let collection = try XCTUnwrap(viewModel.createCollection(named: "Low Saturation", from: [first]))

        XCTAssertEqual(catalog.members(of: collection.id), Set([first]))
        XCTAssertFalse(catalog.members(of: collection.id).contains(second))
        XCTAssertNil(viewModel.createCollection(named: "Empty", from: []))
    }

    func testLibrarySpaceRequiresFocusedDetailAndClearsWhenFocusLeaves() async throws {
        let catalog = LUTCatalog(fileURL: tempDirectory.appendingPathComponent("focus-catalog.json"))
        let library = LUTLibrary(catalog: catalog)
        let viewModel = AppViewModel(
            engine: FakeRenderEngine(), library: library
        )
        viewModel.section = .lutLibrary

        viewModel.showOriginal(true)
        XCTAssertFalse(viewModel.isShowingLibraryOriginal, "Gallery must not own Space")

        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "Detail.cube", in: tempDirectory)
        library.scan(tempDirectory)
        while library.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        viewModel.selectLibraryLUT(try XCTUnwrap(library.allLUTs.first))
        viewModel.setLUTDetailFocused(true)
        viewModel.showOriginal(true)
        XCTAssertTrue(viewModel.isShowingLibraryOriginal)

        viewModel.setLUTDetailFocused(false)
        XCTAssertFalse(viewModel.isShowingLibraryOriginal)
        viewModel.showOriginal(true)
        XCTAssertFalse(viewModel.isShowingLibraryOriginal)
    }

    func testExternalCatalogLUTRestoresFromSavedSessionAfterRelaunch() async throws {
        let catalog = LUTCatalog(fileURL: tempDirectory.appendingPathComponent("session-catalog.json"))
        let scanRoot = tempDirectory.appendingPathComponent("scanned", isDirectory: true)
        let outside = tempDirectory.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let externalURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "External.cube", in: outside
        )
        let externalID = try XCTUnwrap(catalog.adoptSavedLUT(try CubeLUT(url: externalURL)))
        let library = LUTLibrary(catalog: catalog)
        library.setFolder(scanRoot)

        let projects = ProjectStore(root: tempDirectory.appendingPathComponent("Projects"))
        _ = projects.create(named: "Restore")
        var session = Project.Session()
        session.selectedLUT = externalID.raw
        projects.updateSession(session)
        let viewModel = AppViewModel(
            engine: FakeRenderEngine(),
            projects: projects,
            tags: LUTTagStore(fileURL: tempDirectory.appendingPathComponent("session-tags.json")),
            media: MediaLibrary(
                root: tempDirectory.appendingPathComponent("Media"),
                manifestURL: tempDirectory.appendingPathComponent("session-media.json")
            ),
            library: library
        )

        let deadline = Date().addingTimeInterval(5)
        while viewModel.document.lut.lutID != externalID {
            if Date() > deadline { return XCTFail("external LUT session never restored") }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(viewModel.selectedLUT?.url.standardizedFileURL, externalURL.standardizedFileURL)
        XCTAssertNil(library.allLUTs.first(where: { $0.url.standardizedFileURL == externalURL.standardizedFileURL }))
    }

    func testExportStatusReachesTheStatusBar() {
        let viewModel = AppViewModel()
        viewModel.export.onStatus?("Exported: photo.jpg")
        XCTAssertEqual(viewModel.statusMessage, "Exported: photo.jpg")
    }

    func testExportErrorReachesBothTheAlertAndTheStatusBar() {
        let viewModel = AppViewModel()
        XCTAssertNil(viewModel.errorMessage)

        viewModel.export.onError?("Export failed: disk full")

        XCTAssertEqual(viewModel.errorMessage, "Export failed: disk full",
                       "a hard failure should raise the alert")
        XCTAssertEqual(viewModel.statusMessage, "Export failed: disk full",
                       "...and also land in the status bar")
    }

    func testDeriveStatusAndErrorAreWired() {
        let viewModel = AppViewModel()

        viewModel.derive.onStatus?("Deriving recipe…")
        XCTAssertEqual(viewModel.statusMessage, "Deriving recipe…")

        viewModel.derive.onError?("Derive failed: bad pair")
        XCTAssertEqual(viewModel.errorMessage, "Derive failed: bad pair")
    }

    /// Build a derived LUT **the way `DeriveCoordinator` does**, scratch file and all.
    ///
    /// Going through `makeDerivedLUT` is the point. The version of this suite that used
    /// `CubeLUT(cube:size:name:)` directly was green against a live resolution bug, purely because
    /// its fixture produced a `derived://` ID where production produced a temp-file path.
    private func makeProductionShapedDerive(named name: String = "shot_recipe_2_Rec709") throws -> CubeLUT {
        let cube = [SIMD3<Float>](repeating: SIMD3(0.25, 0.5, 0.75), count: 8)
        // The scratch file is written because production writes one, and because the save path
        // copies it. It is deliberately not what names the LUT.
        let scratch = tempDirectory.appendingPathComponent("\(name).cube")
        try CubeLUT.write(cube: cube, size: 2, title: name, to: scratch)
        return DeriveCoordinator.makeDerivedLUT(cube: cube, size: 2, name: name)
    }

    /// A finished derive should preview itself immediately — but only when
    /// there's an image on screen to preview it against.
    func testDerivedLUTIsSelectedWhenAnImageIsOpen() throws {
        let viewModel = AppViewModel()
        let lut = try makeProductionShapedDerive()

        viewModel.derive.onDerived?(lut)
        XCTAssertNil(viewModel.selectedLUT, "nothing to preview against yet")

        viewModel.sourceImage = CIImage(color: .gray)
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        viewModel.derive.onDerived?(lut)
        XCTAssertEqual(viewModel.selectedLUT, lut, "a derived LUT should preview on the open image")
    }

    /// **The Step 9 regression test.** A successful derive must leave the preview graded and the LUT
    /// selected.
    ///
    /// This was broken on `main`: `derive` named its result after the scratch temp file, so
    /// `LUTID.isDerived` read false, `selectLUT` filed it under nothing, and `resolvedLUT` fell
    /// through to a library lookup for a path no library contains. The user saw a finished derive and
    /// an ungraded image.
    ///
    /// Asserted on the *resolved LUT*, not on `document.lut.lutID` — the document held the right
    /// reference the whole time. It was resolution that failed, so resolution is what to assert.
    func testAFreshlyDerivedLUTResolvesAndGradesThePreview() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        viewModel.sourceImage = CIImage(color: .gray)
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))

        let lut = try makeProductionShapedDerive()
        viewModel.derive.onDerived?(lut)

        XCTAssertEqual(viewModel.selectedLUT, lut,
                       "a fresh derive must resolve; it is in no library, so only the registry can")
        XCTAssertEqual(viewModel.document.lut.lutID, lut.lutID)
        XCTAssertTrue(lut.lutID.isDerived,
                      "the derived LUT must carry a derived:// identity, not a temp-file path")
    }

    func testDeriveSavePanelDefaultsToTheLUTFolder() async throws {
        let viewModel = AppViewModel()
        XCTAssertNil(viewModel.derive.libraryFolder?(), "no folder configured yet")

        viewModel.library.setFolder(tempDirectory)
        XCTAssertEqual(viewModel.derive.libraryFolder?(), tempDirectory,
                       "Save should open in the user's LUT folder")
    }

    func testGalleryPreviewUsesTheCurrentDocumentWithItsCandidateLUT() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        let imageURL = try Fixtures.writeGradientPNG(
            width: 32,
            height: 24,
            named: "gallery-source.png",
            in: tempDirectory
        )
        let lutURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2),
            named: "Gallery Candidate.cube",
            in: tempDirectory
        )
        let candidate = try CubeLUT(url: lutURL, category: "Test")

        viewModel.openImage(url: imageURL)
        let deadline = Date().addingTimeInterval(5)
        while viewModel.sourceImage == nil {
            if Date() > deadline { return XCTFail("the source image never opened") }
            try await Task.sleep(for: .milliseconds(10))
        }

        viewModel.setLUTIntensity(0.42)
        let current = viewModel.document
        let size = CGSize(width: 480, height: 300)
        _ = await viewModel.makeLUTGalleryPreview(for: candidate, maxSize: size)

        let requests = await fake.previewRequests
        let request = try XCTUnwrap(requests.last { $0.lutID == candidate.lutID })
        XCTAssertEqual(request.document.rawDevelop, current.rawDevelop)
        XCTAssertEqual(request.document.adjustments, current.adjustments)
        XCTAssertEqual(request.document.sourceSpace, current.sourceSpace)
        XCTAssertEqual(request.document.lut.intensity, current.lut.intensity)
        XCTAssertEqual(request.document.lut.lutID, candidate.lutID)
        XCTAssertEqual(request.scale, .preview(maxSize: size))
    }

    /// Saving a derived LUT into the library folder has to trigger a re-scan,
    /// or the new file won't appear in the sidebar until relaunch.
    func testSavingADerivedLUTRescansTheLibrary() async throws {
        let viewModel = AppViewModel()
        viewModel.library.setFolder(tempDirectory)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(viewModel.library.allLUTs.isEmpty)

        // Drop a cube in and fire the saved hook the way DeriveCoordinator does.
        let saved = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Derived.cube", in: tempDirectory
        )
        _ = viewModel.derive.onSaved?(saved)

        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(viewModel.library.allLUTs.map(\.name), ["Derived"],
                       "the sidebar should pick up a just-saved LUT without a relaunch")
    }

    // MARK: - Saving a derive

    /// Install a completed derive and select it, the way a real derive does.
    private func deriveAndSelect(
        on viewModel: AppViewModel, named name: String = "shot_recipe_2_Rec709"
    ) throws -> (lut: CubeLUT, scratch: URL) {
        let cube = [SIMD3<Float>](repeating: SIMD3(0.25, 0.5, 0.75), count: 8)
        let scratch = tempDirectory.appendingPathComponent("scratch-\(name).cube")
        try CubeLUT.write(cube: cube, size: 2, title: name, to: scratch)
        let lut = DeriveCoordinator.makeDerivedLUT(cube: cube, size: 2, name: name)
        viewModel.derive.setScratchResult(lut: lut, report: nil, scratchURL: scratch)
        viewModel.selectLUT(lut)
        return (lut, scratch)
    }

    /// Saving makes the LUT durable, so the document's reference to it should become durable in the
    /// same moment.
    ///
    /// A `derived://` ID resolves only through the in-memory registry: it cannot survive a relaunch,
    /// and it says nothing about where the file went. Once the user has chosen a path, that path is
    /// the honest reference — it is what a fresh launch would resolve, and it is what a rescan puts
    /// in the library.
    func testSavingADerivedLUTRepointsTheDocumentAtTheSavedFile() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.library.setFolder(tempDirectory)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }

        let (lut, _) = try deriveAndSelect(on: viewModel)
        XCTAssertTrue(try XCTUnwrap(viewModel.document.lut.lutID).isDerived)

        let destination = tempDirectory.appendingPathComponent("Keeper.cube")
        XCTAssertTrue(try viewModel.derive.save(to: destination))

        let durableID = try XCTUnwrap(viewModel.document.lut.lutID)
        XCTAssertFalse(durableID.isDerived,
                       "after the save the document should reference a durable catalog record")
        XCTAssertNotEqual(durableID, lut.lutID)
        XCTAssertEqual(viewModel.catalog.record(for: durableID)?.locator, destination.standardizedFileURL.path)
        XCTAssertEqual(viewModel.selectedLUT?.url.standardizedFileURL, destination.standardizedFileURL,
                       "and it must still resolve — to the saved file")
    }

    /// The Save panel does not force the LUT folder, so a save can land somewhere the library never
    /// scans. The document is re-pointed either way, which means the registry — not the rescan — is
    /// what has to keep it resolving.
    func testSavingOutsideTheLibraryFolderStillResolves() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        let libraryFolder = tempDirectory.appendingPathComponent("luts")
        let elsewhere = tempDirectory.appendingPathComponent("elsewhere")
        for folder in [libraryFolder, elsewhere] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "Other.cube", in: libraryFolder)
        viewModel.library.setFolder(libraryFolder)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }

        _ = try deriveAndSelect(on: viewModel)
        let destination = elsewhere.appendingPathComponent("Outside.cube")
        XCTAssertTrue(try viewModel.derive.save(to: destination))
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertNil(viewModel.library.allLUTs.first(where: {
            $0.url.standardizedFileURL == destination.standardizedFileURL
        }),
                     "precondition: the library does not scan this folder")
        let durableID = try XCTUnwrap(viewModel.document.lut.lutID)
        XCTAssertEqual(viewModel.catalog.record(for: durableID)?.locator, destination.standardizedFileURL.path)
        XCTAssertEqual(viewModel.selectedLUT?.url.standardizedFileURL, destination.standardizedFileURL,
                       "the registry has to cover the save the rescan cannot see")
    }

    /// Catalog persistence is part of adopting a save. If it fails, the file
    /// may exist, but the document must keep the resolvable in-memory derive
    /// instead of publishing a durable ID that a relaunch cannot recover.
    func testCatalogPersistenceFailureDoesNotPublishDanglingDocumentReference() async throws {
        let unwritableManifest = tempDirectory.appendingPathComponent("catalog-is-a-directory")
        try FileManager.default.createDirectory(at: unwritableManifest, withIntermediateDirectories: true)
        let catalog = LUTCatalog(fileURL: unwritableManifest)
        let scanRoot = tempDirectory.appendingPathComponent("empty-scan-root", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        let library = LUTLibrary(catalog: catalog)
        library.setFolder(scanRoot)
        let viewModel = AppViewModel(
            engine: FakeRenderEngine(),
            library: library
        )
        while library.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        let (derived, _) = try deriveAndSelect(on: viewModel)
        let destination = scanRoot.appendingPathComponent("Saved-but-unregistered.cube")

        XCTAssertFalse(try viewModel.derive.save(to: destination))

        XCTAssertEqual(viewModel.document.lut.lutID, derived.lutID)
        XCTAssertTrue(viewModel.document.lut.lutID?.isDerived == true)
        XCTAssertTrue(catalog.records.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    /// Re-pointing has to reach the screen.
    ///
    /// The saved file is the `%.6f`-rounded copy of the in-memory cube, so the moment the document
    /// starts referencing the file is the moment the preview should start showing what the file
    /// actually holds. Found by mutation: dropping `schedulePreview()` from `adoptSavedLUT` left the
    /// whole suite green, because every other assertion reads state rather than renders.
    ///
    /// Matched on the *saved* ID rather than on "the last request" — several renders are in flight
    /// after a save (the scan fires too), and a loose match would be satisfied by the pre-save one.
    func testRepointingAfterASaveRendersAgain() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        viewModel.openImage(url: try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "shot.png", in: tempDirectory
        ))
        let opened = Date().addingTimeInterval(5)
        while await fake.previewRequests.isEmpty {
            if Date() > opened { return XCTFail("the image never rendered") }
            try await Task.sleep(for: .milliseconds(10))
        }

        _ = try deriveAndSelect(on: viewModel)
        let destination = tempDirectory.appendingPathComponent("Keeper.cube")
        XCTAssertTrue(try viewModel.derive.save(to: destination))

        let savedID = try XCTUnwrap(viewModel.document.lut.lutID)
        let deadline = Date().addingTimeInterval(5)
        while await !fake.previewRequests.contains(where: { $0.lutID == savedID }) {
            if Date() > deadline {
                let seen = await fake.previewRequests.map { $0.lutID?.raw ?? "nil" }
                return XCTFail("no render used the saved LUT; saw \(seen)")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// A scan that finds nothing still changed the folder under the engine's cache.
    ///
    /// Found by mutation: gating `onScanned` on `scanError == nil` left everything green. Deleting
    /// the `.cube` a cached filter was built from is a failed scan *and* a reason to drop the cache,
    /// so the failure path is exactly the one that must not be skipped.
    func testAFailedScanStillInvalidatesTheLUTCache() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        let empty = tempDirectory.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let before = await fake.invalidateCount
        viewModel.library.setFolder(empty)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(viewModel.library.scanError, "precondition: an empty folder is a scan failure")

        let deadline = Date().addingTimeInterval(2)
        while await fake.invalidateCount == before {
            if Date() > deadline { return XCTFail("a failed scan did not invalidate the LUT cache") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Saving one derive must not re-point a document that is showing a *different* LUT. The user
    /// can derive, select something else from the sidebar, then save the derive from the still-open
    /// sheet.
    func testSavingDoesNotRepointADocumentShowingADifferentLUT() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "Library.cube", in: tempDirectory)
        viewModel.library.setFolder(tempDirectory)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }

        _ = try deriveAndSelect(on: viewModel)
        let fromLibrary = try XCTUnwrap(viewModel.library.allLUTs.first)
        viewModel.selectLUT(fromLibrary)

        let destination = tempDirectory.appendingPathComponent("Keeper.cube")
        XCTAssertTrue(try viewModel.derive.save(to: destination))

        XCTAssertEqual(viewModel.document.lut.lutID, fromLibrary.lutID,
                       "saving the derive must not steal the selection from the LUT on screen")
    }

    // MARK: - LUT filter cache

    /// A durable LUT record keeps its identity when its `.cube` is replaced in place, so the engine
    /// can keep serving the filter it built from the old contents.
    ///
    /// Step 9 makes that reachable: save a derive to `X.cube`, derive again, save over `X.cube`. Same
    /// record, refreshed content, stale cube on screen unless the cache is dropped.
    ///
    /// Asserted through the fake because the real engine's cache is behind an actor and the question
    /// here is not whether the cache works — `RenderEngineTests` covers that — but whether the app
    /// ever asks. Before Step 9 the only caller of `invalidateLUTCache` was a test.
    func testALibraryScanInvalidatesTheEngineLUTCache() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "A.cube", in: tempDirectory)

        let before = await fake.invalidateCount
        viewModel.library.setFolder(tempDirectory)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }

        // The invalidation is dispatched from the scan's completion, so let it land.
        let deadline = Date().addingTimeInterval(2)
        while await fake.invalidateCount == before {
            if Date() > deadline { return XCTFail("a library scan never invalidated the LUT cache") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// ...but not on every render, which would make the cache pointless. The cache exists because a
    /// 65³ cube is ~4.4 MB to hand Core Image, and an intensity drag is many renders.
    func testRenderingDoesNotInvalidateTheLUTCache() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        viewModel.openImage(url: try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "shot.png", in: tempDirectory
        ))
        let deadline = Date().addingTimeInterval(5)
        while await fake.previewRequests.isEmpty {
            if Date() > deadline { return XCTFail("no render happened") }
            try await Task.sleep(for: .milliseconds(10))
        }
        viewModel.selectLUT(TestImages.warmLUT())
        try await Task.sleep(for: .milliseconds(50))

        let invalidations = await fake.invalidateCount
        XCTAssertEqual(invalidations, 0, "rendering must not drop the cube-filter cache")
    }

    // MARK: - Passthroughs

    func testExportFormatPassesThroughToTheCoordinator() {
        let viewModel = AppViewModel()
        XCTAssertEqual(viewModel.exportFormat, viewModel.export.format)

        viewModel.exportFormat = .tiff
        XCTAssertEqual(viewModel.export.format, .tiff,
                       "the toolbar picker writes through to the coordinator")
    }

    func testIsExportingReflectsTheCoordinator() {
        let viewModel = AppViewModel()
        XCTAssertFalse(viewModel.isExporting)
        XCTAssertEqual(viewModel.isExporting, viewModel.export.isExporting)
    }

    // MARK: - Export naming

    func testExportDialogNameUsesSourceAndLUT() throws {
        // Exercises the naming the export panel is seeded with, without the panel.
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "My Look.cube", in: tempDirectory
        )
        let lut = try CubeLUT(url: url)
        XCTAssertEqual(
            ExportCoordinator.defaultFileName(source: "R0010966", lut: lut, format: .jpeg),
            "R0010966_My_Look.jpg"
        )
    }

    // MARK: - Menu forwarding

    /// The menu bar reaches the app through notifications, so these forwards
    /// are the only thing connecting File ▸ Derive to the sheet.
    func testPresentAndDismissRecipeExtractorForwardToTheCoordinator() {
        let viewModel = AppViewModel()

        viewModel.presentRecipeExtractor()
        XCTAssertTrue(viewModel.derive.isSheetPresented)

        viewModel.dismissRecipeExtractor()
        XCTAssertFalse(viewModel.derive.isSheetPresented)
    }

    func testExportDialogWithNoImageTellsTheUserInsteadOfOpeningAPanel() {
        let viewModel = AppViewModel()
        XCTAssertNil(viewModel.sourceImage)

        // Must return without ever constructing a panel — if this hangs, the
        // guard has regressed and a modal is up.
        viewModel.exportDialog()
        XCTAssertEqual(viewModel.statusMessage, "Open an image first")
    }

    func testBatchExportWithNoImagesTellsTheUserInsteadOfOpeningAPanel() {
        let viewModel = AppViewModel()
        XCTAssertTrue(viewModel.collection.items.isEmpty)

        viewModel.batchExportDialog()
        XCTAssertEqual(
            viewModel.statusMessage,
            "Import a set of images first (Export All works on the filmstrip)"
        )
    }
}
