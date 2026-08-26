import XCTest
import simd
@testable import LUTzyKit

/// The derive *pipeline* still needs a RAW fixture to test end to end, but its
/// lifecycle — naming, the scratch-until-saved rule, cancellation, and the save
/// itself — does not. Splitting the save into a `performSave(to:)` core plus a
/// panel wrapper is what makes that reachable.
@MainActor
final class DeriveCoordinatorTests: TempDirectoryTestCase {

    /// Stand in for a completed derive without running the extractor.
    ///
    /// The LUT is built through `DeriveCoordinator.makeDerivedLUT` — the same call `derive` makes —
    /// rather than with a hand-rolled `CubeLUT`. A fixture that constructs its own is free to differ
    /// from production in the field under test, which is precisely how the derived-LUT resolution
    /// bug survived two green tests until Step 9.
    private func installScratchResult(
        on coordinator: DeriveCoordinator,
        named name: String = "shot_recipe_33_Rec709"
    ) throws -> URL {
        let scratch = tempDirectory.appendingPathComponent("\(name).cube")
        let cube = [SIMD3<Float>](repeating: SIMD3(0.25, 0.5, 0.75), count: 8)
        try CubeLUT.write(cube: cube, size: 2, title: name, to: scratch)
        let lut = DeriveCoordinator.makeDerivedLUT(cube: cube, size: 2, name: name)
        coordinator.setScratchResult(lut: lut, report: nil, scratchURL: scratch)
        return scratch
    }

