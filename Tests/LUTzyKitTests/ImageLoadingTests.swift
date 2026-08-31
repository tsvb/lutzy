import XCTest
import CoreImage
import ImageIO
@testable import LUTzyKit

/// Regression coverage for B1 — EXIF orientation being ignored on every non-RAW
/// load, so a portrait photo previewed and exported on its side while its own
/// filmstrip thumbnail stood upright.
///
/// The trap is that `CIImage(contentsOf:)` does not honor the orientation tag
/// but `CIRAWFilter` and `CGImageSourceCreateThumbnailAtIndex(…WithTransform)`
/// both do — so the bug only shows when two paths are compared, which is
/// exactly what these tests do.
final class ImageLoadingTests: TempDirectoryTestCase {

    /// Every quarter-turn orientation, and one that isn't.
    private let quarterTurns = [5, 6, 7, 8]
    private let upright = 1

    func testLoadFromURLAppliesOrientation() throws {
        // A landscape 80×60 buffer tagged "rotate to portrait".
        for orientation in quarterTurns {
            let url = try Fixtures.writeJPEG(
                width: 80, height: 60, orientation: orientation,
                named: "portrait-\(orientation).jpg", in: tempDirectory
            )
            XCTAssertEqual(Fixtures.storedSize(of: url), CGSize(width: 80, height: 60),
                           "fixture should keep a landscape pixel buffer")

            let image = try ImageDecoder.load(from: url)
            XCTAssertEqual(image.extent.width, 60,
                           "orientation \(orientation) should display 60 wide")
            XCTAssertEqual(image.extent.height, 80,
                           "orientation \(orientation) should display 80 tall")
        }
    }

