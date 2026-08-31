import XCTest
import CoreImage
import simd
@testable import LUTzyKit

/// Phase 2 Step 9's ship gate: **the derived cube is still fit against the render the pipeline
/// produces.**
///
/// `RecipeExtractor` fits a cube by comparing a neutral RAW render against the camera's own JPEG, and
/// the app later applies that cube to a render the *pipeline* builds. Those are two different pieces
/// of code arriving at what must be the same image. Two tests already pin the halves separately —
/// `RenderPipelineTests.testNeutralRAWMatchesTheExistingNeutralBaseline` (the neutral renders agree)
/// and `WorkingSpaceTests.testDeriveFitSpaceEqualsApplySpace` (fit space equals apply space). What
/// was missing is the end-to-end link: derive a real cube and check that applying it through the new
/// pipeline lands where applying it the way derive fits it lands.
///
/// **These tests skip in CI, and that is not a hedge — it is the arrangement.** A licence-clean DNG
/// small enough to commit does not exist, `realworldtest/` is gitignored, and `Fixtures.localRAWURL`
/// returns `nil` on a runner. Read the suite's green tick on CI as saying nothing whatsoever about
/// derive; the coverage here is local-only. See `docs/PHASE2_SPEC.md` §8.9.
final class DeriveInvarianceTests: XCTestCase {

    /// One derive, shared by every test here.
    ///
    /// A derive on a 40 MP pair costs tens of seconds and each test below asks a different question
    /// about the *same* cube, so doing it once is the difference between a slow suite and an
    /// unusable one. A `static let` rather than a `class setUp` with mutable statics: this target
    /// runs in Swift 6 language mode, where mutable global state is an error and the repo's answer to
    /// that is never an opt-out.
    private struct Fixture {
        let lut: CubeLUT
        let report: RecipeReport
        let raw: URL
        let jpg: URL
    }

    private enum Outcome {
        case unavailable
        case failed(String)
        case ready(Fixture)
    }

    private static let outcome: Outcome = {
        guard let pair = Fixtures.localRAWJPGPair else { return .unavailable }
        do {
            let result = try RecipeExtractor.derive(rawURL: pair.raw, jpgURL: pair.jpg)
            let name = DeriveCoordinator.derivedName(forJPG: pair.jpg, size: result.size)
            return .ready(Fixture(
                lut: DeriveCoordinator.makeDerivedLUT(
                    cube: result.cube, size: result.size, name: name
                ),
                report: result.report, raw: pair.raw, jpg: pair.jpg
            ))
        } catch {
            return .failed("\(error)")
        }
    }()

    private func requireDerive() throws -> Fixture {
        switch Self.outcome {
        case .ready(let fixture):
            return fixture
        case .failed(let message):
            // A failure is a failure, not a skip: the pair is present and derive broke on it.
            XCTFail("derive failed on the local pair: \(message)")
            throw XCTSkip("derive failed")
        case .unavailable:
            throw XCTSkip("""
                No (RAW, JPG) pair in realworldtest/, so the derive gate did not run. This is the \
                expected state on CI — see Fixtures.localRAWJPGPair and PHASE2_SPEC §8.9.
                """)
        }
    }

    // MARK: - The gate

    /// **The invariance.** A derived cube applied through the new pipeline must land where the same
    /// cube applied over `developRAWNeutral` lands — the render it was fit against.
    ///
    /// Both sides are computed in **one process, interleaved**, because Core Image is not
    /// bit-reproducible across time-separated runs. That is also why there is no recorded number
    /// here to drift: the comparison is against a value computed moments earlier, at the repo's
    /// parity tolerance of 1.
    ///
    /// If this fails, the likely causes in order are: the pipeline's RAW stage stopped matching
    /// `developRAWNeutral`; the LUT stage started interpolating in a space other than the one derive
    /// fits in; or `WorkingSpace.current` moved off sRGB without derive being re-fit (§4.4).
    func testTheDerivedCubeAppliesOverTheSameNeutralRenderItWasFitAgainst() throws {
        let derived = try requireDerive()

        // How RecipeExtractor fits it: the neutral RAW render, cube applied, sampled in sRGB.
        let neutral = try XCTUnwrap(ImageDecoder.developRAWNeutral(at: derived.raw))
        let viaDeriveBaseline = try XCTUnwrap(derived.lut.apply(to: neutral, space: .sRGB))

        // How the app applies it: the whole document, through the pipeline, at full resolution.
        let document = EditDocument(lut: LUTSettings(lutID: derived.lut.lutID, intensity: 1))
        let viaPipeline = try XCTUnwrap(RenderPipeline.buildImage(
            source: ImageSource(url: derived.raw, nativeExtent: .zero),
            document: document, lut: derived.lut, scale: .full, space: .sRGB
        ))

        XCTAssertEqual(viaPipeline.extent, viaDeriveBaseline.extent)
        assertPixelsEqual(
            try Pixels.bytes(of: viaPipeline, space: .sRGB),
            try Pixels.bytes(of: viaDeriveBaseline, space: .sRGB),
            """
            the derived cube no longer lands on the render it was fit against — a cube fit in one \
            baseline and applied over another mis-maps everywhere, silently
            """
        )
    }

