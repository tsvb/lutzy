import XCTest
import CoreImage
@testable import LUTzyKit

/// Phase 2 Step 10a. The ship gate is "the inspector drives live re-render", which is a claim about
/// wiring, so most of this drives `FakeRenderEngine` and asserts on the requests it recorded.
@MainActor
final class DevelopInspectorTests: TempDirectoryTestCase {

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

    // MARK: - Probing

    func testCapabilitiesArePublishedAfterOpeningAnImage() async throws {
        // Neither `.everyGateOpen` nor `.distinctivelySeeded`: the second is
        // `FakeRenderEngine.stubbedCapabilities`' own field default, so an `AppViewModel` that
        // hardcoded it and never called the engine would pass this test just as happily, and the
        // first is a named constant in the module under test. This is the "wrote a value that
        // equals the default" weakness (docs/CODE_REVIEW.md §2) — use a value built here, with a
        // mixed set of flags and non-round seeds, so the test can only pass if the engine's answer
        // actually made it through.
        let distinctiveCapabilities = RAWCapabilities(
            isSharpnessSupported: true,
            isDetailSupported: true,
            isLocalToneMapSupported: false,
            asShotTemperature: 5842.2,
            asShotTint: 14.04
        )
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(distinctiveCapabilities)
        let viewModel = AppViewModel(engine: fake)
        XCTAssertNil(viewModel.rawCapabilities, "nothing open yet")

        try await openStandardImage(viewModel)
        try await waitUntil("capabilities to arrive") { viewModel.rawCapabilities != nil }

        XCTAssertEqual(viewModel.rawCapabilities, distinctiveCapabilities)
    }

    /// The probe costs ~25 ms. Paying that once per image is fine; paying it per render would put it
    /// on every frame of a slider drag.
    func testCapabilitiesAreProbedOncePerOpenAndNotPerRender() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities to arrive") { viewModel.rawCapabilities != nil }

        let afterOpen = await fake.capabilityProbeCount
        XCTAssertEqual(afterOpen, 1, "one open, one probe")

        // Several renders, no new image.
        viewModel.updateDocument { $0.rawDevelop.exposure = 0.5 }
        viewModel.updateDocument { $0.rawDevelop.exposure = 0.6 }
        viewModel.selectLUT(TestImages.warmLUT())
        try await Task.sleep(for: .milliseconds(200))