    func testLoadFromURLLeavesUprightImagesAlone() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: upright,
            named: "landscape.jpg", in: tempDirectory
        )
        let image = try ImageDecoder.load(from: url)
        XCTAssertEqual(image.extent.width, 80)
        XCTAssertEqual(image.extent.height, 60)
    }

    /// The Photos-import path decodes from `Data`, not a URL, and had the same
    /// defect independently.
    func testLoadFromDataAppliesOrientation() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "fromdata.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let image = try ImageDecoder.load(from: data, name: "fromdata.jpg")
        XCTAssertEqual(image.extent.width, 60)
        XCTAssertEqual(image.extent.height, 80)
    }

    func testLoadFromDataThrowsOnGarbage() {
        let garbage = Data("not an image".utf8)
        XCTAssertThrowsError(try ImageDecoder.load(from: garbage, name: "bad.txt"))
    }

    func testLoadFromURLThrowsOnMissingFile() {
        let missing = tempDirectory.appendingPathComponent("nope.jpg")
        XCTAssertThrowsError(try ImageDecoder.load(from: missing))
    }

    /// The heart of the bug: preview and thumbnail disagreed. They must agree
    /// on which way is up, or the filmstrip contradicts the canvas.
    func testPreviewAndThumbnailAgreeOnOrientation() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "agree.jpg", in: tempDirectory
        )
        let loaded = try ImageDecoder.load(from: url)
        let thumbnail = try XCTUnwrap(Thumbnails.generate(from: url))

        let loadedIsPortrait = loaded.extent.height > loaded.extent.width
        let thumbIsPortrait = thumbnail.size.height > thumbnail.size.width
        XCTAssertEqual(loadedIsPortrait, thumbIsPortrait,
                       "canvas and filmstrip must not disagree about orientation")
        XCTAssertTrue(loadedIsPortrait, "both should be portrait for orientation 6")
    }

    /// Exports were written sideways too, which is the part a user can't undo.
    ///
    /// Driven through `RenderEngine` since Step 7 deleted `ImageProcessor.export`. That matters for
    /// what this covers: the encoder no longer receives an already-decoded image, it decodes the
    /// source itself through `RenderPipeline.developedSource`, so this now pins that *that* decode
    /// bakes the orientation too.
    func testExportPreservesDisplayOrientation() async throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "toexport.jpg", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 60, height: 80))
        let engine = RenderEngine()

        for format in ExportFormat.allCases {
            let out = tempDirectory.appendingPathComponent("out.\(format.fileExtension)")
            let data = try await engine.encode(
                source: source, document: EditDocument(), lut: nil, scale: .full,
                format: format, quality: 0.95, space: .current
            )
            try data.write(to: out)
            XCTAssertEqual(Fixtures.storedSize(of: out), CGSize(width: 60, height: 80),
                           "\(format.rawValue) export should be written upright")
        }
    }

    func testMetadataReportsDisplayDimensions() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "meta.jpg", in: tempDirectory
        )
        let metadata = ImageMetadata.read(from: url)
        XCTAssertEqual(metadata.pixelWidth, 60, "inspector should report what's on screen")
        XCTAssertEqual(metadata.pixelHeight, 80)
    }

    func testMetadataFromDataMatchesMetadataFromURL() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "both.jpg", in: tempDirectory
        )
        let fromURL = ImageMetadata.read(from: url)
        let fromData = ImageMetadata.read(from: try Data(contentsOf: url))
        XCTAssertEqual(fromURL.pixelWidth, fromData.pixelWidth)
        XCTAssertEqual(fromURL.pixelHeight, fromData.pixelHeight)
    }

    /// Opening a RAW must produce the neutral baseline — the render that the whole migration
    /// promises not to move, and the one `RecipeExtractor` fits its cubes against.
    ///
    /// **What this cannot tell you, measured rather than assumed.** `ImageDecoder.load` routes RAW
    /// through `CIRAWFilter` and everything else through `CIImage(contentsOf:)`, and a mutation that
    /// deleted that branch *survived* this test. Probing the two decoders directly on the local
    /// Leica DNG explains why: they produce the same demosaic, with a worst per-byte delta of **1**
    /// and 3.3% of bytes off by one — inside the house tolerance. ImageIO reads a DNG through the
    /// same RAW pipeline at default settings.
    ///
    /// So the branch is not load-bearing for DNG at neutral. It is load-bearing for RAW formats
    /// ImageIO will not open bare (`CIImage(contentsOf:)` returns nil and `load` would throw
    /// `cannotLoad`), and no fixture in this repo can exercise that — the same limitation
    /// `docs/CODE_REVIEW.md` §5 records for the `is*Supported` gates. What this test *does* pin is
    /// that `load` and `developRAWNeutral` stay in agreement, which is what would break if someone
    /// taught the eager decode to apply develop settings.
    ///
    /// Skipped without a local RAW, like every other `CIRAWFilter` test here.
    func testLoadingARAWGoesThroughCIRAWFilter() throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW to decode; see Fixtures.localRAWURL")
        }
        // Interleaved rather than sequential: Core Image is not bit-reproducible across
        // time-separated runs, so the two renders are taken next to each other.
        let viaLoad = try ImageDecoder.load(from: rawURL)
        let viaNeutral = try XCTUnwrap(ImageDecoder.developRAWNeutral(at: rawURL))

        XCTAssertEqual(viaLoad.extent, viaNeutral.extent)
        assertPixelsEqual(try Pixels.bytes(of: viaLoad), try Pixels.bytes(of: viaNeutral),
                          "opening a RAW must demosaic it, not hand it to the standard decoder")
    }

    // MARK: - Format routing

    /// `supportedExtensions` is the single source of truth shared by the open
    /// panel and the folder scanner; RAW and standard sets must stay disjoint
    /// or `loadImage` would route a file down the wrong decoder.
    func testSupportedExtensionsCoverRAWAndStandard() {
        XCTAssertTrue(ImageDecoder.supportedExtensions.contains("dng"))
        XCTAssertTrue(ImageDecoder.supportedExtensions.contains("jpg"))
        XCTAssertTrue(ImageDecoder.supportedExtensions.contains("heic"))
        XCTAssertFalse(ImageDecoder.supportedExtensions.contains("cube"))
        XCTAssertFalse(ImageDecoder.supportedExtensions.contains("pdf"))

        XCTAssertTrue(ImageDecoder.rawExtensions.isSubset(of: ImageDecoder.supportedExtensions))
        XCTAssertFalse(ImageDecoder.rawExtensions.contains("jpg"),
                       "a RAW/standard overlap would send JPEGs through CIRAWFilter")
        XCTAssertTrue(ImageDecoder.supportedExtensions.allSatisfy { $0 == $0.lowercased() },
                      "extensions are matched lowercased at the call sites")
    }

    func testSupportedTypesIncludeRawAndAreUnique() {
        let identifiers = ImageDecoder.supportedTypes.map(\.identifier)
        XCTAssertTrue(identifiers.contains("public.camera-raw-image"))
        XCTAssertEqual(identifiers.count, Set(identifiers).count, "open panel types should not repeat")
    }

    // MARK: - B16: a RAW that does not decode must not open

    /// `CIRAWFilter` is far more permissive than `CIImage(contentsOf:)`, and the decoder's `nil` check
    /// was written as though they behaved alike.
    ///
    /// Measured: handed twelve bytes of ASCII text named `.dng`, `CIRAWFilter(imageURL:)` constructs a
    /// filter **and** returns an `outputImage` — extent `(inf, inf, 0.0, 0.0)`. Nothing was `nil`, so
    /// `ImageDecoder.load` returned it as a valid image. The failure was quiet rather than loud,
    /// because the render paths guard on `isRasterizable` downstream: the file "opened", the status
    /// bar read `0×0`, the preview stayed blank, and no error was ever shown.
    ///
    /// This is the same decoder-leniency shape as B1 (orientation) and B12 (degenerate LUT domain):
    /// a framework accepting input that the code assumed it would reject.
    ///
    /// Runs on CI — the fixture is a text file, not a RAW.
    func testAnUndecodableRAWThrowsRatherThanOpeningAtZeroSize() throws {
        let url = tempDirectory.appendingPathComponent("truncated.dng")
        try Data("not an image".utf8).write(to: url)

        // The precondition that makes this test necessary: the nil check alone does not catch it.
        let lenient = ImageDecoder.developRAWNeutral(at: url)
        XCTAssertNotNil(lenient, "if CIRAWFilter ever starts returning nil here, this test still holds "
                        + "but its reason for existing has changed — check before simplifying it")
        XCTAssertFalse(lenient?.extent.isRasterizable ?? true, "the lenient decode is the degenerate one")

        XCTAssertThrowsError(try ImageDecoder.load(from: url)) { error in
            guard case ImageError.cannotLoad = error else {
                return XCTFail("expected .cannotLoad, got \(error)")
            }
        }
    }

    /// The other half: a real RAW must still load. Without this, B16's fix is satisfiable by
    /// rejecting every RAW.
    func testARealRAWStillLoads() throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW; see Fixtures.localRAWURL")
        }
        let image = try ImageDecoder.load(from: rawURL)
        XCTAssertTrue(image.extent.isRasterizable, "a real RAW must survive the B16 extent check")
    }

    // MARK: - Where the preview-scaling tests went
    //
    // `testRenderPreviewCapsSizeAndPreservesAspect` and `testRenderPreviewDoesNotUpscale` drove
    // `ImageProcessor.renderPreview`, which Step 7 deleted. Downscaling is `RenderScale`'s job now
    // and happens *before* the filter graph rather than after it, so the properties are pinned where
    // that decision is made: `RenderPipelineTests.testPreviewScaleFitsTheBoxAndFullDoesNot` and
    // `testPreviewLargerThanTheSourceDoesNotUpscale`, plus
    // `RenderEngineTests.testScaleIsTheOnlyDifferenceBetweenPreviewAndFull` at the rasterizer.
}