    /// A sanity floor, so the invariance above cannot pass trivially.
    ///
    /// Two identical-but-wrong renders satisfy an equality check perfectly. This asks the separate
    /// question of whether the derived cube actually *reproduces the camera's look*: apply it through
    /// the pipeline, put the result next to the in-camera JPG, and require the mean absolute error to
    /// stay under a bound.
    ///
    /// The bound is measured, and so is its discriminating power — both numbers are recorded below.
    /// It is a floor against a broken derive, not a quality target; tightening it toward the measured
    /// value would make the suite flaky for no gain.
    func testTheDerivedCubeLandsNearTheInCameraJPG() throws {
        let derived = try requireDerive()

        let document = EditDocument(lut: LUTSettings(lutID: derived.lut.lutID, intensity: 1))
        let graded = try XCTUnwrap(RenderPipeline.buildImage(
            source: ImageSource(url: derived.raw, nativeExtent: .zero),
            document: document, lut: derived.lut, scale: .full, space: .sRGB
        ))
        let jpg = try XCTUnwrap(
            CIImage(contentsOf: derived.jpg, options: ImageDecoder.orientedLoadOptions)
        )

        // Compared small: the question is whether the colour mapping is right, and a 512 px pair
        // answers that for a fraction of the memory. Both sides are scaled the same way, so the
        // resampler contributes to neither side's error.
        let a = try Self.bytes(of: graded, longEdge: 512)
        let b = try Self.bytes(of: jpg, longEdge: 512)
        XCTAssertEqual(a.count, b.count, "the pair must rasterize to the same shape to be compared")

        let mae = Self.meanAbsoluteError(a, b)
        // Measured on the Leica pair in realworldtest/, three runs: 1.248, 1.246, 1.249 — the
        // sampler's run-to-run variation is ±0.003, far smaller than expected for a randomly seeded
        // fit. The same comparison with **no cube at all** reads 5.297, so that is what a derive that
        // had silently stopped working looks like: the gap the cube closes is 5.30 → 1.25.
        //
        // Bounded at 3.0 — 2.4x the measurement, and well under the 5.30 no-op reading, so the test
        // has real discriminating power rather than a bound nothing could ever cross. The headroom
        // is for a different camera's pair, not for drift in this one.
        XCTAssertLessThan(mae, 3.0, """
            the derived cube no longer approximates the in-camera JPG (mean abs error \
            \(String(format: "%.2f", mae))/255). The invariance test can still pass here — two \
            renders can agree with each other and both be wrong — so suspect the extractor itself.
            """)
        XCTAssertGreaterThan(derived.report.sampleCount, 0)
    }

    /// The **pipeline** side of derive's baseline: `RenderPipeline` must honour a document's develop
    /// settings, so that the neutral render derive fits against is demonstrably not what a developed
    /// document produces.
    ///
    /// **This does not test derive.** It never re-derives — both operands are
    /// `ImageDecoder.developRAWNeutral` and `RenderPipeline.buildImage` — so it is invariant to
    /// `RecipeExtractor.derive`'s signature, and its own failure message says as much ("develop is not
    /// reaching the pipeline at all"). `PHASE2_SPEC.md` §5 named this test as the enforcement of
    /// "derive baseline immunity" for several steps; it is not, and a defaulted `develop:` parameter
    /// on `derive` leaves it green. That invariant is pinned by `DeriveBaselineImmunityTests`, which
    /// reads derive's signature as source text and runs without a DNG.
    func testDeriveIgnoresTheDocumentsDevelopSettings() throws {
        let derived = try requireDerive()

        // What derive fits against, and what the pipeline produces for a *heavily developed*
        // document, must be the same neutral render — because derive never sees the document.
        let baseline = try XCTUnwrap(ImageDecoder.developRAWNeutral(at: derived.raw))
        var developed = EditDocument()
        developed.rawDevelop.exposure = 1.5
        let viaPipeline = try XCTUnwrap(RenderPipeline.buildImage(
            source: ImageSource(url: derived.raw, nativeExtent: .zero),
            document: developed, lut: nil, scale: .full, space: .sRGB
        ))

        assertPixelsDiffer(
            try Pixels.bytes(of: viaPipeline, space: .sRGB),
            try Pixels.bytes(of: baseline, space: .sRGB),
            """
            a +1.5 EV document rendered identically to the neutral baseline, so this test is not \
            measuring what it claims — develop is not reaching the pipeline at all
            """
        )
    }

    // MARK: - Helpers

    private static func bytes(of image: CIImage, longEdge: Int) throws -> [UInt8] {
        let extent = image.extent
        let factor = min(CGFloat(longEdge) / extent.width, CGFloat(longEdge) / extent.height, 1)
        let scaled = image
            .transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            .cropped(to: CGRect(
                x: 0, y: 0,
                width: (extent.width * factor).rounded(.down),
                height: (extent.height * factor).rounded(.down)
            ))
        return try Pixels.bytes(of: scaled, space: .sRGB)
    }

    /// Mean absolute error over the colour channels, ignoring alpha — a uniformly opaque alpha would
    /// otherwise dilute the number by a quarter and make the bound read tighter than it is.
    private static func meanAbsoluteError(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var total = 0
        var counted = 0
        for index in stride(from: 0, to: min(a.count, b.count), by: 4) {
            for channel in 0..<3 {
                total += abs(Int(a[index + channel]) - Int(b[index + channel]))
                counted += 1
            }
        }
        return counted == 0 ? .infinity : Double(total) / Double(counted)
    }
}