        let afterRenders = await fake.capabilityProbeCount
        XCTAssertEqual(afterRenders, 1, "rendering must never re-probe")
    }

    /// A standard image has no develop stage, so the panel must have nothing to offer.
    func testCapabilitiesAreClearedForAnImageWithNoDevelopStage() async throws {
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(nil)
        let viewModel = AppViewModel(engine: fake)

        try await openStandardImage(viewModel)
        try await Task.sleep(for: .milliseconds(200))

        // `nil` alone is also `AppViewModel.rawCapabilities`' pre-open default, so on its own this
        // assertion cannot tell "the engine was consulted and answered nil" apart from "the engine
        // was never consulted at all." Assert the probe count too, so the test can only pass if the
        // engine actually ran.
        let probeCount = await fake.capabilityProbeCount
        XCTAssertEqual(probeCount, 1, "the engine must still be consulted even with no develop stage")
        XCTAssertNil(viewModel.rawCapabilities)
    }

    // MARK: - Three panel states, not two

    /// **The panel used to lie while the probe was in flight.**
    ///
    /// `DevelopInspectorView` was `if let capabilities = viewModel.rawCapabilities { … } else {
    /// notRAW }`, and `rawCapabilities` is `nil` in two situations that mean opposite things:
    /// "this file has no develop stage" and "this file's develop stage has not been measured yet".
    /// `refreshCapabilities()` clears it **synchronously** on open and refills it 25–170 ms later, so
    /// opening a RAW with the Develop tab showing displayed *"No develop stage — Develop controls
    /// come from the RAW decoder. This image is already rendered."* for the duration of the probe —
    /// a false statement about the file, on every ←/→ step through a folder of RAWs, since
    /// `inspectorTab` is not reset on open.
    ///
    /// The mapping is asserted here rather than in the view because this repo has no SwiftUI view
    /// tests; that is the same reason `availableControls` is a value. Both inputs are exercised in
    /// both positions, so collapsing `.probing` back into `.noDevelopStage` — the regression — fails
    /// on the row that matters, and so does the mirror-image mistake of reporting `.probing` for a
    /// standard image whose answer has already arrived.
    func testThePanelStateMappingCoversAllThreeStates() {
        typealias State = AppViewModel.DevelopPanelState
        let caps = RAWCapabilities.distinctivelySeeded

        XCTAssertEqual(
            State(sourceIsRAW: true, capabilities: nil), .probing,
            "a RAW whose probe has not landed must not be told it has no develop stage — this is "
            + "the whole defect"
        )
        XCTAssertEqual(
            State(sourceIsRAW: false, capabilities: nil), .noDevelopStage,
            "a standard image genuinely has no develop stage"
        )
        XCTAssertEqual(
            State(sourceIsRAW: true, capabilities: caps), .ready(caps),
            "a probed RAW draws its own controls"
        )
        // The fourth combination is not reachable through `AppViewModel` — `RenderEngine` answers
        // `nil` for a standard image — but the mapping is a total function of two inputs and a
        // caller reading it as "capabilities win" should be able to rely on that, rather than on the
        // reachability argument holding forever.
        XCTAssertEqual(State(sourceIsRAW: false, capabilities: caps), .ready(caps))
    }

    /// The wiring on the CI-reachable side: a standard image is `.noDevelopStage` once the probe has
    /// answered, and `sourceIsRAW` is what says so.
    func testAStandardImageEndsOnNoDevelopStage() async throws {
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(nil)
        let viewModel = AppViewModel(engine: fake)
        XCTAssertEqual(viewModel.developPanelState, .noDevelopStage, "nothing open yet")

        try await openStandardImage(viewModel)
        try await waitUntil("the probe to answer") { await fake.capabilityProbeCount == 1 }
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(viewModel.sourceIsRAW, "a PNG does not go through the RAW decoder")
        XCTAssertEqual(viewModel.developPanelState, .noDevelopStage)
    }

    /// And the `.ready` side, end to end: the engine's answer becomes the panel's state.
    func testAProbedImageEndsOnReadyCarryingTheProbedCapabilities() async throws {
        let caps = RAWCapabilities.distinctivelySeeded
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(caps)
        let viewModel = AppViewModel(engine: fake)

        try await openStandardImage(viewModel)
        try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

        XCTAssertEqual(viewModel.developPanelState, .ready(caps))
    }

    /// **The state the defect was actually about, end to end on a real RAW.**
    ///
    /// The mapping test above pins `.probing` as a function of its inputs; this pins that the inputs
    /// genuinely take that combination on a real file — `sourceIsRAW` true while `rawCapabilities`
    /// is still `nil` — which is the part no synthetic value can vouch for, because
    /// `ImageSource.kind` for a URL comes from the file extension and `AppViewModel` only records a
    /// source for a file that actually decoded. The probe is gated so the window is held open rather
    /// than raced.
    ///
    /// Skips on CI, which has no DNG — read a green CI run as saying nothing about this row.
    func testARAWStaysOnProbingUntilTheProbeAnswers() async throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW; see Fixtures.localRAWURL and PHASE2_SPEC §8.9")
        }
        let caps = RAWCapabilities.distinctivelySeeded
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(caps)
        await fake.gateProbe()
        let viewModel = AppViewModel(engine: fake)

        viewModel.openImage(url: rawURL)
        try await waitUntil("the RAW to load") { viewModel.sourceImage != nil }
        try await waitUntil("the probe to start") { await fake.capabilityProbeCount == 1 }

        XCTAssertTrue(viewModel.sourceIsRAW, "a DNG goes through the RAW decoder")
        XCTAssertNil(viewModel.rawCapabilities, "precondition: the probe is still parked")
        XCTAssertEqual(
            viewModel.developPanelState, .probing,
            "the panel would be telling the user this RAW has no develop stage"
        )

        await fake.releaseProbe()
        try await waitUntil("the probe to answer") { viewModel.rawCapabilities != nil }
        XCTAssertEqual(viewModel.developPanelState, .ready(caps))
    }

    // MARK: - Coalescing

    /// A slider drag is many ticks. Rendering each one would be two full renders per tick, because
    /// a develop change also re-rasterizes the side-by-side baseline. Twenty ticks in one main-actor
    /// turn — the tightest a drag can be — must collapse, because the render loop reads the request
    /// when it starts rather than when it is scheduled.
    func testADragIssuesFarFewerRendersThanTicks() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        let atRest = await fake.previewRequests.count

        // Twenty ticks in quick succession, as a drag produces.
        for step in 1...20 {
            viewModel.updateDocument {
                $0.rawDevelop.exposure = Double(step) / 20.0
            }
        }
        // Let the final render land.
        try await waitUntil("the settled render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.exposure == 1.0 }
        }

        let issued = await fake.previewRequests.count - atRest
        XCTAssertLessThan(issued, 10, "20 ticks issued \(issued) renders — the render loop is not coalescing")
        XCTAssertGreaterThan(issued, 0)
    }

    /// ...and the value the user let go on is the one that gets rendered. A coalescer that dropped
    /// the *last* event would leave the screen showing a value the slider is not on.
    func testTheFinalValueOfADragIsTheOneRendered() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        for step in 1...10 {
            viewModel.updateDocument { $0.rawDevelop.exposure = Double(step) }
        }

        try await waitUntil("the final value to render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.exposure == 10.0 }
        }
        XCTAssertEqual(viewModel.document.rawDevelop.exposure, 10.0,
                       "the document must hold the released value immediately")
    }

    /// **An edit renders without waiting** — the defect this replaced. The old path parked every
    /// slider tick behind a 60 ms trailing timer that the next tick restarted, so a drag that never
    /// paused never rendered; the preview froze until the pointer stopped.
    ///
    /// The discriminator is **sequence, not elapsed time**: spin on `Task.yield()` — scheduling
    /// turns, not wall-clock — and require the render to appear. Hundreds of yields complete in a
    /// tiny fraction of any plausible debounce, so this fails if a timer of any length is put back
    /// in front of the render, where a deadline-based wait would pass either way.
    ///
    /// The second edit, with no suspension in between, pins the other half of the contract: the
    /// request is read when the render *starts*, so the first edit's value never renders on its own.
    func testAnEditRendersWithoutWaiting() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        viewModel.updateDocument { $0.rawDevelop.exposure = 0.42 }
        viewModel.updateDocument { $0.rawDevelop.gamutMappingEnabled = false }

        var sawBoth = false
        for _ in 0..<1000 {
            sawBoth = await fake.previewRequests.contains {
                $0.document.rawDevelop.exposure == 0.42 && $0.document.rawDevelop.gamutMappingEnabled == false
            }
            if sawBoth { break }
            await Task.yield()
        }
        XCTAssertTrue(sawBoth, "the edits must render without waiting on a timer")

        let requestsSoFar = await fake.previewRequests
        XCTAssertFalse(
            requestsSoFar.contains {
                $0.document.rawDevelop.exposure == 0.42 && $0.document.rawDevelop.gamutMappingEnabled != false
            },
            "the first edit rendered on its own — the loop captured its request at schedule time, "
            + "not when the render started"
        )
    }

    // MARK: - Coalesced bursts

    /// **Finding 1 regression.** When edits were debounced, a burst shared one timer task and only
    /// the last call's survived to fire; `developChanged` captured per call meant a burst that
    /// changed `rawDevelop` first and something else (here, `adjustments`) last fired with
    /// `developChanged == false`, and the comparison baseline never re-rendered. The debounce is
    /// gone, but the shape of the bug is not: any scheme that decides "does the baseline move?" from
    /// the last edit alone reintroduces it, so the burst stays pinned.
    func testAMixedBurstStillRendersTheComparisonBaseline() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        // First call in the burst changes rawDevelop...
        viewModel.updateDocument { $0.rawDevelop.exposure = 0.8 }
        // ...a second call in the same turn changes only adjustments. No `await` in between, so
        // both land before either render starts — exactly what a burst of slider ticks produces.
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.3)] }

        let expectedBaseline = viewModel.document.originalForComparison

        try await waitUntil("the comparison baseline to re-render") {
            await fake.previewRequests.contains { $0.document == expectedBaseline && $0.lutID == nil }
        }
    }

    /// **A develop edit pending at an open describes the image being left.** Written against the
    /// debounce, where `load()` had to clear a `pendingDevelopChange` flag or the *first unrelated
    /// edit on the new image* re-rasterized a comparison baseline for develop settings never touched
    /// on it. Found by `scripts/mutate-step10a.sh`: deleting that one line left every other test
    /// green.
    ///
    /// The flag is gone; the hazard is the same one in a new place. A develop edit schedules the
    /// baseline's render loop, and opening another image in the same turn must cancel that loop —
    /// `cancelPreviewRenders()` — rather than let it run, or be re-armed, against the new file.
    func testADevelopEditPendingAtOpenDoesNotLeakOntoTheNextImage() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        // A develop edit on the first image schedules both render loops...
        viewModel.updateDocument { $0.rawDevelop.exposure = 0.7 }
        // ...and opening another image immediately — no `await` in between, so neither loop has
        // started — cancels them. What they would have drawn belongs to the image being closed.
        let second = try Fixtures.writeGradientPNG(
            width: 20, height: 16, named: "second.png", in: tempDirectory
        )
        viewModel.openImage(url: second)
        try await waitUntil("the second image to load") { viewModel.sourceName == "second.png" }
        try await Task.sleep(for: .milliseconds(200))

        // A comparison-baseline render is exactly a request whose document has no adjustments —
        // `originalForComparison` strips them. Counting before and after is what makes the extra
        // render visible; both images legitimately produce one on open.
        let baselinesBefore = await fake.previewRequests.filter { $0.document.adjustments.isEmpty }.count

        // An edit on the new image that touches nothing in `rawDevelop`. The baseline only moves
        // with develop, so this must not re-rasterize it.
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.3)] }
        try await waitUntil("the edited render") {
            await fake.previewRequests.contains { !$0.document.adjustments.isEmpty }
        }
        try await Task.sleep(for: .milliseconds(150))

        let baselinesAfter = await fake.previewRequests.filter { $0.document.adjustments.isEmpty }.count
        XCTAssertEqual(
            baselinesAfter, baselinesBefore,
            "an edit that changed no develop setting re-rasterized the comparison baseline, so a "
            + "develop edit from the previous image survived the open"
        )
    }

    // MARK: - The histogram belongs to the Info tab

    /// The histogram is gated on the inspector being open "so we don't tally pixels for a panel
    /// nobody's looking at" — its own words. The Develop tab breaks that: the inspector is open, the
    /// histogram is not on screen, and every settled render of a slider drag was tallying one. An
    /// open inspector parked on Develop is as much a panel nobody's looking at as a closed one.
    func testNoHistogramIsTalliedWhileTheDevelopTabIsShowing() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        // Switch first, *then* open: opening with Info showing would legitimately tally one.
        viewModel.inspectorTab = .develop
        viewModel.isInspectorPresented = true

        viewModel.developBinding(for: .exposure).wrappedValue = 0.9
        try await waitUntil("the develop render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.exposure == 0.9 }
        }
        // The tally would be issued from the same task that publishes the preview, so by the time
        // that render is visible it would already be recorded. The sleep is belt and braces.
        try await Task.sleep(for: .milliseconds(150))

        let requests = await fake.histogramRequests
        XCTAssertTrue(requests.isEmpty,
                      "the Develop tab has no histogram; \(requests.count) tallies were issued for a "
                      + "chart nobody can see")
        XCTAssertNil(viewModel.histogram)
    }

    /// ...and coming **back** has to recompute, or the gate above just makes the histogram blank (on
    /// a first visit) or stale (on a return) for anyone who touched Develop.
    func testSwitchingBackToInfoRecomputesTheHistogram() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        viewModel.inspectorTab = .develop
        viewModel.isInspectorPresented = true

        // Edit while the histogram is off-screen. Nothing is tallied, so whatever Info shows next
        // can only be right if the switch itself recomputes.
        viewModel.developBinding(for: .exposure).wrappedValue = 0.9
        try await waitUntil("the develop render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.exposure == 0.9 }
        }
        try await Task.sleep(for: .milliseconds(150))
        let beforeSwitch = await fake.histogramRequests
        XCTAssertTrue(beforeSwitch.isEmpty, "precondition: nothing tallied while on Develop")

        viewModel.inspectorTab = .info

        try await waitUntil("the histogram to be published") { viewModel.histogram != nil }
        let after = await fake.histogramRequests
        XCTAssertEqual(after.count, 1, "returning to Info should tally exactly once")
        XCTAssertEqual(
            after.first?.document.rawDevelop.exposure, 0.9,
            "the recomputed histogram must describe the document as it is now, not as it was when "
            + "the user left the tab"
        )
    }

    /// Leaving Info for Develop and coming back must not need an intervening render — and must not
    /// tally on the way *out*, either.
    func testLeavingInfoStopsTalliesAndReturningResumesThem() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        viewModel.isInspectorPresented = true   // Info is the default tab
        try await waitUntil("the first tally") { await !fake.histogramRequests.isEmpty }
        let onInfo = await fake.histogramRequests.count

        viewModel.inspectorTab = .develop
        try await Task.sleep(for: .milliseconds(100))
        let afterLeaving = await fake.histogramRequests.count
        XCTAssertEqual(afterLeaving, onInfo, "switching away must not tally")

        viewModel.inspectorTab = .info
        try await waitUntil("the tally on return") {
            await fake.histogramRequests.count > onInfo
        }
    }

    // MARK: - The ship gate: edits reach the renderer

    func testADevelopEditRendersTheChangedDocument() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        viewModel.developBinding(for: .exposure).wrappedValue = 1.25

        try await waitUntil("the edited render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.exposure == 1.25 }
        }
    }

    /// A control bound to a `nil` setting has to show the decoder's own value, not zero. As-shot
    /// white balance on a real file is ~5842 K; a slider opening at 0 K would be nonsense.
    func testAnUnsetControlReadsBackTheSeedRatherThanZero() async throws {
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(RAWCapabilities(asShotTemperature: 5842.2, asShotTint: 14.04))
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

        XCTAssertNil(viewModel.document.rawDevelop.neutralTemperature, "nothing written yet")
        XCTAssertEqual(viewModel.developBinding(for: .whiteBalance).wrappedValue, 5842.2, accuracy: 0.01,
                       "an unset white balance must display the file's as-shot value")
        XCTAssertEqual(viewModel.developBinding(for: .exposure).wrappedValue, 0,
                       "exposure has a fixed decoder default of 0")
    }

    /// Presenting the panel must not write anything. `.neutral` is byte-identical to
    /// `developRAWNeutral` *because it sets nothing*; seeding every field on open would quietly end
    /// that, and the derive baseline reasons about a neutral document.
    func testReadingEveryControlWritesNothing() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

        for control in DevelopControl.allCases {
            _ = viewModel.developBinding(for: control).wrappedValue
        }

        XCTAssertTrue(viewModel.document.rawDevelop.isNeutral,
                      "opening the panel must not write settings")
    }

    /// **Every** seeded control reads **its own** seed.
    ///
    /// The previous version of this file proved the seed path for exactly one control, white
    /// balance, and every stub left the other seeds at 0 — so for the rest, "read the seed" and
    /// "return a hardcoded 0" were the same number and eight controls were guessing. A table with a
    /// distinct value per field means a getter reading the wrong seed names itself in the failure.
    func testEverySeededControlReadsItsOwnSeed() async throws {
        let caps = RAWCapabilities.distinctivelySeeded
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(caps)
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

        let seeded: [(DevelopControl, Double)] = [
            (.baselineExposure, caps.baselineExposure),
            (.shadowBias, caps.shadowBias),
            (.whiteBalance, caps.asShotTemperature),
            (.sharpness, caps.sharpnessAmount),
            (.contrast, caps.contrastAmount),
            (.detail, caps.detailAmount),
            (.moireReduction, caps.moireReductionAmount),
            (.localToneMap, caps.localToneMapAmount),
            (.luminanceNoiseReduction, caps.luminanceNoiseReductionAmount),
            (.colorNoiseReduction, caps.colorNoiseReductionAmount),
            (.lensCorrection, caps.lensCorrectionEnabled ? 1 : 0),
        ]

        // Distinctness is what gives the table its power: two rows sharing a value would let a
        // getter read the wrong field and still pass.
        XCTAssertEqual(Set(seeded.map(\.1)).count, seeded.count,
                       "the seed values must all differ, or a mis-wired getter can pass by accident")

        for (control, expected) in seeded {
            XCTAssertEqual(
                viewModel.developValue(for: control), expected, accuracy: 0.0001,
                "\(control.rawValue) must display the decoder's own seed, not a guessed constant"
            )
        }

        // Tint travels on its own binding, so it needs its own row.
        XCTAssertEqual(viewModel.developTintBinding().wrappedValue, caps.asShotTint, accuracy: 0.0001)

        // And the controls that genuinely *do* have a fixed documented default keep it — a blanket
        // "read a seed for everything" would have broken these.
        let fixedDefault: [(DevelopControl, Double)] = [
            (.exposure, 0),
            (.boost, 1),
            (.boostShadow, 1),
            (.extendedDynamicRange, 0),
            (.gamutMapping, 1),
            (.highlightRecovery, 1),
        ]
        for (control, expected) in fixedDefault {
            XCTAssertEqual(viewModel.developValue(for: control), expected)
        }

        // A new `DevelopControl` must arrive with a row in one of the two tables above, not inherit
        // no coverage by omission — the same "silently inherits" guard
        // `RAWCapabilitiesTests.testEveryControlsSliderRangeIsPinned` applies to slider ranges.
        XCTAssertEqual(
            Set(seeded.map(\.0)).union(fixedDefault.map(\.0)), Set(DevelopControl.allCases),
            "every control must be covered by either the per-image seed table or the fixed-default "
            + "table above, or a new control would ship with no seed coverage tested at all"
        )

        // Reading all of that still wrote nothing.
        XCTAssertTrue(viewModel.document.rawDevelop.isNeutral)
    }

    /// **`lensCorrectionEnabled` is a `Bool`**, so `RAWCapabilities.distinctivelySeeded`'s single
    /// `false` above cannot by itself distinguish "reads the seed" from "returns a constant" — a
    /// getter hardcoded to `false` (the field's own default, and the getter's own tail fallback) would
    /// pass the table above just as happily as a correct one. Only two stubs, one `true` and one
    /// `false`, can pin the getter to the seed rather than to either constant.
    ///
    /// This is not academic: the Leica in `realworldtest/` reports `lensCorrectionEnabled == true`
    /// (`RAWCapabilitiesTests.testProbingARealRAWReportsItsDecodersSeeds`). Under the regression this
    /// guards against, that camera's toggle would show OFF while the decoder already has it ON, and
    /// the user flipping it "on" would write a value into a document that was already effectively on
    /// — no longer neutral, for no visual change at all.
    func testLensCorrectionValueFollowsTheSeedInBothDirections() async throws {
        for seedValue in [true, false] {
            let fake = FakeRenderEngine()
            await fake.setStubbedCapabilities(RAWCapabilities(lensCorrectionEnabled: seedValue))
            let viewModel = AppViewModel(engine: fake)
            try await openStandardImage(viewModel)
            try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

            XCTAssertEqual(
                viewModel.developValue(for: .lensCorrection), seedValue ? 1 : 0,
                "lensCorrection must track the decoder's own seed (\(seedValue)), not a hardcoded "
                + "constant"
            )
        }
    }

    // MARK: - Tint

    /// Tint is the one control with no `DevelopControl` case of its own, so nothing in the table
    /// tests reaches it. It gets the same two guarantees as the rest: reading never writes, and what
    /// you set is what you read back.
    func testTheTintBindingRoundTripsAndNeverWritesOnRead() async throws {
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(RAWCapabilities(asShotTemperature: 5842.2, asShotTint: 14.04))
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

        // Read, repeatedly. `.neutral` is byte-identical to `developRAWNeutral` *because it sets
        // nothing*; a getter that seeded on read would quietly end that and move the derive baseline.
        for _ in 0..<3 {
            XCTAssertEqual(viewModel.developTintBinding().wrappedValue, 14.04, accuracy: 0.0001,
                           "an unset tint must display the file's as-shot value")
        }
        XCTAssertNil(viewModel.document.rawDevelop.neutralTint, "reading must not write")
        XCTAssertTrue(viewModel.document.rawDevelop.isNeutral)

        // Write, then read back — through the binding, not the document, so a getter that ignored
        // the stored value and always returned the seed fails here.
        viewModel.developTintBinding().wrappedValue = -87.5
        XCTAssertEqual(viewModel.document.rawDevelop.neutralTint, -87.5)
        XCTAssertEqual(viewModel.developTintBinding().wrappedValue, -87.5, accuracy: 0.0001,
                       "a written tint must win over the seed")

        // And the write reaches the renderer.
        try await waitUntil("the tinted render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.neutralTint == -87.5 }
        }
    }

    // MARK: - Sliders and toggles share one path

    /// `developBinding` used to pass `debounced: !control.isToggle`, and this test pinned the toggle
    /// half. The split is gone — every write renders at once — so what is left to pin is that a
    /// toggle written straight after a slider, through the same binding factory, renders **with**
    /// the slider's value and never lets the slider's value render alone.
    ///
    /// Same discriminator as `testAnEditRendersWithoutWaiting`: **sequence, not elapsed time**.
    func testWritingAToggleThroughTheBindingRendersWithoutWaiting() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        viewModel.developBinding(for: .exposure).wrappedValue = 0.42
        XCTAssertTrue(DevelopControl.gamutMapping.isToggle, "this test needs a toggle control")
        viewModel.developBinding(for: .gamutMapping).wrappedValue = 0

        var sawToggle = false
        for _ in 0..<1000 {
            sawToggle = await fake.previewRequests.contains {
                $0.document.rawDevelop.gamutMappingEnabled == false
            }
            if sawToggle { break }
            await Task.yield()
        }
        XCTAssertTrue(sawToggle, "a toggle written through developBinding must render immediately")

        // The toggle's 0 must have become `false`, not 0.0 in some numeric field.
        XCTAssertEqual(viewModel.document.rawDevelop.gamutMappingEnabled, false)
        let soFar = await fake.previewRequests
        XCTAssertFalse(
            soFar.contains {
                $0.document.rawDevelop.exposure == 0.42
                    && $0.document.rawDevelop.gamutMappingEnabled != false
            },
            "the slider's value rendered on its own, before the toggle written in the same turn"
        )
    }

    /// The mirror image: a *slider* drag through the same binding must still coalesce, or the test
    /// above could be satisfied by a binding that renders every tick.
    func testWritingASliderThroughTheBindingStillCoalesces() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        let atRest = await fake.previewRequests.count

        XCTAssertFalse(DevelopControl.exposure.isToggle)
        for step in 1...20 {
            viewModel.developBinding(for: .exposure).wrappedValue = Double(step) / 20.0
        }
        try await waitUntil("the settled render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.exposure == 1.0 }
        }

        let issued = await fake.previewRequests.count - atRest
        XCTAssertLessThan(issued, 10,
                          "20 slider ticks issued \(issued) renders — developBinding stopped coalescing")
    }

    func testResettingAControlReturnsItToUnset() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

        viewModel.developBinding(for: .exposure).wrappedValue = 2.0
        XCTAssertEqual(viewModel.document.rawDevelop.exposure, 2.0)

        viewModel.resetDevelop(.exposure)
        XCTAssertNil(viewModel.document.rawDevelop.exposure, "reset means unset, not zero")

        viewModel.developBinding(for: .exposure).wrappedValue = 2.0
        viewModel.developBinding(for: .whiteBalance).wrappedValue = 3000
        viewModel.resetAllDevelop()
        XCTAssertTrue(viewModel.document.rawDevelop.isNeutral)
    }

    /// **White balance is one control over two settings.** `resetDevelop(.whiteBalance)` has to clear
    /// `neutralTint` as well as `neutralTemperature`; there is no `.tint` case to reset it through, so
    /// a dropped line would strand the tint set forever with a reset button that appears to work.
    /// Nothing caught that before — `resetAllDevelop` clears both by replacing the whole struct.
    func testResettingWhiteBalanceClearsBothTemperatureAndTint() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

        viewModel.developBinding(for: .whiteBalance).wrappedValue = 3200
        viewModel.developTintBinding().wrappedValue = -42
        XCTAssertEqual(viewModel.document.rawDevelop.neutralTemperature, 3200)
        XCTAssertEqual(viewModel.document.rawDevelop.neutralTint, -42)

        viewModel.resetDevelop(.whiteBalance)

        XCTAssertNil(viewModel.document.rawDevelop.neutralTemperature, "reset means unset, not zero")
        XCTAssertNil(viewModel.document.rawDevelop.neutralTint,
                     "the tint half of white balance has no reset of its own — this one must clear it")
        // Both halves gone means the document is untouched again, which is the observable
        // consequence: a stranded tint would keep it non-neutral and keep the develop stage running.
        XCTAssertTrue(viewModel.document.rawDevelop.isNeutral,
                      "resetting the only edited control must return the document to neutral")
    }

    /// Reset per control, one at a time, across the whole enum: each returns to neutral on its own.
    /// The single-control test above only exercises `.exposure`, so a `resetDevelop` arm that cleared
    /// the wrong field would survive it.
    func testEveryControlResetsToUnsetOnItsOwn() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

        for control in DevelopControl.allCases {
            // A value the seed cannot coincide with, so the write genuinely changes the document.
            let written: Double = control.isToggle ? 0 : (control.range.lowerBound + 0.03)
            viewModel.developBinding(for: control).wrappedValue = written
            XCTAssertFalse(viewModel.document.rawDevelop.isNeutral,
                           "writing \(control.rawValue) should have left the document non-neutral")

            viewModel.resetDevelop(control)
            XCTAssertTrue(viewModel.document.rawDevelop.isNeutral,
                          "resetDevelop(.\(control.rawValue)) left something set — it is clearing "
                          + "the wrong field, or not every field it writes")
        }
    }
}
