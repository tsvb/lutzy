import XCTest
import CoreImage
@testable import LUTzyKit

/// Phase 2 Step 10b. The ship gate is "the inspector drives live re-render", which is a claim about
/// wiring, so this drives `FakeRenderEngine` and asserts on the requests it recorded. The pure-value
/// half of the step is in `AdjustmentControlTests`.
@MainActor
final class AdjustInspectorTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func openStandardImage(_ viewModel: AppViewModel) async throws {
        let url = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "shot.png", in: tempDirectory)
        viewModel.openImage(url: url)
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }
    }

    // MARK: - Reading

    /// An untouched panel reads its neutrals and writes nothing. The document must still be empty.
    func testAnUntouchedPanelLeavesTheDocumentEmpty() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        for control in AdjustmentControl.allCases {
            _ = viewModel.adjustmentValue(for: control)
        }
        XCTAssertEqual(viewModel.document.adjustments, [], "reading must never write")
        XCTAssertFalse(viewModel.hasAdjustments)
    }

    /// The value a control reads is in **slider space** — mapped, not the raw stored value.
    func testTemperatureReadsBackInSliderSpace() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .temperature).wrappedValue = 9000

        XCTAssertEqual(viewModel.adjustmentValue(for: .temperature), 9000, accuracy: 1e-9,
                       "what the slider was set to is what it must read back")
        XCTAssertEqual(AdjustmentControl.temperature.value(in: viewModel.document.adjustments),
                       4000, accuracy: 1e-9,
                       "the node stores the reflected value, not the slider's")
    }

    // MARK: - Writing drives a render

    /// **The ship gate.** A slider write must reach the engine.
    func testAnAdjustmentEditRendersThroughTheEngine() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5

        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 1.5)],
                       "the document updates immediately, even though the render is debounced")

        try await waitUntil("the adjusted render") {
            await fake.previewRequests.contains { $0.document.adjustments == [.exposure(ev: 1.5)] }
        }
    }

    /// Nothing asserted that adjustment sliders actually debounce. `adjustmentBinding(for:)` passes
    /// `debounced: true`, and a regression to `debounced: false` would mean one full render per
    /// slider tick on a 60 MP RAW — shipping silently, because
    /// `testAnAdjustmentEditRendersThroughTheEngine` makes a single edit and passes either way.
    /// Follows `DevelopInspectorTests.testWritingASliderThroughTheBindingStillDebounces`.
    func testWritingAnAdjustmentSliderThroughTheBindingStillDebounces() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        let atRest = await fake.previewRequests.count

        for step in 1...20 {
            viewModel.adjustmentBinding(for: .exposure).wrappedValue = Double(step) / 20.0
        }
        try await waitUntil("the settled render") {
            await fake.previewRequests.contains { $0.document.adjustments == [.exposure(ev: 1.0)] }
        }

        let issued = await fake.previewRequests.count - atRest
        XCTAssertLessThan(issued, 10,
                          "20 slider ticks issued \(issued) renders — adjustmentBinding stopped "
                          + "debouncing")
    }

    /// Resets are undebounced, per `updateDocument(debounced:)`'s contract — a button that lagged
    /// 60 ms would feel broken. Follows
    /// `DevelopInspectorTests.testWritingAToggleThroughTheBindingSkipsTheDebounce`: **sequence, not
    /// elapsed time**, is the discriminator. Two debounced writes land on the same node first — both
    /// through `adjustmentBinding`, which always debounces here, there being no toggles in this panel
    /// — and then, with no suspension in between, the undebounced reset, so
    /// `updateDocument(debounced:)`'s `developTask?.cancel()` is what has to pre-empt the pending
    /// debounce task rather than merely outrunning it. Spinning on `Task.yield()` rather than
    /// sleeping keeps the loop's own cost a tiny fraction of the 60 ms debounce, so the reset's render
    /// can only appear this fast if it truly took the immediate path.
    func testResettingOneControlPreservesTheOthers() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        // Two debounced writes to the same node — this pair *should* wait ~60 ms.
        viewModel.adjustmentBinding(for: .contrast).wrappedValue = 1.4
        viewModel.adjustmentBinding(for: .saturation).wrappedValue = 0.5
        // ...and immediately, with no suspension in between, the undebounced reset.
        viewModel.resetAdjustment(.contrast)

        XCTAssertEqual(viewModel.adjustmentValue(for: .contrast),
                       AdjustmentControl.contrast.neutral, accuracy: 1e-12)
        XCTAssertEqual(viewModel.adjustmentValue(for: .saturation), 0.5, accuracy: 1e-12)

        let expectedAfterReset: [AdjustmentNode] = [.colorControls(brightness: 0, contrast: 1, saturation: 0.5)]
        var sawReset = false
        for _ in 0..<1000 {
            sawReset = await fake.previewRequests.contains { $0.document.adjustments == expectedAfterReset }
            if sawReset { break }
            await Task.yield()
        }
        XCTAssertTrue(sawReset,
                      "resetAdjustment must render immediately — a reset routed through the debounce "
                      + "would not have landed within this tight a loop")

        // And the pre-reset writes' own render — contrast still at 1.4 — must never have landed: it
        // can only appear if the debounced task outraced the reset's cancellation instead of being
        // pre-empted by it.
        let soFar = await fake.previewRequests
        XCTAssertFalse(
            soFar.contains { request in
                guard case .colorControls(_, let contrast, let saturation)? =
                    request.document.adjustments.first(where: { $0.slot == .colorControls }) else {
                    return false
                }
                return contrast == 1.4 && saturation == 0.5
            },
            "the debounced writes' own render should have been pre-empted by the reset, not raced"
        )
    }

    func testResetAllEmptiesTheArray() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5
        viewModel.adjustmentBinding(for: .vibrance).wrappedValue = 0.4
        XCTAssertTrue(viewModel.hasAdjustments)

        viewModel.resetAllAdjustments()

        XCTAssertEqual(viewModel.document.adjustments, [])
        XCTAssertFalse(viewModel.hasAdjustments)
    }

    /// Reset-all must not touch the develop settings or the LUT — it is one panel's button.
    func testResetAllLeavesDevelopAndTheLUTAlone() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.updateDocument { $0.rawDevelop.exposure = 0.7 }
        viewModel.selectLUT(TestImages.warmLUT())
        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5

        viewModel.resetAllAdjustments()

        XCTAssertEqual(viewModel.document.adjustments, [])
        XCTAssertEqual(viewModel.document.rawDevelop.exposure, 0.7, "develop is a different panel")
        XCTAssertNotNil(viewModel.document.lut.lutID, "the LUT is a different panel again")
    }
}

