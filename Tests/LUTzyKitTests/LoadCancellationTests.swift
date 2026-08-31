import XCTest
import CoreImage
@testable import LUTzyKit

/// **B15** (`docs/CODE_REVIEW.md`): work started for the image on screen must survive a *failed* open.
///
/// `load()` cancelled six tasks up front, before it knew whether the new file would even decode. For
/// the four that render the incoming image that is right — they are about to be superseded. For the
/// two that describe the image *already displayed* it was wrong, because a load that fails never
/// publishes a new source and never restarts them: only the `.success` branch calls
/// `refreshCapabilities()` and `refreshMetadata()`.
///
/// The rule the fix follows: **cancel at the refresh site, not the load site.** The refresh site is
/// the only one that knows a replacement is actually coming.
///
/// Both defects need two opens to reach, and every `developPanelState` test before this one opened
/// exactly one image. That is the whole reason they went unseen, so these tests open two.
@MainActor
final class LoadCancellationTests: TempDirectoryTestCase {

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

    /// A file with a decodable extension and undecodable bytes, so `load` reaches its `.failure`
    /// branch rather than its cancellation guard.
    private func writeUndecodableFile(named name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try Data("not an image".utf8).write(to: url)
        return url
    }

    /// **The mechanism, on CI.**
    ///
    /// No RAW is needed to pin the cancellation rule itself: `refreshCapabilities()` probes for any
    /// source, and the fake answers for any source. What a RAW is needed for is the *consequence* —
    /// `developPanelState` reaching `.probing` — which the DNG-gated test below covers.
    ///
    /// Reading it: the probe is parked with the first image open, then a second open fails on top of
    /// it. Before the fix, `load()` cancelled the parked probe, `releaseProbe()` resumed a task whose
    /// `Task.isCancelled` guard then discarded the answer, and `rawCapabilities` stayed `nil` forever
    /// with nothing left to set it.
    func testAFailedOpenDoesNotCancelTheInFlightCapabilityProbe() async throws {
        let caps = RAWCapabilities.distinctivelySeeded
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(caps)
        await fake.gateProbe()
        let viewModel = AppViewModel(engine: fake)

        let good = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "first.png", in: tempDirectory)
        viewModel.openImage(url: good)
        try await waitUntil("the first image to load") { viewModel.sourceImage != nil }
        try await waitUntil("the probe to park") { await fake.capabilityProbeCount == 1 }
        XCTAssertNil(viewModel.rawCapabilities, "precondition: the probe has not answered yet")

        // The second open fails. Nothing about the first image has left the screen.
        viewModel.openImage(url: try writeUndecodableFile(named: "broken.png"))
        try await waitUntil("the failed open to report") { viewModel.errorMessage != nil }
        XCTAssertNotNil(viewModel.sourceImage, "the undecodable file must not replace what is shown")

        await fake.releaseProbe()

