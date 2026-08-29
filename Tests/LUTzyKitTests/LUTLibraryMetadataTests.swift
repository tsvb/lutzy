import XCTest
import CoreImage
@testable import LUTzyKit

final class LUTLibraryMetadataTests: TempDirectoryTestCase {
    func testBuiltInSampleSetIsFixedAndResolvable() throws {
        XCTAssertEqual(
            LUTLibrarySample.all.map(\.id),
            ["panasonic-s9", "portrait", "outdoor", "mixed", "saturated"]
        )
        XCTAssertEqual(LUTLibrarySample.default.id, "panasonic-s9")
        XCTAssertTrue(LUTLibrarySample.all.allSatisfy { $0.sourceSpace == .display })
        for sample in LUTLibrarySample.all {
            XCTAssertNotNil(sample.url, "missing bundled sample \(sample.filename)")
            XCTAssertNotNil(sample.imageSource)
            XCTAssertFalse(sample.colorProfile.isEmpty)
        }
    }

    func testGalleryTagsPreferTypedThenMeasuredAndStopAtThree() {
        XCTAssertEqual(
            LUTGalleryMetadata.visibleTags(
                typed: ["warm", "cinema"],
                measured: ["soft", "contrast", "warm", "input:vlog"]
            ),
            ["cinema", "warm", "contrast"]
        )
        XCTAssertEqual(
            LUTGalleryMetadata.visibleTags(typed: [], measured: ["z", "a", "m", "b"]),
            ["a", "b", "m"]
        )
    }

    @MainActor
    func testDisplayNameFallsBackToFilenameAndEmptyOverrideResetsIt() throws {
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Filename Look.cube", in: tempDirectory
        )
        let catalog = LUTCatalog(fileURL: tempDirectory.appendingPathComponent("catalog.json"))
        let parsed = try CubeLUT(url: url)
        let id = try XCTUnwrap(catalog.adoptSavedLUT(parsed))
        let durable = parsed.withRecordID(id)