// MARK: - The tab

extension AdjustInspectorTests {

    /// Three tabs, in pipeline order left to right.
    func testTheInspectorHasThreeTabsInPipelineOrder() {
        XCTAssertEqual(AppViewModel.InspectorTab.allCases, [.info, .develop, .adjust])
        XCTAssertEqual(AppViewModel.InspectorTab.adjust.title, "Adjust")
    }

    /// The histogram is gated on the Info tab being on screen. Adjust is as much "a panel nobody is
    /// looking at" as Develop is, so switching to it must not start tallying pixels — the same
    /// finding `testNoHistogramIsTalliedWhileTheDevelopTabIsShowing` pins for the other tab.
    func testTheAdjustTabDoesNotTallyAHistogram() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        // Switch first, *then* open: opening with Info showing would legitimately tally one — see
        // testNoHistogramIsTalliedWhileTheDevelopTabIsShowing for the same pitfall on the other tab.
        viewModel.inspectorTab = .adjust
        viewModel.isInspectorPresented = true
        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5
        try await Task.sleep(for: .milliseconds(300))

        let requests = await fake.histogramRequests
        XCTAssertTrue(requests.isEmpty,
                      "the Adjust tab has no histogram; \(requests.count) tallies were issued")
        XCTAssertNil(viewModel.histogram)
    }
}

// MARK: - Render cost

extension AdjustInspectorTests {

    /// **An adjustment edit costs one render; a develop edit costs two.**
    ///
    /// `EditDocument.originalForComparison` keeps `rawDevelop` and strips `adjustments` (§8.5), so
    /// the comparison baseline moves when develop moves and stays put when an adjustment moves.
    /// That falls out of `pendingDevelopChange` never being set here, which is to say it works by
    /// accident of the current code — hence this test. Without it, a later edit that started
    /// scheduling the baseline unconditionally would double every slider tick's cost silently.
    func testAnAdjustmentEditDoesNotReRenderTheComparisonBaseline() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        // Let the opening renders settle so the count below is only this edit's.
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        try await Task.sleep(for: .milliseconds(200))
        let before = await fake.previewRequests.count

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5
        try await waitUntil("the adjusted render") {
            await fake.previewRequests.contains { $0.document.adjustments == [.exposure(ev: 1.5)] }
        }
        try await Task.sleep(for: .milliseconds(200))   // a second render would have landed by now