    /// The scratch file is still written and still kept — Step 9 changed what *names* the LUT, not
    /// the bookkeeping around it. A derived LUT's identity must not be a temp path, and the temp file
    /// must still be there for `performSave` to copy.
    func testTheDerivedLUTIsNotNamedAfterItsScratchFile() throws {
        let coordinator = DeriveCoordinator()
        let scratch = try installScratchResult(on: coordinator)

        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.path),
                      "the scratch .cube is still written and kept")
        let lut = try XCTUnwrap(coordinator.derivedLUT)
        XCTAssertTrue(lut.lutID.isDerived, "a derived LUT carries a derived:// identity")
        XCTAssertNotEqual(lut.id, scratch.path,
                          "a temp path must never be a LUT's identity — it can be reused after a sweep")
    }

    // MARK: - Naming

    func testDerivedNameEncodesSourceAndSize() {
        let jpg = URL(fileURLWithPath: "/photos/20260525_102528_L1031183.JPG")
        XCTAssertEqual(
            DeriveCoordinator.derivedName(forJPG: jpg, size: 33),
            "20260525_102528_L1031183_recipe_33_Rec709"
        )
    }

    /// The name has to survive a round trip through the parser's suffix
    /// stripping without losing what makes it identifiable.
    func testDerivedNameSurvivesTheParsersSuffixStripping() throws {
        let name = DeriveCoordinator.derivedName(
            forJPG: URL(fileURLWithPath: "/photos/shot.JPG"), size: 33
        )
        let url = tempDirectory.appendingPathComponent("\(name).cube")
        try CubeLUT.write(cube: [SIMD3<Float>](repeating: .zero, count: 8), size: 2, title: name, to: url)

        let parsed = try CubeLUT(url: url)
        XCTAssertEqual(parsed.name, "shot_recipe", "the _33_Rec709 suffix is stripped for display")
    }

    // MARK: - Sheet lifecycle

    func testPresentAndDismissTogglesTheSheet() {
        let coordinator = DeriveCoordinator()
        XCTAssertFalse(coordinator.isSheetPresented)

        coordinator.present()
        XCTAssertTrue(coordinator.isSheetPresented)

        coordinator.dismiss()
        XCTAssertFalse(coordinator.isSheetPresented)
    }

    /// A finished result outlives the sheet on purpose: the user may reopen it
    /// to read the report or save the LUT.
    func testDismissKeepsAFinishedResult() throws {
        let coordinator = DeriveCoordinator()
        _ = try installScratchResult(on: coordinator)

        coordinator.present()
        coordinator.dismiss()

        XCTAssertNotNil(coordinator.derivedLUT, "closing the sheet must not discard a finished derive")
    }

    func testDismissWithoutAnActiveDeriveDoesNotEmitCancelledStatus() {
        let coordinator = DeriveCoordinator()
        var statuses: [String] = []
        coordinator.onStatus = { statuses.append($0) }

        coordinator.present()
        coordinator.dismiss()

        XCTAssertFalse(statuses.contains("Derive cancelled"),
                       "closing an idle sheet is not a cancellation")
    }

    // MARK: - Saving

    func testPerformSaveCopiesTheScratchCube() throws {
        let coordinator = DeriveCoordinator()
        _ = try installScratchResult(on: coordinator)

        let destination = tempDirectory.appendingPathComponent("Saved.cube")
        try coordinator.performSave(to: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        // And what landed is a real, parseable LUT — not a truncated copy.
        let parsed = try CubeLUT(url: destination)
        XCTAssertEqual(parsed.size, 2)
        XCTAssertTrue(parsed.tableFloats.allSatisfy { $0.isFinite })
    }

    func testPerformSaveReplacesAnExistingFile() throws {
        let coordinator = DeriveCoordinator()
        _ = try installScratchResult(on: coordinator)

        let destination = tempDirectory.appendingPathComponent("Saved.cube")
        try Data("stale contents".utf8).write(to: destination)

        try coordinator.performSave(to: destination)

        let contents = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertFalse(contents.contains("stale"), "an existing file should be replaced, not appended to")
        XCTAssertNoThrow(try CubeLUT(url: destination))
    }

    func testPerformSaveThrowsWhenThereIsNothingToSave() {
        let coordinator = DeriveCoordinator()
        XCTAssertThrowsError(
            try coordinator.performSave(to: tempDirectory.appendingPathComponent("x.cube"))
        ) { error in
            XCTAssertEqual(error as? DeriveCoordinator.SaveError, .nothingToSave)
        }
    }

    func testSavedCubeIsIndependentOfTheScratchFile() throws {
        let coordinator = DeriveCoordinator()
        let scratch = try installScratchResult(on: coordinator)

        let destination = tempDirectory.appendingPathComponent("Keeper.cube")
        try coordinator.performSave(to: destination)

        // Losing the temp file must not affect what the user saved.
        try FileManager.default.removeItem(at: scratch)
        XCTAssertNoThrow(try CubeLUT(url: destination))
    }

    func testSaveBracketsAtomicWriteAndReturnsCatalogAdoptionResult() throws {
        let coordinator = DeriveCoordinator()
        _ = try installScratchResult(on: coordinator)
        let destination = tempDirectory.appendingPathComponent("Transactional.cube")
        var events: [String] = []
        coordinator.onWillSave = { url, transientID, fingerprint in
            XCTAssertEqual(url, destination)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            XCTAssertEqual(transientID, coordinator.derivedLUT?.lutID)
            XCTAssertFalse(fingerprint.isEmpty)
            events.append("marker")
            return true
        }
        coordinator.onSaved = { url in
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            events.append("adopt")
            return false
        }

        let adopted = try coordinator.save(to: destination)

        XCTAssertFalse(adopted)
        XCTAssertEqual(events, ["marker", "adopt"])
    }

    func testAtomicWriteFailureCancelsRecoveryMarker() throws {
        let coordinator = DeriveCoordinator()
        _ = try installScratchResult(on: coordinator)
        let destination = tempDirectory.appendingPathComponent("is-a-directory")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var cancelled: URL?
        coordinator.onWillSave = { _, _, _ in true }
        coordinator.onSaveFailed = { cancelled = $0 }

        XCTAssertThrowsError(try coordinator.save(to: destination))
        XCTAssertEqual(cancelled, destination)
    }

    // MARK: - Error reporting

    func testDeriveReportsAFailureThroughOnError() async throws {
        let coordinator = DeriveCoordinator()
        var errors: [String] = []
        coordinator.onError = { errors.append($0) }
        coordinator.onDerived = { _ in XCTFail("should not have produced a LUT") }

        // Neither file is a decodable RAW/JPG pair.
        let missing = tempDirectory.appendingPathComponent("nope.dng")
        let jpg = try Fixtures.writeJPEG(width: 16, height: 16, orientation: 1, named: "a.jpg", in: tempDirectory)
        coordinator.derive(rawURL: missing, jpgURL: jpg)

        let deadline = Date().addingTimeInterval(5)
        while coordinator.isDeriving {
            if Date() > deadline { return XCTFail("derive did not finish") }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(errors.count, 1, "a failed derive must surface")
        XCTAssertTrue(errors[0].hasPrefix("Derive failed:"), errors[0])
        XCTAssertEqual(coordinator.progress, 0, "a failed derive should reset progress")
        XCTAssertNil(coordinator.derivedLUT)
    }

    func testDeriveIgnoresASecondRequestWhileRunning() async throws {
        let coordinator = DeriveCoordinator()
        let jpg = try Fixtures.writeJPEG(width: 16, height: 16, orientation: 1, named: "a.jpg", in: tempDirectory)
        let missing = tempDirectory.appendingPathComponent("nope.dng")

        var errorCount = 0
        coordinator.onError = { _ in errorCount += 1 }

        coordinator.derive(rawURL: missing, jpgURL: jpg)
        coordinator.derive(rawURL: missing, jpgURL: jpg)   // must be a no-op

        let deadline = Date().addingTimeInterval(5)
        while coordinator.isDeriving {
            if Date() > deadline { return XCTFail("derive did not finish") }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(errorCount, 1, "the second request should have been ignored, not queued")
    }
}
