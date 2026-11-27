import XCTest
import CoreImage
import CoreGraphics
import UniformTypeIdentifiers
@testable import LUTzyKit

/// Phase 2 Step 4. The engine is the only thing in the stack that owns a `CIContext`, so what is
/// worth pinning is the boundary rather than the arithmetic — the pipeline's maths already has its
/// own suite.
///
/// The headline property is **preview/export parity**. Today `renderPreview` and `export` are two
/// code paths that merely agree; after the cutover they are one `buildImage` call and one rasterizer,
/// differing only in `RenderScale`. This is where that stops being an aspiration.
final class RenderEngineTests: TempDirectoryTestCase {

    private var sourceURL: URL!
    private var source: ImageSource!

    override func setUpWithError() throws {
        try super.setUpWithError()
        sourceURL = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "src.png", in: tempDirectory)
        source = ImageSource(url: sourceURL, nativeExtent: CGSize(width: 96, height: 64))
    }

    /// `XCTUnwrap` takes an autoclosure, which cannot contain `await` — so the actor hop happens
    /// here and the unwrap happens after it.
    private func render(
        _ engine: RenderEngine,
        _ document: EditDocument,
        lut: CubeLUT? = nil,
        scale: RenderScale = .full,
        space: WorkingSpace = .current
    ) async throws -> CGImage {
        let image = await engine.makeCGImage(
            source: source, document: document, lut: lut, scale: scale, space: space
        )
        return try XCTUnwrap(image)
    }

    // MARK: - Cancellation

    /// **A cancelled request skips the GPU.** An actor hop is not a cancellation point, so a caller
    /// cancelled while queued behind another render still reaches the engine — and before this check
    /// it was rasterized in full and thrown away, once per LUT on a held ↓ and once per image on a
    /// held →. The task cancels itself before calling, so the outcome is decided, not raced.
    ///
    /// The control half matters as much: an engine that returned `nil` for everything would satisfy
    /// the first two assertions.
    func testACancelledRequestSkipsTheRender() async throws {
        let engine = RenderEngine()
        let source: ImageSource = self.source

        let previewSkipped = await Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            let image = await engine.makeCGImage(
                source: source, document: EditDocument(), lut: nil, scale: .full, space: .current
            )
            return image == nil
        }.value
        XCTAssertTrue(previewSkipped, "a cancelled preview request was rendered anyway")

        let histogramSkipped = await Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            let tally = await engine.histogram(
                source: source, document: EditDocument(), lut: nil, scale: .full, space: .current,
                maxDimension: 64
            )
            return tally == nil
        }.value
        XCTAssertTrue(histogramSkipped, "a cancelled histogram request was tallied anyway")

        // Control: the same requests, uncancelled, still produce something.
        _ = try await render(engine, EditDocument())
        let tally = await engine.histogram(
            source: source, document: EditDocument(), lut: nil, scale: .full, space: .current,
            maxDimension: 64
        )
        XCTAssertNotNil(tally, "the uncancelled histogram must still tally")
    }

    // MARK: - Parity

    /// The whole point of Phase 2, asserted directly: the same document rendered for display and
    /// encoded for export must be the same pixels. Not "close" — the same graph, the same rasterizer,
    /// one scale value apart.
    ///
    /// PNG because it is lossless; a JPEG comparison would be measuring the encoder.
    func testPreviewAndExportAreTheSamePixels() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(
            adjustments: [.exposure(ev: 0.3), .vibrance(amount: 0.4)],
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.8)
        )

        let preview = try await render(engine, document, lut: lut)
        let exported = try await engine.encode(
            source: source, document: document, lut: lut, scale: .full,
            format: .png, quality: 1, space: .current
        )
        let decoded = try Pixels.decode(exported)

        XCTAssertEqual(preview.width, decoded.width)
        XCTAssertEqual(preview.height, decoded.height)
        assertPixelsEqual(try Pixels.bytes(of: preview), try Pixels.bytes(of: decoded),
                          "preview and export must rasterize to the same pixels")
    }

    /// And parity has to hold in a *non-default* space, or the test above would pass for a pipeline
    /// that hard-coded sRGB in both halves — which is precisely the bug Step 1 fixed.
    func testParityHoldsInEveryWorkingSpace() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 1))

        for space in WorkingSpace.allCases {
            let preview = try await render(engine, document, lut: lut, space: space)
            let exported = try await engine.encode(
                source: source, document: document, lut: lut, scale: .full,
                format: .png, quality: 1, space: space
            )
            assertPixelsEqual(try Pixels.bytes(of: preview),
                              try Pixels.bytes(of: try Pixels.decode(exported)),
                              "preview and export disagree in \(space.rawValue)")
        }
    }

    /// The engine rasterizes exactly the graph `RenderPipeline` builds — it does not resize, crop or
    /// re-grade on the way out.
    ///
    /// Run in **both** spaces on purpose. Parity alone cannot catch an engine that passes the wrong
    /// space to the graph builder, because both halves would then be wrong *together* and still agree
    /// with each other — which is exactly what a mutation demonstrated. Comparing against a graph
    /// built independently in the same space is what pins the interpolation half.
    func testTheEngineRasterizesThePipelineGraphUnchanged() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(
            adjustments: [.colorControls(brightness: 0.1, contrast: 1.3, saturation: 0.7)],
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.5)
        )

        for space in WorkingSpace.allCases {
            let viaEngine = try await render(engine, document, lut: lut, space: space)
            let graph = try XCTUnwrap(RenderPipeline.buildImage(
                source: source, document: document, lut: lut, scale: .full, space: space
            ))

            assertPixelsEqual(try Pixels.bytes(of: viaEngine),
                              try Pixels.bytes(of: graph, space: space),
                              "the engine should evaluate the graph unchanged in \(space.rawValue)")
        }
    }

    /// And the cube really is interpolated in the requested space when driven through the engine —
    /// the same assertion Step 3 makes of the pipeline, repeated here because the engine is a second
    /// place the argument could be dropped.
    func testTheWorkingSpaceReachesTheCubeThroughTheEngine() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 1))

        // Both graphs rasterized through sRGB, so only the interpolation differs.
        let inSRGB = try XCTUnwrap(RenderPipeline.buildImage(
            source: source, document: document, lut: lut, scale: .full, space: .sRGB
        ))
        let inP3 = try XCTUnwrap(RenderPipeline.buildImage(
            source: source, document: document, lut: lut, scale: .full, space: .displayP3
        ))
        assertPixelsDiffer(try Pixels.bytes(of: inSRGB, space: .sRGB),
                           try Pixels.bytes(of: inP3, space: .sRGB),
                           "the interpolation space must change the cube's result")

        // The engine's own output in each space must match its corresponding graph.
        let engineSRGB = try await render(engine, document, lut: lut, space: .sRGB)
        assertPixelsEqual(try Pixels.bytes(of: engineSRGB), try Pixels.bytes(of: inSRGB, space: .sRGB),
                          "the engine's sRGB render should match an sRGB-interpolated graph")
    }

    // MARK: - Scale

    func testScaleIsTheOnlyDifferenceBetweenPreviewAndFull() async throws {
        let engine = RenderEngine()

        let full = try await render(engine, EditDocument())
        let preview = try await render(
            engine, EditDocument(), scale: .preview(maxSize: CGSize(width: 32, height: 32))
        )

        XCTAssertEqual(full.width, 96)
        XCTAssertEqual(full.height, 64)
        XCTAssertLessThanOrEqual(preview.width, 32)
        XCTAssertLessThanOrEqual(preview.height, 32)
        XCTAssertGreaterThan(preview.width, 0)
    }

    // MARK: - Encoding

    func testEveryFormatEncodesToItsOwnType() async throws {
        let engine = RenderEngine()
        let expected: [ExportFormat: UTType] = [
            .png: .png, .jpeg: .jpeg, .tiff: .tiff,
        ]

        for (format, type) in expected {
            let data = try await engine.encode(
                source: source, document: EditDocument(), lut: nil, scale: .full,
                format: format, quality: 0.95, space: .current
            )
            XCTAssertFalse(data.isEmpty, "\(format) produced no bytes")

            let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let uti = try XCTUnwrap(CGImageSourceGetType(imageSource) as String?)
            XCTAssertEqual(UTType(uti), type, "\(format) encoded as \(uti)")
        }
    }

    /// The output-encoding half of the colour seam has to reach the encoder — if it were dropped,
    /// both files would carry the same profile.
    func testTheWorkingSpaceReachesTheEncoder() async throws {
        let engine = RenderEngine()

        let sRGB = try await engine.encode(
            source: source, document: EditDocument(), lut: nil, scale: .full,
            format: .png, quality: 1, space: .sRGB
        )
        let p3 = try await engine.encode(
            source: source, document: EditDocument(), lut: nil, scale: .full,
            format: .png, quality: 1, space: .displayP3
        )

        let sRGBName = try Pixels.decode(sRGB).colorSpace?.name as String?
        let p3Name = try Pixels.decode(p3).colorSpace?.name as String?
        XCTAssertEqual(sRGBName, CGColorSpace.sRGB as String)
        XCTAssertEqual(p3Name, CGColorSpace.displayP3 as String)
        XCTAssertNotEqual(sRGBName, p3Name)
    }

    // MARK: - Failure

    func testAnUndecodableSourceIsNilForPreviewAndThrowsForExport() async throws {
        let engine = RenderEngine()
        let junk = ImageSource(backing: .data(Data("not an image".utf8)), kind: .standard, nativeExtent: .zero)

        let preview = await engine.makeCGImage(
            source: junk, document: EditDocument(), lut: nil, scale: .full, space: .current
        )
        XCTAssertNil(preview)

        do {
            _ = try await engine.encode(
                source: junk, document: EditDocument(), lut: nil, scale: .full,
                format: .png, quality: 1, space: .current
            )
            XCTFail("encoding an undecodable source should throw")
        } catch {
            // Assert on *which* failure: an unrelated error would satisfy a bare `catch`. Matched
            // by pattern rather than by `==` so `ImageError` doesn't need an `Equatable` conformance
            // it has no other use for.
            guard case ImageError.processingFailed = error else {
                return XCTFail("expected processingFailed, got \(error)")
            }
        }
    }

    // MARK: - The developed-source memo

    /// The memo exists so an intensity drag does not re-decode the file every frame (measured: 156 ms
    /// versus 0.6 ms on a 6000×4000 source). It must not be observable in the output.
    ///
    /// Two *different preview sizes* on purpose: a memo keyed on everything but the scale would
    /// serve the first size's image for the second, which a single preview render cannot detect.
    func testTheMemoIsKeyedOnThePreviewSize() async throws {
        let engine = RenderEngine()

        let small = try await render(engine, EditDocument(),
                                     scale: .preview(maxSize: CGSize(width: 32, height: 32)))
        let large = try await render(engine, EditDocument(),
                                     scale: .preview(maxSize: CGSize(width: 64, height: 64)))

        XCTAssertLessThanOrEqual(small.width, 32)
        XCTAssertEqual(large.width, 64, "a second preview size must not reuse the first's image")
        XCTAssertNotEqual(small.width, large.width)
    }

    /// And keyed on the image. A memo that ignored which source it held would keep showing the
    /// previous photo after the user stepped to the next one — invisible to any test that only ever
    /// opens one image.
    func testTheMemoIsKeyedOnTheSource() async throws {
        let engine = RenderEngine()
        let box = RenderScale.preview(maxSize: CGSize(width: 48, height: 48))

        let firstURL = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "a.png", in: tempDirectory)
        // A solid patch, so the two images cannot be confused for one another.
        let secondURL = tempDirectory.appendingPathComponent("b.png")
        let solid = try Fixtures.makeCGImage(width: 96, height: 64, red: 0.1, green: 0.9, blue: 0.2)
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(
            secondURL as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(dest, solid, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let a = ImageSource(url: firstURL, nativeExtent: CGSize(width: 96, height: 64))
        let b = ImageSource(url: secondURL, nativeExtent: CGSize(width: 96, height: 64))

        let imageA = await engine.makeCGImage(
            source: a, document: EditDocument(), lut: nil, scale: box, space: .current
        )
        let imageB = await engine.makeCGImage(
            source: b, document: EditDocument(), lut: nil, scale: box, space: .current
        )
        let renderedA = try XCTUnwrap(imageA)
        let renderedB = try XCTUnwrap(imageB)

        assertPixelsDiffer(try Pixels.bytes(of: renderedB), try Pixels.bytes(of: renderedA),
                           "opening a second image must not keep serving the first")
    }

    // MARK: - The cache lives on the actor

    /// The cube filter is built once and reused across renders. Invisible in the output by design, so
    /// it is observed through the count — a silently-bypassed cache would be pure cost.
    func testTheCubeFilterIsBuiltOnceAndReused() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 1))

        let initialCount = await engine.cachedFilterCount
        XCTAssertEqual(initialCount, 0)

        for _ in 0..<5 {
            _ = await engine.makeCGImage(
                source: source, document: document, lut: lut, scale: .full, space: .current
            )
        }
        let afterFive = await engine.cachedFilterCount
        XCTAssertEqual(afterFive, 1, "five renders of one LUT should build one filter")

        // A second space is a second entry — the cube is interpolated in the space.
        _ = await engine.makeCGImage(
            source: source, document: document, lut: lut, scale: .full, space: .displayP3
        )
        let afterP3 = await engine.cachedFilterCount
        XCTAssertEqual(afterP3, 2)

        await engine.invalidateLUTCache()
        let afterFlush = await engine.cachedFilterCount
        XCTAssertEqual(afterFlush, 0, "a rescan must be able to drop stale cubes")
    }

    /// The staleness the cache flush exists to prevent, asserted in **pixels** rather than in counts.
    ///
    /// A `LUTID` is a file path, so replacing a `.cube` in place gives a different cube under an
    /// unchanged identity. Step 9 made that reachable from the UI: save a derive to `X.cube`, derive
    /// again, save over `X.cube`. Without the flush the engine serves the first cube forever and the
    /// second save appears to do nothing.
    ///
    /// The count-based test above would pass against a flush that dropped entries and rebuilt them
    /// from a stale table, so this one drives the whole path and looks at the output. The two renders
    /// are interleaved in one process, per the repo's Core Image reproducibility rule.
    func testAReplacedCubeAtTheSamePathRendersTheNewLookAfterAFlush() async throws {
        let engine = RenderEngine()
        let path = tempDirectory.appendingPathComponent("Look.cube")

        try Fixtures.writeCube(Fixtures.identityCubeText(size: 4), named: "Look.cube", in: tempDirectory)
        let identity = try CubeLUT(url: path)
        let document = EditDocument(lut: LUTSettings(lutID: identity.lutID, intensity: 1))
        let first = try Pixels.bytes(of: try await render(engine, document, lut: identity))

        // Same path, different contents — so the same LUTID, which is the whole hazard.
        try CubeLUT.write(
            cube: TestImages.toBlackCube(size: 4), size: 4, title: "Look", to: path
        )
        let replaced = try CubeLUT(url: path)
        XCTAssertEqual(replaced.lutID, identity.lutID, "precondition: the identity did not change")

        await engine.invalidateLUTCache()
        let second = try Pixels.bytes(of: try await render(engine, document, lut: replaced))

        assertPixelsDiffer(first, second,
                           "after a flush the replaced cube must reach the screen")
    }

    // MARK: - Actor isolation

    /// The cache is a mutable reference type living inside the actor. If it ever escaped — or if the
    /// engine stopped serializing — concurrent renders would race on the filter's `inputImage`.
    ///
    /// Twenty concurrent renders of the same document must all produce the same correct pixels, and
    /// must still have built exactly one filter. Each task rasterizes to bytes *before* returning, so
    /// the non-`Sendable` `CGImage` never leaves the task that received it.
    func testConcurrentRendersAreSerializedAndCorrect() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(
            adjustments: [.exposure(ev: 0.2)],
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.6)
        )
        let expected = try Pixels.bytes(of: try await render(engine, document, lut: lut))

        let source = self.source!
        let results: [[UInt8]] = await withTaskGroup(of: [UInt8]?.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    guard let cg = await engine.makeCGImage(
                        source: source, document: document, lut: lut, scale: .full, space: .current
                    ) else { return nil }
                    return try? Pixels.bytes(of: cg)
                }
            }
            var collected: [[UInt8]] = []
            for await result in group {
                if let result { collected.append(result) }
            }
            return collected
        }

        XCTAssertEqual(results.count, 20, "every concurrent render should have produced an image")
        for (index, bytes) in results.enumerated() {
            assertPixelsEqual(bytes, expected, "concurrent render \(index) diverged")
        }
        let filterCount = await engine.cachedFilterCount
        XCTAssertEqual(filterCount, 1, "concurrent renders should still share one cached filter")
    }

    // MARK: - The protocol is a real injection point

    /// Step 4's other deliverable. Once the view model renders through `RenderEngining`, its tests
    /// should not need a GPU — so the protocol has to be conformable by something trivial and usable
    /// both generically and as an existential.
    func testAFakeCanStandInForTheEngine() async throws {
        let fake = FakeRenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 0.25))

        // Generic position …
        func renderThrough(_ engine: some RenderEngining) async -> CGImage? {
            await engine.makeCGImage(
                source: ImageSource(url: URL(fileURLWithPath: "/nowhere.png"), nativeExtent: .zero),
                document: document, lut: lut,
                scale: .preview(maxSize: CGSize(width: 64, height: 64)), space: .displayP3
            )
        }
        let image = await renderThrough(fake)
        XCTAssertNotNil(image, "the fake should answer without touching a file or the GPU")

        // … and as an existential, which is what a stored `var engine: any RenderEngining` needs.
        let boxed: any RenderEngining = fake
        _ = try await boxed.encode(
            source: ImageSource(url: URL(fileURLWithPath: "/nowhere.png"), nativeExtent: .zero),
            document: document, lut: lut, scale: .full,
            format: .jpeg, quality: 0.9, space: .sRGB
        )

        // And it recorded what was asked for — the reason a fake beats a stub.
        let previews = await fake.previewRequests
        let encodes = await fake.encodeRequests
        XCTAssertEqual(previews.count, 1)
        XCTAssertEqual(previews.first?.document, document)
        XCTAssertEqual(previews.first?.lutID, lut.lutID)
        XCTAssertEqual(previews.first?.scale, .preview(maxSize: CGSize(width: 64, height: 64)))
        XCTAssertEqual(previews.first?.space, .displayP3)
        XCTAssertEqual(encodes.count, 1)
        XCTAssertEqual(encodes.first?.format, .jpeg)
    }

    func testTheFakeCanSimulateAnEncodeFailure() async throws {
        let fake = FakeRenderEngine()
        await fake.setShouldFailEncode(true)

        do {
            _ = try await fake.encode(
                source: ImageSource(url: URL(fileURLWithPath: "/nowhere.png"), nativeExtent: .zero),
                document: EditDocument(), lut: nil, scale: .full,
                format: .png, quality: 1, space: .sRGB
            )
            XCTFail("the fake should have thrown")
        } catch {
            guard case ImageError.exportFailed = error else {
                return XCTFail("expected exportFailed, got \(error)")
            }
        }
    }

    // MARK: - Old path still stands

    /// Step 4 ships the engine *alongside* `ImageProcessor`; the app still renders through the old
    /// path until Steps 5–7. Both must therefore still work, and — since they now share a pipeline
    /// definition of "the identity" — agree on an unedited image.
    func testTheOldPathStillWorksAndAgreesOnAnUneditedImage() async throws {
        let engine = RenderEngine()

        let viaEngine = try await render(engine, EditDocument())
        let viaProcessor = try ImageDecoder.load(from: sourceURL)
        let oldRaster = try Pixels.bytes(of: viaProcessor)

        assertPixelsEqual(try Pixels.bytes(of: viaEngine), oldRaster,
                          "the new engine and the old loader should agree on an unedited image")
    }
}
