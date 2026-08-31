import XCTest
import CoreImage
import CoreGraphics
@testable import LUTzyKit

/// Phase 2 Step 3. `RenderPipeline.buildImage` is the function preview and export will both call, so
/// the properties worth pinning are the ones that make that substitution safe:
///
/// - an empty document is the identity (§5), or the migration cannot ship under the old behaviour;
/// - intensity 0 and 1 are exactly "no LUT" and "full LUT", the two endpoints the slider must hit;
/// - the graph is ordered, and the order is the document's;
/// - the scale is applied *early*, which is what makes resolution-independence load-bearing.
final class RenderPipelineTests: TempDirectoryTestCase {

    private var sourceURL: URL!
    private var source: ImageSource!

    override func setUpWithError() throws {
        try super.setUpWithError()
        sourceURL = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "src.png", in: tempDirectory)
        source = ImageSource(url: sourceURL, nativeExtent: CGSize(width: 96, height: 64))
    }

    /// The undecorated decode, for comparing a pipeline result against "the source, untouched".
    private func decodedSource() throws -> CIImage {
        try XCTUnwrap(CIImage(contentsOf: sourceURL, options: ImageDecoder.orientedLoadOptions))
    }

    private func build(
        _ document: EditDocument,
        lut: CubeLUT? = nil,
        scale: RenderScale = .full,
        space: WorkingSpace = .current,
        cache: LUTFilterCache? = nil
    ) throws -> CIImage {
        try XCTUnwrap(RenderPipeline.buildImage(
            source: source, document: document, lut: lut, scale: scale, space: space, lutCache: cache
        ))
    }

    // MARK: - Identity

    /// The ship gate. `EditDocument()` must produce the source unchanged — not approximately, not
    /// "close enough to look right", but the same pixels the old path decodes.
    func testEmptyDocumentIsTheIdentity() throws {
        let built = try build(EditDocument())
        let expected = try decodedSource()

        XCTAssertEqual(built.extent, expected.extent, "the identity must not resize")
        assertPixelsEqual(try Pixels.bytes(of: built), try Pixels.bytes(of: expected),
                          "an empty document must render the source unchanged")
    }

    /// **`rawDevelop` is inert for a standard image**, however loudly it is set.
    ///
    /// `developedSource` switches on `source.kind` and hands `rawDevelop` to `CIRAWFilter` on the
    /// `.raw` arm only; the `.standard` arm decodes and scales and never looks at it. That is the
    /// premise `DevelopInspectorView`'s "No develop stage — this image is already rendered" rests
    /// on: if a JPEG's render quietly *did* respond to a develop setting, withholding the controls
    /// would be hiding a real effect rather than declining to offer a missing one. It is also the
    /// premise behind keeping `document.rawDevelop` across image opens (§8.4) — a look auditioned on
    /// a RAW must not smear onto the next JPEG in the folder.
    ///
    /// Needs no RAW, which is the point: it is a claim about the *standard* branch, so it runs
    /// everywhere including CI. Written because the design doc's §6 test table listed a row for it
    /// that was never built, and nothing else in the suite asserted it.
    func testDevelopEditsAreInertForAStandardImage() throws {
        XCTAssertEqual(source.kind, .standard, "precondition: this fixture is a PNG")

        // Every develop knob the panel can reach, at a value far from its decoder default — if any
        // of it leaked into the standard path, a 2000 K white balance alone would recolour the frame.
        var loud = RAWDevelopSettings()
        loud.exposure = 3
        loud.baselineExposure = -2
        loud.shadowBias = 8
        loud.boostAmount = 0
        loud.boostShadowAmount = 2
        loud.neutralTemperature = 2000
        loud.neutralTint = -150
        loud.sharpnessAmount = 1
        loud.contrastAmount = 1
        loud.detailAmount = 3
        loud.moireReductionAmount = 1
        loud.localToneMapAmount = 1
        loud.luminanceNoiseReductionAmount = 1
        loud.colorNoiseReductionAmount = 1
        loud.lensCorrectionEnabled = true
        loud.gamutMappingEnabled = false
        loud.extendedDynamicRangeAmount = 2
        loud.highlightRecoveryEnabled = false
        XCTAssertFalse(loud.isNeutral, "precondition: this would change a RAW")

        // Interleaved rather than sequential: Core Image is not bit-reproducible across
        // time-separated runs (see `Pixels.bytes`).
        let neutral = try build(EditDocument())
        let developed = try build(EditDocument(rawDevelop: loud))

        XCTAssertEqual(developed.extent, neutral.extent, "develop must not resize a standard image")
        assertPixelsEqual(
            try Pixels.bytes(of: developed), try Pixels.bytes(of: neutral),
            "rawDevelop reached a standard image's render — the develop panel is withheld for these "
            + "files on the grounds that there is nothing for it to drive"
        )
    }

    /// The identity has to survive the stages *running* rather than only being skipped: a document
    /// whose nodes are all at their defaults, and a LUT that is the identity cube, must still come out
    /// pixel-for-pixel the same.
    func testNeutralNodesAndAnIdentityCubeAreStillTheIdentity() throws {
        let document = EditDocument(
            adjustments: [.neutralExposure, .neutralColorControls, .neutralHighlightShadow,
                          .neutralTemperatureTint, .neutralVibrance],
            lut: LUTSettings(lutID: LUTID(raw: "identity"), intensity: 1)
        )
        let built = try build(document, lut: TestImages.identityLUT())

        assertPixelsEqual(try Pixels.bytes(of: built), try Pixels.bytes(of: try decodedSource()),
                          "neutral nodes plus an identity cube is still a no-op")
    }

    /// Skipping identity nodes is an optimization, so it has to be invisible. If any of the five
    /// filters were not a true pass-through at its default values, this is where that would show.
    func testSkippingIdentityNodesChangesNothing() throws {
        let neutral: [AdjustmentNode] = [.neutralExposure, .neutralColorControls,
                                         .neutralHighlightShadow, .neutralTemperatureTint,
                                         .neutralVibrance]
        let base = try decodedSource()

        for node in neutral {
            // What the pipeline does (skip) …
            let skipped = RenderPipeline.applyAdjustments([node], to: base)
            // … versus actually building the filter, which is what a non-identity value would do.
            let applied = try XCTUnwrap(forcedFilter(for: node, input: base))

            assertPixelsEqual(try Pixels.bytes(of: skipped), try Pixels.bytes(of: applied),
                              "\(node) is advertised as an identity but the filter changes pixels")
        }
    }

    /// Build the node's filter without the `isIdentity` short-circuit, by nudging the node off its
    /// default and back is not possible — so this reimplements the one line the pipeline skips.
    private func forcedFilter(for node: AdjustmentNode, input: CIImage) -> CIImage? {
        switch node {
        case .exposure(let ev):
            return input.applyingFilter("CIExposureAdjust", parameters: ["inputEV": ev])
        case .colorControls(let b, let c, let s):
            return input.applyingFilter("CIColorControls", parameters: [
                "inputBrightness": b, "inputContrast": c, "inputSaturation": s,
            ])
        case .highlightShadow(let h, let s):
            return input.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": h, "inputShadowAmount": s,
            ])
        case .temperatureTint(let t, let tint):
            return input.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: t, y: tint),
            ])
        case .vibrance(let amount):
            return input.applyingFilter("CIVibrance", parameters: ["inputAmount": amount])
        }
    }

    // MARK: - Intensity endpoints

    /// The other half of the ship gate. Intensity 0 is *exactly* the ungraded image and intensity 1 is
    /// *exactly* the fully graded one — the endpoints have to be exact or the slider lies at its own
    /// extremes, which is where users check whether a look is doing anything.
    func testIntensityEndpointsAreExact() throws {
        let lut = TestImages.warmLUT()
        let ungraded = try Pixels.bytes(of: try build(EditDocument()))
        let fullyGraded = try Pixels.bytes(of: try XCTUnwrap(
            lut.apply(to: try decodedSource(), intensity: 1)
        ))

        let atZero = try Pixels.bytes(of: try build(
            EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 0)), lut: lut
        ))
        let atOne = try Pixels.bytes(of: try build(
            EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 1)), lut: lut
        ))

        assertPixelsEqual(atZero, ungraded, "intensity 0 must be the untouched image")
        assertPixelsEqual(atOne, fullyGraded, "intensity 1 must be the fully graded image")

        // And the endpoints are not the same image — otherwise both assertions above could pass
        // against a pipeline that ignored the LUT entirely.
        assertPixelsDiffer(atZero, atOne, "the LUT must actually change the image")
    }

    func testIntermediateIntensityLandsBetweenTheEndpoints() throws {
        let lut = TestImages.warmLUT()
        func render(_ intensity: Double) throws -> [UInt8] {
            try Pixels.bytes(of: try build(
                EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: intensity)), lut: lut
            ))
        }
        let atZero = try render(0)
        let atHalf = try render(0.5)
        let atOne = try render(1)

        assertPixelsDiffer(atHalf, atZero, "half strength should differ from none")
        assertPixelsDiffer(atHalf, atOne, "half strength should differ from full")
    }

    /// Out-of-range intensities are clamped rather than extrapolated — a corrupt or hand-edited
    /// document must not be able to produce a wilder grade than the LUT itself.
    ///
    /// Note this property is over-determined, and deliberately so: `LUTSettings.isIdentity` catches
    /// `<= 0` before the LUT stage runs, `CubeLUT.apply` clamps and short-circuits at both ends, and
    /// `CIDissolveTransition` clamps its own time input (measured: 5.0 renders as 1.0, -3.0 as 0.0).
    /// No single-point mutation can break this test, which is a property of the design rather than a
    /// gap in the test.
    func testIntensityIsClamped() throws {
        let lut = TestImages.warmLUT()
        let atOne = try Pixels.bytes(of: try build(
            EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 1)), lut: lut
        ))
        let aboveOne = try Pixels.bytes(of: try build(
            EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 5)), lut: lut
        ))
        let belowZero = try Pixels.bytes(of: try build(
            EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: -3)), lut: lut
        ))

        assertPixelsEqual(aboveOne, atOne, "intensity above 1 should clamp to the full LUT")
        assertPixelsEqual(belowZero, try Pixels.bytes(of: try build(EditDocument())),
                          "negative intensity should clamp to no LUT")
    }

    /// A document that names a LUT the caller could not resolve renders *without* it rather than
    /// failing. Blanking the preview because a file moved would turn a missing look into a broken app;
    /// reporting belongs at load, once, not per frame.
    func testUnresolvedLUTRendersUngradedRatherThanFailing() throws {
        let document = EditDocument(lut: LUTSettings(lutID: LUTID(raw: "/gone/missing.cube"), intensity: 1))
        let built = try build(document, lut: nil)

        assertPixelsEqual(try Pixels.bytes(of: built), try Pixels.bytes(of: try decodedSource()),
                          "an unresolvable LUT should leave the image ungraded, not nil")
    }

    // MARK: - Ordering

    /// The adjustments array is a pipeline, and the graph has to reflect the document's order rather
    /// than any convenient one.
    ///
    /// The two nodes are chosen so they **cannot** commute: exposure is a multiply in linear light and
    /// `brightness` is an add, so `2x + 0.3` and `2(x + 0.3)` differ by a constant. That matters —
    /// the first draft of this test paired desaturation with brightness and failed, because
    /// desaturation is a weighted average whose weights sum to 1 and therefore
    /// `luma(rgb + k) == luma(rgb) + k`. Two commuting operations prove nothing about ordering.
    func testAdjustmentOrderReachesTheGraph() throws {
        let multiply = AdjustmentNode.exposure(ev: 1.0)
        let add = AdjustmentNode.colorControls(brightness: 0.3, contrast: 1, saturation: 1)

        let forwards = try Pixels.bytes(of: try build(EditDocument(adjustments: [multiply, add])))
        let backwards = try Pixels.bytes(of: try build(EditDocument(adjustments: [add, multiply])))

        assertPixelsDiffer(forwards, backwards, "reordering the nodes must change the render")

        // Asserting only that the two differ is not enough: a pipeline that reversed *every*
        // document would still produce two different images and sail through. So pin which one is
        // which against a graph built by hand in the document's order. (A reversing mutation
        // survived the weaker version of this test.)
        let base = try decodedSource()
        let expected = base
            .applyingFilter("CIExposureAdjust", parameters: ["inputEV": 1.0])
            .applyingFilter("CIColorControls", parameters: [
                "inputBrightness": 0.3, "inputContrast": 1.0, "inputSaturation": 1.0,
            ])
        assertPixelsEqual(forwards, try Pixels.bytes(of: expected),
                          "the graph must run the nodes in the order the document lists them")
    }

    /// The direction of `temperatureTint`, pinned deliberately.
    ///
    /// With the source neutral pinned at D65 and only `targetNeutral` moving, **raising Kelvin cools
    /// the image** — the inverse of the Lightroom convention. `docs/PHASE2_SPEC.md` §8.7 is **closed**:
    /// this direction is pinned deliberately and must not be flipped here, because the node's
    /// convention is what stored documents mean. The user-facing correction lives one layer up, in
    /// `AdjustmentControl.sliderMapped(_:)`, which reflects the Adjust slider about D65 so that
    /// dragging right warms. Changing that mapping is a UI decision; changing this one silently
    /// re-renders every document ever saved.
    ///
    /// This test records what ships today so that either change is a deliberate act with a failing
    /// test attached, rather than a silent look change.
    ///
    /// Measured on a mid grey: 3200 K → (158,121,74), 6500 K → (128,128,128), 9000 K → (119,128,144).
    func testRaisingKelvinCoolsTheImage() throws {
        let flat = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))

        func channels(_ temp: Double) throws -> (r: Int, g: Int, b: Int) {
            let out = RenderPipeline.applyAdjustments([.temperatureTint(temp: temp, tint: 0)], to: flat)
            let bytes = try Pixels.bytes(of: out)
            return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
        }

        let warm = try channels(3200)
        let neutral = try channels(6500)
        let cool = try channels(9000)

        XCTAssertEqual(neutral.r, neutral.b, accuracy: 1, "6500 K must be the identity")
        XCTAssertGreaterThan(warm.r, warm.b, "below 6500 K should warm the image")
        XCTAssertLessThan(cool.r, cool.b, "above 6500 K should cool it — see PHASE2_SPEC §8.7")
    }

    func testDuplicateNodesStack() throws {
        let once = try Pixels.bytes(of: try build(EditDocument(adjustments: [.exposure(ev: 0.5)])))
        let twice = try Pixels.bytes(of: try build(
            EditDocument(adjustments: [.exposure(ev: 0.5), .exposure(ev: 0.5)])
        ))
        let combined = try Pixels.bytes(of: try build(EditDocument(adjustments: [.exposure(ev: 1.0)])))

        assertPixelsDiffer(once, twice, "two exposure nodes must not collapse into one")
        assertPixelsEqual(twice, combined, "stacking +0.5 EV twice should equal +1.0 EV")
    }

    /// Every case has to actually reach a filter. A `switch` arm that fell through to `nil` would be
    /// invisible in the tests above, which only exercise a couple of node kinds.
    func testEveryAdjustmentCaseChangesTheImage() throws {
        let nodes: [AdjustmentNode] = [
            .exposure(ev: 1.0),
            .colorControls(brightness: 0.2, contrast: 1.4, saturation: 0.3),
            .highlightShadow(highlights: 0.3, shadows: 0.8),
            .temperatureTint(temp: 3200, tint: 60),
            .vibrance(amount: 0.9),
        ]
        let base = try Pixels.bytes(of: try build(EditDocument()))

        for node in nodes {
            let rendered = try Pixels.bytes(of: try build(EditDocument(adjustments: [node])))
            assertPixelsDiffer(rendered, base, "\(node) should reach a CIFilter and change the image")
        }
    }

    // MARK: - Scale

    /// `.full` is native; `.preview` fits the box. Both run the *same* graph, which is the entire
    /// point — the only difference between a preview and an export is this value.
    func testPreviewScaleFitsTheBoxAndFullDoesNot() throws {
        let full = try build(EditDocument(), scale: .full)
        XCTAssertEqual(full.extent.width, 96)
        XCTAssertEqual(full.extent.height, 64)

        let preview = try build(EditDocument(), scale: .preview(maxSize: CGSize(width: 32, height: 32)))
        XCTAssertLessThanOrEqual(preview.extent.width, 32)
        XCTAssertLessThanOrEqual(preview.extent.height, 32)
        XCTAssertGreaterThan(preview.extent.width, 0)

        // Aspect ratio survives: 96×64 is 3:2, and a 32-box should give 32×~21.
        XCTAssertEqual(preview.extent.width / preview.extent.height, 96.0 / 64.0, accuracy: 0.05)
    }

    /// A preview box larger than the image must not magnify it — that would cost pixels for no
    /// detail and push an upscaled image through the LUT.
    func testPreviewLargerThanTheSourceDoesNotUpscale() throws {
        let preview = try build(EditDocument(), scale: .preview(maxSize: CGSize(width: 4096, height: 4096)))
        XCTAssertEqual(preview.extent.width, 96)
        XCTAssertEqual(preview.extent.height, 64)
    }

    /// The downscale happens *before* the adjustments, not after. If it were applied at the end, the
    /// nodes would be running on full-resolution pixels and the preview's whole reason to exist —
    /// being cheap — would be gone.
    ///
    /// Observable because a Lanczos-downscaled-then-graded image is not the same as a
    /// graded-then-downscaled one: the resample mixes neighbouring pixels, and a non-linear tone
    /// curve does not commute with that mixing.
    func testTheDownscaleHappensBeforeTheAdjustments() throws {
        let box = CGSize(width: 24, height: 24)
        let document = EditDocument(adjustments: [.colorControls(brightness: 0, contrast: 2.5, saturation: 1)])

        let pipeline = try build(document, scale: .preview(maxSize: box))

        // Grade first at full resolution, then downscale — the order the pipeline must NOT use.
        let full = try build(document, scale: .full)
        let factor = RenderScale.preview(maxSize: box).factor(for: CGSize(width: 96, height: 64))
        let gradedThenScaled = full.applyingFilter("CILanczosScaleTransform", parameters: [
            "inputScale": factor, "inputAspectRatio": 1.0,
        ])

        XCTAssertEqual(pipeline.extent.integral, gradedThenScaled.extent.integral,
                       "both orders should land on the same extent, so only the pixels differ")
        assertPixelsDiffer(try Pixels.bytes(of: pipeline), try Pixels.bytes(of: gradedThenScaled),
                           "scaling after grading would mean the downscale is not early")
    }

    // MARK: - Colour space

    /// The interpolation space has to reach the cube. If `buildImage` dropped its `space` argument,
    /// these two would be identical.
    func testWorkingSpaceReachesTheCube() throws {
        let lut = TestImages.warmLUT()
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 1))

        // Rasterize both through the SAME space, so only the interpolation differs.
        let inSRGB = try Pixels.bytes(of: try build(document, lut: lut, space: .sRGB), space: .sRGB)
        let inP3 = try Pixels.bytes(of: try build(document, lut: lut, space: .displayP3), space: .sRGB)

        assertPixelsDiffer(inSRGB, inP3, "the cube's interpolation space should change the result")
    }

    // MARK: - Source backing

    /// A Photos import and the same image on disk must render identically — the `.data` case exists
    /// so those imports work at all, and it would be a poor fix if it took a different path.
    func testDataBackedAndURLBackedSourcesAgree() throws {
        let data = try Data(contentsOf: sourceURL)
        let fromData = ImageSource(data: data, nativeExtent: CGSize(width: 96, height: 64))
        let lut = TestImages.warmLUT()
        let document = EditDocument(
            adjustments: [.exposure(ev: 0.4)],
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.7)
        )

        let viaURL = try XCTUnwrap(RenderPipeline.buildImage(
            source: source, document: document, lut: lut, scale: .full
        ))
        let viaData = try XCTUnwrap(RenderPipeline.buildImage(
            source: fromData, document: document, lut: lut, scale: .full
        ))

        assertPixelsEqual(try Pixels.bytes(of: viaURL), try Pixels.bytes(of: viaData),
                          "the same image should render the same whether it arrived as a file or bytes")
    }

    /// B1, the worst bug this app has had, was `CIImage` ignoring the EXIF orientation tag: portrait
    /// JPEGs previewed and *exported* on their side while their thumbnails stood upright. The new
    /// pipeline is a second decode path and would reintroduce it for free if it skipped
    /// `orientedLoadOptions`. Neither the gradient PNG nor the RAW fixture carries a tag, so without
    /// this nothing in Step 3 would notice.
    func testOrientationIsBakedLikeTheOldPath() throws {
        // An 80×40 landscape buffer tagged "rotate 90° CW to display" — what a camera writes when it
        // was held on end. It must come out 40×80.
        let url = try Fixtures.writeJPEG(width: 80, height: 40, orientation: 6,
                                         named: "portrait.jpg", in: tempDirectory)
        let tagged = ImageSource(url: url, nativeExtent: CGSize(width: 40, height: 80))

        let built = try XCTUnwrap(RenderPipeline.buildImage(
            source: tagged, document: EditDocument(), lut: nil, scale: .full
        ))
        XCTAssertEqual(built.extent.width, 40, "the pipeline must honour the orientation tag")
        XCTAssertEqual(built.extent.height, 80)

        // The bytes path has to agree — a Photos import of the same file is the same picture.
        let fromData = ImageSource(data: try Data(contentsOf: url),
                                   nativeExtent: CGSize(width: 40, height: 80))
        let viaData = try XCTUnwrap(RenderPipeline.buildImage(
            source: fromData, document: EditDocument(), lut: nil, scale: .full
        ))
        XCTAssertEqual(viaData.extent, built.extent, "bytes and file must agree on orientation")
    }

    func testUndecodableSourceReturnsNil() throws {
        let junk = ImageSource(backing: .data(Data("not an image".utf8)), kind: .standard, nativeExtent: .zero)
        XCTAssertNil(RenderPipeline.buildImage(
            source: junk, document: EditDocument(), lut: nil, scale: .full
        ))

        let missing = ImageSource(url: tempDirectory.appendingPathComponent("nope.png"),
                                  nativeExtent: CGSize(width: 10, height: 10))
        XCTAssertNil(RenderPipeline.buildImage(
            source: missing, document: EditDocument(), lut: nil, scale: .full
        ))
    }

    // MARK: - Cache equivalence

    /// The cache is an optimization and must not be observable in the output.
    func testACachedFilterRendersTheSameAsAFreshOne() throws {
        let lut = TestImages.warmLUT()
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 0.6))
        let cache = LUTFilterCache()

        let uncached = try Pixels.bytes(of: try build(document, lut: lut))
        let cached = try Pixels.bytes(of: try build(document, lut: lut, cache: cache))
        // Second time through, the filter comes back from the cache rather than being built.
        let cachedAgain = try Pixels.bytes(of: try build(document, lut: lut, cache: cache))

        assertPixelsEqual(cached, uncached, "a cached cube filter must render identically")
        assertPixelsEqual(cachedAgain, uncached, "and still identically on the cache hit")
        XCTAssertEqual(cache.count, 1)
    }

    // MARK: - RAW

    /// RAW develop reaches the decoder through the pipeline, and the preview scale reaches
    /// `CIRAWFilter.scaleFactor` rather than being applied afterwards. Skipped without a local RAW.
    func testRAWDevelopAndScaleReachTheDecoder() throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW to develop; see Fixtures.localRAWURL")
        }
        let rawSource = ImageSource(url: rawURL, nativeExtent: .zero)
        XCTAssertEqual(rawSource.kind, .raw)

        let neutral = try XCTUnwrap(RenderPipeline.buildImage(
            source: rawSource, document: EditDocument(),
            lut: nil, scale: .preview(maxSize: CGSize(width: 400, height: 400))
        ))
        let brightened = try XCTUnwrap(RenderPipeline.buildImage(
            source: rawSource,
            document: EditDocument(rawDevelop: RAWDevelopSettings(exposure: 1.5)),
            lut: nil, scale: .preview(maxSize: CGSize(width: 400, height: 400))
        ))

        XCTAssertEqual(neutral.extent, brightened.extent, "develop must not change geometry")
        assertPixelsDiffer(try Pixels.bytes(of: neutral), try Pixels.bytes(of: brightened),
                           "rawDevelop.exposure must reach CIRAWFilter through the pipeline")

        // And the scale really shrank the decode: `nativeExtent` was passed as .zero above, so this
        // can only have come from the decoder's own nativeSize.
        XCTAssertLessThanOrEqual(neutral.extent.width, 400)
        XCTAssertLessThanOrEqual(neutral.extent.height, 400)
        XCTAssertGreaterThan(neutral.extent.width, 0)
    }

    /// A neutral document over a RAW must match `developRAWNeutral` — the baseline the whole
    /// migration promises not to move.
    func testNeutralRAWMatchesTheExistingNeutralBaseline() throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW to develop; see Fixtures.localRAWURL")
        }
        let rawSource = ImageSource(url: rawURL, nativeExtent: .zero)

        // Interleaved, not sequential: Core Image is not bit-reproducible across time-separated runs.
        let viaPipeline = try XCTUnwrap(RenderPipeline.buildImage(
            source: rawSource, document: EditDocument(), lut: nil, scale: .full
        ))
        let viaProcessor = try XCTUnwrap(ImageDecoder.developRAWNeutral(at: rawURL))

        XCTAssertEqual(viaPipeline.extent, viaProcessor.extent)
        assertPixelsEqual(try Pixels.bytes(of: viaPipeline), try Pixels.bytes(of: viaProcessor),
                          "a neutral document must reproduce today's neutral RAW render")
    }
}