        XCTAssertEqual(catalog.effectiveName(for: durable), "Filename Look")
        catalog.setDisplayName("Soft Portrait", for: [id])
        XCTAssertEqual(catalog.effectiveName(for: durable), "Soft Portrait")
        catalog.setDisplayName("   ", for: [id])
        XCTAssertEqual(catalog.effectiveName(for: durable), "Filename Look")
    }

    func testFilenameDerivedDisplayNameRemovesExportNoiseWithoutLosingTechnicalTokens() {
        XCTAssertEqual(LUTDisplayName.normalized("Warm_18.A049_12291747_S"), "Warm 18")
        XCTAssertEqual(LUTDisplayName.normalized("WOODEN_GOLD__20.C0021"), "WOODEN GOLD 20")
        XCTAssertEqual(LUTDisplayName.normalized("00_Gara_CineLut03"), "Gara CineLut03")
        XCTAssertEqual(
            LUTDisplayName.normalized("1_25.A002_02161553_C053", brand: "FreshLUTs"),
            "FreshLUTs Look 1"
        )
        XCTAssertEqual(
            LUTDisplayName.normalized("1_SGamut3CineSLog3_To_LC-709"),
            "SGamut3CineSLog3 To LC-709"
        )
        XCTAssertEqual(LUTDisplayName.normalized("65MM_FILM_01"), "65MM FILM 01")
        XCTAssertEqual(LUTDisplayName.normalized("12 Years a Slave"), "12 Years a Slave")
        XCTAssertEqual(LUTDisplayName.normalized("Look.v2024"), "Look.v2024")
        XCTAssertEqual(LUTDisplayName.normalized("Look.V2024"), "Look.V2024")
        XCTAssertEqual(LUTDisplayName.normalized("1.1", brand: "FreshLUTs"), "FreshLUTs Look 1.1")
        XCTAssertEqual(LUTDisplayName.normalized("1.2", brand: "FreshLUTs"), "FreshLUTs Look 1.2")
    }

    func testSplitToneAngleUsesTheShortArcAroundTheHueCircle() {
        XCTAssertEqual(LUTSimilarity.circularHueDistance(350, 10), 20, accuracy: 0.0001)
        XCTAssertEqual(LUTSimilarity.circularHueDistance(10, 350), 20, accuracy: 0.0001)
        XCTAssertEqual(LUTSimilarity.circularHueDistance(20, 200), 180, accuracy: 0.0001)
    }

    func testManagerSelectionSummaryExposesCommonMixedAndTriStateMetadata() {
        let first = LUTID(recordUUID: UUID())
        let second = LUTID(recordUUID: UUID())
        let records = [
            LUTRecord(
                id: first, locator: "/first.cube", fingerprint: "same", isAvailable: true,
                origin: .vendor("Acme"), typedTags: ["soft", "warm"], isStarred: true
            ),
            LUTRecord(
                id: second, locator: "/second.cube", fingerprint: "other", isAvailable: true,
                origin: .custom, typedTags: ["mono", "soft"], isStarred: false
            ),
        ]

        let state = LUTManagerSelectionState(
            records: records,
            visibleTagsByRecordID: [
                first: ["soft", "warm", "標準對比"],
                second: ["mono", "soft", "標準對比"],
            ]
        )

        XCTAssertEqual(state.commonTags, ["soft", "標準對比"])
        XCTAssertEqual(state.mixedTags, ["mono", "warm"])
        XCTAssertNil(state.commonOrigin)
        XCTAssertFalse(state.allStarred)
        XCTAssertEqual(state.membership(in: []), .none)
        XCTAssertEqual(state.membership(in: [first]), .mixed)
        XCTAssertEqual(state.membership(in: [first, second]), .all)
    }

    @MainActor
    func testRemovingVisibleMeasuredTagHidesItAndAddingItRestoresOneTypedValue() throws {
        let cubeURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "candidate.cube", in: tempDirectory
        )
        let catalog = LUTCatalog(fileURL: tempDirectory.appendingPathComponent("catalog.json"))
        let parsed = try CubeLUT(url: cubeURL)
        let id = try XCTUnwrap(catalog.adoptSavedLUT(parsed))
        let lut = parsed.withRecordID(id)
        let tagStore = LUTTagStore(fileURL: tempDirectory.appendingPathComponent("tags.json"))
        tagStore.indexNow([lut])
        let tag = try XCTUnwrap(tagStore.measuredTags(for: lut).first { $0.hasPrefix("input:") == false })
        let library = LUTLibrary(catalog: catalog)
        let viewModel = AppViewModel(
            projects: ProjectStore(root: tempDirectory.appendingPathComponent("Projects")),
            tags: tagStore,
            media: MediaLibrary(
                root: tempDirectory.appendingPathComponent("Media"),
                manifestURL: tempDirectory.appendingPathComponent("media.json")
            ),
            library: library
        )

        XCTAssertTrue(viewModel.allTags(for: lut).contains(tag))
        viewModel.removeTag(tag, from: lut)
        XCTAssertFalse(viewModel.allTags(for: lut).contains(tag))

        viewModel.addTag(tag, to: [lut])
        XCTAssertEqual(viewModel.allTags(for: lut).filter { $0 == tag }.count, 1)
        XCTAssertEqual(catalog.typedTags(for: lut), [tag])
        XCTAssertEqual(catalog.excludedMeasuredTags(for: lut), [])
    }

    @MainActor
    func testLibraryPreviewRequestNeverInheritsViewerState() async throws {
        let cubeURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "candidate.cube", in: tempDirectory
        )
        let lut = try CubeLUT(url: cubeURL)
        let engine = FakeRenderEngine()
        let projects = ProjectStore(root: tempDirectory.appendingPathComponent("Projects"))
        let tags = LUTTagStore(fileURL: tempDirectory.appendingPathComponent("tags.json"))
        let media = MediaLibrary(
            root: tempDirectory.appendingPathComponent("Media"),
            manifestURL: tempDirectory.appendingPathComponent("media.json")
        )
        let viewModel = AppViewModel(engine: engine, projects: projects, tags: tags, media: media)
        viewModel.setSourceSpace(.vlog)
        viewModel.setLUTIntensity(0.18)
        viewModel.section = .lutLibrary

        _ = await viewModel.makeLUTGalleryPreview(
            for: lut, maxSize: CGSize(width: 320, height: 200)
        )
        let requests = await engine.previewRequests
        let request = try XCTUnwrap(requests.last)

        XCTAssertEqual(request.lutID, lut.lutID)
        XCTAssertEqual(request.document.rawDevelop, .neutral)
        XCTAssertTrue(request.document.adjustments.isEmpty)
        XCTAssertEqual(request.document.lut.intensity, 1)
        XCTAssertEqual(request.document.sourceSpace, .display)
        XCTAssertEqual(request.source, viewModel.selectedLibrarySample.imageSource)
    }

    func testViewerAutoAndExplicitLibraryBaselineProduceSamePixels() async throws {
        let sample = try XCTUnwrap(LUTLibrarySample.all.first)
        let source = try XCTUnwrap(sample.imageSource)
        let engine = RenderEngine(context: CIContext(options: [.useSoftwareRenderer: true]))

        let displayLUT = TestImages.warmLUT(size: 4, name: "display-look")
        let vlogURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 4), named: "reference-vlog.cube", in: tempDirectory
        )
        let vlogLUT = try CubeLUT(url: vlogURL)
        XCTAssertEqual(vlogLUT.inputSpace, .vlog)

        for lut in [displayLUT, vlogLUT] {
            var viewer = EditDocument()
            viewer.lut = LUTSettings(lutID: lut.lutID, intensity: 1)
            viewer.sourceSpace = .auto
            var library = viewer
            library.sourceSpace = .display

            let renderedViewer = await engine.makeCGImage(
                source: source, document: viewer, lut: lut,
                scale: .preview(maxSize: CGSize(width: 480, height: 320)), space: .sRGB
            )
            let renderedLibrary = await engine.makeCGImage(
                source: source, document: library, lut: lut,
                scale: .preview(maxSize: CGSize(width: 480, height: 320)), space: .sRGB
            )
            let viewerImage = try XCTUnwrap(renderedViewer)
            let libraryImage = try XCTUnwrap(renderedLibrary)
            assertPixelsEqual(
                try Pixels.bytes(of: viewerImage), try Pixels.bytes(of: libraryImage),
                "Viewer and LUT Library must share the same neutral sample render for \(lut.name)"
            )
        }
    }
}