        try await waitUntil("the probe to answer anyway") { viewModel.rawCapabilities != nil }
        XCTAssertEqual(
            viewModel.rawCapabilities, caps,
            """
            The probe for the image still on screen was cancelled by an unrelated failed open and \
            never restarted — only the .success branch calls refreshCapabilities(). On a RAW this \
            strands developPanelState on .probing indefinitely (B15).
            """
        )
    }

    /// A *successful* open must still supersede the previous probe — the fix must not turn a stale
    /// answer loose. Without this, "stop cancelling the probe" is satisfiable by never cancelling it,
    /// which would let the previous image's capabilities land on the new one.
    func testASuccessfulOpenStillReplacesThePreviousProbesAnswer() async throws {
        let stale = RAWCapabilities.distinctivelySeeded
        let fresh = RAWCapabilities(
            isSharpnessSupported: false,
            isDetailSupported: true,
            asShotTemperature: 3210.5,
            asShotTint: -7.25
        )
        XCTAssertNotEqual(stale, fresh, "the two answers must be distinguishable for this to assert anything")

        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(stale)
        await fake.gateProbe()
        let viewModel = AppViewModel(engine: fake)

        let first = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "a.png", in: tempDirectory)
        viewModel.openImage(url: first)
        try await waitUntil("the first image to load") { viewModel.sourceImage != nil }
        try await waitUntil("the first probe to park") { await fake.capabilityProbeCount == 1 }

        // A second open that succeeds, while the first probe is still parked.
        await fake.setStubbedCapabilities(fresh)
        let second = try Fixtures.writeGradientPNG(width: 16, height: 16, named: "b.png", in: tempDirectory)
        viewModel.openImage(url: second)
        try await waitUntil("the second image to load") { viewModel.sourceName == "b.png" }

        await fake.releaseProbe()
        try await waitUntil("a probe to answer") { viewModel.rawCapabilities != nil }

        XCTAssertEqual(
            viewModel.rawCapabilities, fresh,
            "the first image's parked probe answered onto the second image — refreshCapabilities() "
                + "must cancel the one it supersedes"
        )
    }

    /// **The consequence, on a real RAW.** `developPanelState` is what the user sees, and it only
    /// reaches `.probing` for a file that genuinely decodes through the RAW path — `ImageSource.kind`
    /// comes from the extension, and `AppViewModel` records a source only for a file that decoded.
    ///
    /// Skips on CI, which has no DNG; the mechanism test above is the one that runs there.
    func testAFailedOpenDuringTheProbeDoesNotStrandTheDevelopPanel() async throws {
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
        try await waitUntil("the probe to park") { await fake.capabilityProbeCount == 1 }
        XCTAssertEqual(viewModel.developPanelState, .probing, "precondition: parked mid-probe")

        viewModel.openImage(url: try writeUndecodableFile(named: "broken.dng"))
        try await waitUntil("the failed open to report") { viewModel.errorMessage != nil }

        XCTAssertTrue(viewModel.sourceIsRAW, "the RAW is still the open image")
        await fake.releaseProbe()

        try await waitUntil("the panel to leave .probing") { viewModel.developPanelState != .probing }
        XCTAssertEqual(
            viewModel.developPanelState, .ready(caps),
            "the panel spins on \"Reading the decoder's develop controls…\" forever, beside a RAW "
                + "that is still on screen, recoverable only by opening another image (B15)"
        )
    }

    /// The metadata half of B15, pinned as source text.
    ///
    /// `refreshMetadata` fired an **unstored** `Task.detached`: no handle, so nothing could stop image
    /// A's EXIF read from landing after image B's had been published, and the Info panel then
    /// described the wrong file. `ImageMetadata.read` on a 30 MB DNG is slow enough to lose that race
    /// on a held-down arrow key. B11 was the same shape one layer over.
    ///
    /// **Read as text because the race is not deterministically reproducible from outside.**
    /// `ImageMetadata.read` is a static call with no injection seam, so a test cannot hold one read
    /// open while another finishes — the honest options were a timing-dependent test that would flake,
    /// or this. This catches deletion of either half of the fix, which is the failure that actually
    /// happens to lines like these, and it is the same reasoning and the same idiom as
    /// `RenderStackTests`. It does not prove the ordering; nothing here does, and `CODE_REVIEW.md`
    /// says so rather than implying coverage this does not have.
    func testTheMetadataReadIsCancellableAndChecksBeforePublishing() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/LUTzyKit/ViewModels/AppViewModel.swift"),
            encoding: .utf8
        )

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("private func refreshMetadata(") }) else {
            return XCTFail("could not find refreshMetadata in AppViewModel.swift")
        }
        let body = lines[start..<min(start + 20, lines.count)]
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        XCTAssertTrue(
            body.contains("metadataTask?.cancel()"),
            "refreshMetadata must cancel the read it supersedes, or a slow EXIF read from the "
                + "previous image can publish over the current one's (B15)"
        )
        XCTAssertTrue(
            body.contains("metadataTask = Task"),
            "the read must be stored, or there is no handle to cancel"
        )
        XCTAssertTrue(
            body.contains("Task.isCancelled"),
            "cancellation must be checked before publishing — cancelling a detached task that never "
                + "looks at isCancelled does not stop it writing self.metadata"
        )
    }
}
