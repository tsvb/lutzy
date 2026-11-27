import XCTest
import CoreImage
@testable import LUTzyKit

/// The preview render loops — `AppViewModel.schedulePreview()` and `scheduleOriginalPreview()`.
///
/// They replaced a 60 ms trailing debounce that every slider tick restarted, so a drag that never
/// paused never rendered: the preview froze for the length of the drag and caught up on release.
/// The contract now is **leading edge, latest wins, at most one render in flight**, and each test
/// here pins one clause of it. `FakeRenderEngine.gatePreviews()` holds a render in flight, which is
/// the only way to reach the coalescing path without racing the scheduler.
///
/// The batched-in-one-turn cases (a burst never renders a partial state) live beside the panels
/// that produce them, in `DevelopInspectorTests` and `AdjustInspectorTests`.
@MainActor
final class PreviewSchedulingTests: TempDirectoryTestCase {

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

    /// Open an image and let its opening renders — preview and baseline — finish, so every count a
    /// test takes afterwards is its own.
    private func openAndSettle(_ viewModel: AppViewModel, _ fake: FakeRenderEngine) async throws {
        let url = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "shot.png", in: tempDirectory)
        viewModel.openImage(url: url)
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }
        try await waitUntil("the opening renders") { await fake.previewRequests.count >= 2 }
        try await Task.sleep(for: .milliseconds(100))
    }

    /// Many scheduling turns: enough for a scheduler that issued a render per edit to have issued
    /// them all, at no wall-clock cost worth mentioning.
    private func spin() async {
        for _ in 0..<200 { await Task.yield() }
    }

    // MARK: - Latest wins

    /// **The coalescing clause.** Edits made while a render is in flight must not each queue a
    /// render: they collapse into one follow-up, of the newest value, issued when the in-flight one
    /// lands. The intermediate values are never drawn — the user has already moved past them.
    ///
    /// Without this, a slider drag over an expensive render builds a queue the engine drains long
    /// after the pointer stopped, which is the same frozen-preview symptom by another route.
    func testEditsDuringAnInFlightRenderCoalesceIntoOneFollowUp() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openAndSettle(viewModel, fake)
        let atRest = await fake.previewRequests.count

        await fake.gatePreviews()
        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 0.25
        try await waitUntil("the first render to park") { await fake.parkedPreviewCount == 1 }

        for ev in [0.5, 0.75, 1.0] {
            viewModel.adjustmentBinding(for: .exposure).wrappedValue = ev
            await spin()
        }
        let issuedWhileParked = await fake.previewRequests.count - atRest
        XCTAssertEqual(issuedWhileParked, 1,
                       "edits made during an in-flight render each issued their own render")

        await fake.releasePreviews()
        try await waitUntil("the newest value to render") {
            await fake.previewRequests.contains { $0.document.adjustments == [.exposure(ev: 1.0)] }
        }
        try await Task.sleep(for: .milliseconds(100))

        let drawn = await fake.previewRequests.dropFirst(atRest).map(\.document.adjustments)
        XCTAssertEqual(drawn, [[.exposure(ev: 0.25)], [.exposure(ev: 1.0)]],
                       "expected the in-flight render and one follow-up of the newest value, nothing else")
    }

    /// The baseline panel has its own loop and its own generation counter. A develop drag moves both
    /// panels, and each must coalesce on its own — a baseline that queued per tick would cost as much
    /// as the debounce it replaced was protecting against.
    func testTheComparisonBaselineCoalescesToo() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openAndSettle(viewModel, fake)
        let atRest = await fake.previewRequests.count

        await fake.gatePreviews()
        viewModel.updateDocument { $0.rawDevelop.exposure = 0.25 }
        // One graded render and one baseline render, both parked.
        try await waitUntil("both renders to park") { await fake.parkedPreviewCount == 2 }

        for ev in [0.5, 0.75, 1.0] {
            viewModel.updateDocument { $0.rawDevelop.exposure = ev }
            await spin()
        }
        let issuedWhileParked = await fake.previewRequests.count - atRest
        XCTAssertEqual(issuedWhileParked, 2, "one in flight per panel, and nothing queued behind them")

        await fake.releasePreviews()
        let baseline = viewModel.document.originalForComparison
        try await waitUntil("the newest baseline to render") {
            await fake.previewRequests.contains { $0.document == baseline && $0.lutID == nil }
        }
        try await Task.sleep(for: .milliseconds(100))

        let issued = await fake.previewRequests.count - atRest
        XCTAssertEqual(issued, 4, "each panel: the in-flight render plus one follow-up")
    }

    // MARK: - Leading edge

    /// The intensity slider had its own copy of the debounce. It must render on the first tick, with
    /// no timer in front of it — **sequence, not elapsed time**, as in
    /// `DevelopInspectorTests.testAnEditRendersWithoutWaiting`.
    func testAnIntensityTickRendersWithoutWaiting() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openAndSettle(viewModel, fake)

        let lut = TestImages.warmLUT()
        viewModel.selectLUT(lut)
        try await waitUntil("the graded render") {
            await fake.previewRequests.contains { $0.lutID == lut.lutID }
        }

        viewModel.setLUTIntensity(0.3)
        var sawTick = false
        for _ in 0..<1000 {
            sawTick = await fake.previewRequests.contains { $0.document.lut.intensity == 0.3 }
            if sawTick { break }
            await Task.yield()
        }
        XCTAssertTrue(sawTick, "an intensity tick must render without waiting on a timer")
    }

    // MARK: - The histogram waits for the loop to settle

    /// Every frame of a drag is now published, so a histogram tallied per frame would put a second
    /// render on the actor between every pair of preview frames and halve the frame rate the user is
    /// watching. It is tallied once, for the frame the loop settled on.
    func testTheHistogramIsTalliedWhenTheLoopSettlesNotPerFrame() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openAndSettle(viewModel, fake)

        // Info is the default tab; opening the inspector tallies once on its own.
        XCTAssertEqual(viewModel.inspectorTab, .info)
        viewModel.isInspectorPresented = true
        try await waitUntil("the opening tally") { await !fake.histogramRequests.isEmpty }
        try await Task.sleep(for: .milliseconds(100))
        let tallied = await fake.histogramRequests.count

        await fake.gatePreviews()
        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 0.25
        try await waitUntil("the first render to park") { await fake.parkedPreviewCount == 1 }
        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.0
        await spin()

        await fake.releasePreviews()
        try await waitUntil("the newest value to render") {
            await fake.previewRequests.contains { $0.document.adjustments == [.exposure(ev: 1.0)] }
        }
        try await waitUntil("the settled tally") { await fake.histogramRequests.count > tallied }
        try await Task.sleep(for: .milliseconds(150))

        let tallies = await fake.histogramRequests.dropFirst(tallied).map(\.document.adjustments)
        XCTAssertEqual(tallies, [[.exposure(ev: 1.0)]],
                       "two frames were drawn; only the one the loop settled on should be tallied")
    }
}