        let after = await fake.previewRequests.count
        XCTAssertEqual(after - before, 1,
                       "an adjustment must schedule the preview and nothing else; the A/B baseline "
                       + "strips adjustments, so it cannot have moved")
    }

    /// The other half of the same claim, so the test above cannot pass by the renderer being broken:
    /// a **develop** edit must still cost two.
    ///
    /// The count alone is not enough — a regression that called `schedulePreview()` twice and never
    /// `scheduleOriginalPreview()` would also produce a delta of 2 and pass. So, following the pattern
    /// `DevelopInspectorTests.testAMixedBurstStillRendersTheComparisonBaseline` and
    /// `testAPendingDevelopFlagDoesNotSurviveOpeningAnotherImage` already use, this also confirms
    /// *which* two renders landed: one of them must be the baseline itself, a request whose document
    /// equals `originalForComparison` and which carries no LUT — and the other must be the graded
    /// document, distinct in value from the baseline.
    ///
    /// That last clause is why an adjustment is set **before** the develop edit below. Left out, this
    /// test's document would have `adjustments == []` and `lut == .none` throughout, so
    /// `originalForComparison` — which only strips those two fields — is byte-for-byte equal to the
    /// current document. Both `schedulePreview()` and `scheduleOriginalPreview()` would then send
    /// identical payloads, and a regression that rendered the current document twice and never called
    /// `scheduleOriginalPreview()` at all would still satisfy `$0.document == expectedBaseline`. The
    /// pre-set adjustment gives the baseline a value the graded document does not share, so the two
    /// renders are actually distinguishable — do not delete it as unrelated setup.
    func testADevelopEditStillReRendersTheComparisonBaseline() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        try await Task.sleep(for: .milliseconds(200))

        // Set apart from the develop edit below and allowed to settle first, so its own render
        // isn't counted against the develop edit's expected delta of 2.
        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5
        try await waitUntil("the adjustment render") {
            await fake.previewRequests.contains { $0.document.adjustments == [.exposure(ev: 1.5)] }
        }
        try await Task.sleep(for: .milliseconds(200))
        let before = await fake.previewRequests.count

        viewModel.updateDocument { $0.rawDevelop.exposure = 0.7 }
        let expectedBaseline = viewModel.document.originalForComparison
        let expectedGraded = viewModel.document
        try await Task.sleep(for: .milliseconds(300))

        let requests = await fake.previewRequests
        XCTAssertEqual(requests.count - before, 2,
                       "a develop edit moves the baseline too — preview plus baseline")
        XCTAssertTrue(
            requests.contains { $0.document == expectedBaseline && $0.lutID == nil },
            "one of the two renders must be the comparison baseline itself, not just any two renders"
        )
        XCTAssertTrue(
            requests.contains { $0.document == expectedGraded },
            "the other render must be the graded document — the pre-set adjustment makes it differ "
            + "in value from the baseline, so this and the assertion above cannot both be satisfied "
            + "by two copies of the same render"
        )
    }
}

// MARK: - The A/B gate

extension AdjustInspectorTests {

    /// **§8.5, forced by this step.** Comparison used to be gated on `selectedLUT != nil`, which was
    /// defensible while a LUT was the only thing that could change the picture. The Adjust panel
    /// makes it wrong: an image with exposure pushed two stops and no LUT selected had a dead V key
    /// and a dead Space bar.
    ///
    /// This test pins the case that motivated the change. `isComparisonAvailable` itself carries the
    /// full rationale for the enumerated gate it settled on instead — see that property for why the
    /// obvious replacement, comparing the document against its own baseline, is not it.
    func testComparisonBecomesAvailableWithAnAdjustmentAndNoLUT() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        XCTAssertFalse(viewModel.isComparisonAvailable, "an untouched image has nothing to compare")

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 2.0

        XCTAssertNil(viewModel.selectedLUT, "no LUT — this is the case the old gate got wrong")
        XCTAssertTrue(viewModel.isComparisonAvailable)
    }

    /// The old behaviour must survive: a LUT alone still offers comparison.
    func testComparisonIsStillAvailableWithALUTAndNoAdjustments() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.selectLUT(TestImages.warmLUT())

        XCTAssertEqual(viewModel.document.adjustments, [])
        XCTAssertTrue(viewModel.isComparisonAvailable)
    }

    /// A **develop-only** edit must not offer comparison, because the baseline keeps `rawDevelop`
    /// (§8.5) — both sides would render identically, and a split view showing two identical
    /// pictures is worse than no split view.
    func testADevelopOnlyEditDoesNotOfferComparison() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.updateDocument { $0.rawDevelop.exposure = 0.7 }

        XCTAssertFalse(viewModel.isComparisonAvailable,
                       "the baseline keeps rawDevelop, so both halves would be the same picture")
    }

    /// Undoing the edit by hand withdraws the offer again — the sparse array is what makes this work.
    func testComparisonWithdrawsWhenTheAdjustmentReturnsToNeutral() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 2.0
        XCTAssertTrue(viewModel.isComparisonAvailable)

        viewModel.resetAdjustment(.exposure)
        XCTAssertFalse(viewModel.isComparisonAvailable)
    }

    /// The case that motivated the move off `document != document.originalForComparison`: a LUT at
    /// 0% intensity is structurally non-neutral — `lutID` is still set — but `LUTSettings.isIdentity`
    /// correctly calls it contributing nothing, and the render is pixel-identical to no LUT at all.
    /// The old structural gate offered a split view of two identical pictures here; it must not.
    func testComparisonIsNotAvailableWithALUTAtZeroIntensity() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.selectLUT(TestImages.warmLUT())
        viewModel.setLUTIntensity(0)

        XCTAssertNotNil(viewModel.document.lut.lutID, "the LUT is still selected, just at zero strength")
        XCTAssertFalse(viewModel.isComparisonAvailable)
    }

    // MARK: - B14: the histogram's caption

    /// The defect, stated as the row that was wrong: an adjustment-only edit captioned "Original".
    ///
    /// `InfoInspectorView` read `selectedLUT != nil ? "Graded" : "Original"`, which was a correct
    /// reading of the world until Step 10b shipped a second way to change the picture.
    func testAnAdjustmentOnlyEditIsNotCaptionedOriginal() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 2.0

        XCTAssertNil(viewModel.selectedLUT, "no LUT — this is the case the old label got wrong")
        XCTAssertEqual(
            viewModel.histogramSource, .adjusted,
            "the histogram is tallied from a genuinely graded render; captioning it \"Original\" "
                + "tells the user the opposite of what they are looking at (B14)"
        )
    }

    /// The whole mapping in one table, so a change has to be deliberate rather than incidental.
    ///
    /// Written as a table for the same reason `DevelopInspectorTests` writes its state mapping as
    /// one: the interesting content is the *combinations*, and a per-case test hides which ones were
    /// never considered.
    func testTheHistogramCaptionOverEveryLookState() async throws {
        // (apply a look, expected caption, why)
        let rows: [(String, (AppViewModel) -> Void, AppViewModel.HistogramSource)] = [
            ("untouched", { _ in }, .original),
            ("adjustment only", { $0.adjustmentBinding(for: .exposure).wrappedValue = 2.0 }, .adjusted),
            ("LUT only", { $0.selectLUT(TestImages.warmLUT()) }, .graded),
            ("LUT and adjustment", {
                $0.selectLUT(TestImages.warmLUT())
                $0.adjustmentBinding(for: .exposure).wrappedValue = 2.0
            }, .graded),
            ("LUT at zero intensity", {
                $0.selectLUT(TestImages.warmLUT())
                $0.setLUTIntensity(0)
            }, .original),
            ("LUT at zero intensity, with an adjustment", {
                $0.selectLUT(TestImages.warmLUT())
                $0.setLUTIntensity(0)
                $0.adjustmentBinding(for: .exposure).wrappedValue = 2.0
            }, .adjusted),
            ("develop only", { $0.developBinding(for: .exposure).wrappedValue = 0.7 }, .original),
        ]

        for (name, apply, expected) in rows {
            let viewModel = AppViewModel(engine: FakeRenderEngine())
            try await openStandardImage(viewModel)
            apply(viewModel)
            XCTAssertEqual(viewModel.histogramSource, expected, "look state: \(name)")
        }
    }

    /// Holding Space wins over everything else — it is showing the comparison baseline.
    func testHoldingSpaceCaptionsTheHistogramOriginal() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.selectLUT(TestImages.warmLUT())
        XCTAssertEqual(viewModel.histogramSource, .graded)

        viewModel.isShowingOriginal = true
        XCTAssertEqual(viewModel.histogramSource, .original)
    }
}
