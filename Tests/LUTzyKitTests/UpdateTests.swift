import XCTest
@testable import LUTzyKit

/// The updater without a network or a bundle: version arithmetic, feed decoding, the coordinator's
/// two manners (quiet automatic check, talkative manual one), and the on-disk swap. The signature
/// check and the real download are not staged here — they need a Developer ID-signed bundle, which
/// `swift test` is not.
@MainActor
final class UpdateTests: TempDirectoryTestCase {

    // MARK: - AppVersion

    func testVersionParsesWithAndWithoutTheTagPrefix() {
        XCTAssertEqual(AppVersion("v0.1.0"), AppVersion(0, 1, 0))
        XCTAssertEqual(AppVersion("0.10.2"), AppVersion(0, 10, 2))
        XCTAssertEqual(AppVersion("1.2"), AppVersion(1, 2, 0), "a missing component reads as zero")
        XCTAssertNil(AppVersion("v0.1.0-beta.1"), "a pre-release suffix is not guessed at")
        XCTAssertNil(AppVersion("1.2.3.4"))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion(""))
    }

    func testVersionOrderIsNumericNotLexical() {
        XCTAssertLessThan(AppVersion(0, 9, 0), AppVersion(0, 10, 0))
        XCTAssertLessThan(AppVersion(0, 1, 9), AppVersion(0, 2, 0))
        XCTAssertLessThan(AppVersion(1, 0, 0), AppVersion(1, 0, 1))
        XCTAssertEqual(AppVersion(1, 0, 0).description, "1.0.0")
    }

    // MARK: - ReleaseFeed

    private let feedJSON = """
    {
      "tag_name": "v0.2.0",
      "name": "LUTzy 0.2.0",
      "body": "## Highlights\\n\\n- Drops from **Photos**",
      "html_url": "https://github.com/tsvb/lutzy/releases/tag/v0.2.0",
      "assets": [
        {"name": "LUTzy-0.2.0.dmg", "browser_download_url": "https://github.com/tsvb/lutzy/releases/download/v0.2.0/LUTzy-0.2.0.dmg", "size": 1779807, "content_type": "application/x-apple-diskimage"},
        {"name": "checksums.txt", "browser_download_url": "https://example.com/checksums.txt", "size": 12}
      ]
    }
    """

    func testFeedDecodesTheReleaseAndFindsTheDiskImage() throws {
        let release = try ReleaseFeed.parse(Data(feedJSON.utf8))
        XCTAssertEqual(release.version, AppVersion(0, 2, 0))
        XCTAssertEqual(release.title, "LUTzy 0.2.0")
        XCTAssertEqual(release.diskImageURL?.lastPathComponent, "LUTzy-0.2.0.dmg")
        XCTAssertEqual(release.diskImageSize, 1_779_807)
        XCTAssertTrue(release.notes.contains("Photos"))
    }

    func testFeedWithoutADiskImageStillReports() throws {
        let json = #"{"tag_name": "v0.3.0", "html_url": "https://example.com/r", "assets": []}"#
        let release = try ReleaseFeed.parse(Data(json.utf8))
        XCTAssertNil(release.diskImageURL)
        XCTAssertEqual(release.title, "LUTzy 0.3.0", "a missing name falls back to the version")
    }

    func testFeedRejectsATagThatIsNotAVersion() {
        let json = #"{"tag_name": "nightly", "html_url": "https://example.com/r"}"#
        XCTAssertThrowsError(try ReleaseFeed.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? ReleaseFeed.FeedError, .unusableTag("nightly"))
        }
    }

    // MARK: - UpdateCoordinator

    nonisolated private static func makeRelease(_ version: String, dmg: Bool = true) -> Release {
        Release(
            version: AppVersion(version)!, title: "LUTzy \(version)", notes: "",
            pageURL: URL(string: "https://example.com/r")!,
            diskImageURL: dmg ? URL(string: "https://example.com/r.dmg") : nil, diskImageSize: nil
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "UpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func waitUntil(
        _ description: String, timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeCoordinator(
        current: String? = "0.1.0",
        defaults: UserDefaults? = nil,
        fetch: @escaping UpdateCoordinator.Fetch,
        install: @escaping UpdateCoordinator.Install = { _ in throw CocoaError(.featureUnsupported) }
    ) -> UpdateCoordinator {
        UpdateCoordinator(
            currentVersion: current.flatMap(AppVersion.init), canInstallInPlace: true,
            defaults: defaults ?? makeDefaults(), fetch: fetch, install: install
        )
    }

    func testManualCheckShowsANewerRelease() async throws {
        let release = Self.makeRelease("0.2.0")
        let coordinator = makeCoordinator(fetch: { release })
        coordinator.checkNow()
        XCTAssertEqual(coordinator.phase, .checking)
        XCTAssertTrue(coordinator.isSheetPresented, "the sheet opens at once so the check is visible")
        try await waitUntil("the release") { coordinator.phase == .available(release) }
        XCTAssertNotNil(coordinator.lastCheck)
    }

    func testManualCheckReportsUpToDate() async throws {
        let coordinator = makeCoordinator(fetch: { Self.makeRelease("0.1.0") })
        coordinator.checkNow()
        try await waitUntil("up to date") { coordinator.phase == .upToDate }
    }

    func testManualCheckReportsAFailure() async throws {
        let coordinator = makeCoordinator(fetch: { throw ReleaseFeed.FeedError.badStatus(503) })
        coordinator.checkNow()
        try await waitUntil("the failure") {
            if case .failed(let message) = coordinator.phase { return message.contains("503") }
            return false
        }
    }

    func testAutomaticCheckIsQuietUnlessSomethingIsNewer() async throws {
        let coordinator = makeCoordinator(fetch: { Self.makeRelease("0.1.0") })
        XCTAssertTrue(coordinator.isAutomaticCheckDue, "never checked, so due")
        coordinator.checkAutomaticallyIfDue()
        XCTAssertFalse(coordinator.isSheetPresented)
        try await waitUntil("the check to land") { coordinator.lastCheck != nil }
        XCTAssertNil(coordinator.phase)
        XCTAssertFalse(coordinator.isSheetPresented)
        XCTAssertFalse(coordinator.isAutomaticCheckDue, "just checked, so not due again")
    }

    func testAutomaticCheckShowsANewerReleaseAndSwallowsErrors() async throws {
        let release = Self.makeRelease("0.2.0")
        let found = makeCoordinator(fetch: { release })
        found.checkAutomaticallyIfDue()
        try await waitUntil("the release") { found.phase == .available(release) }
        XCTAssertTrue(found.isSheetPresented)

        let failing = makeCoordinator(fetch: { throw URLError(.notConnectedToInternet) })
        failing.checkAutomaticallyIfDue()
        try await waitUntil("the check to land") { failing.lastCheck != nil }
        XCTAssertNil(failing.phase, "an offline launch is not an alert")
        XCTAssertFalse(failing.isSheetPresented)
    }

    func testASkippedVersionStaysQuietAutomaticallyButNotManually() async throws {
        let release = Self.makeRelease("0.2.0")
        let defaults = makeDefaults()
        let coordinator = makeCoordinator(defaults: defaults, fetch: { release })
        coordinator.skip(release)
        XCTAssertEqual(coordinator.skippedVersion, release.version)

        coordinator.checkAutomaticallyIfDue()
        try await waitUntil("the check to land") { coordinator.lastCheck != nil }
        XCTAssertNil(coordinator.phase)

        coordinator.checkNow()
        try await waitUntil("the release") { coordinator.phase == .available(release) }
    }

    func testAutomaticCheckRespectsThePreferenceAndTheInterval() {
        let defaults = makeDefaults()
        let coordinator = makeCoordinator(defaults: defaults, fetch: { Self.makeRelease("0.2.0") })
        coordinator.checksAutomatically = false
        XCTAssertFalse(coordinator.isAutomaticCheckDue)
        coordinator.checksAutomatically = true
        coordinator.lastCheck = Date().addingTimeInterval(-60 * 60)
        XCTAssertFalse(coordinator.isAutomaticCheckDue, "an hour ago is too recent")
        coordinator.lastCheck = Date().addingTimeInterval(-UpdateCoordinator.automaticInterval - 1)
        XCTAssertTrue(coordinator.isAutomaticCheckDue)
    }

    func testAnUnversionedBuildNeverChecksAutomatically() {
        let coordinator = makeCoordinator(current: nil, fetch: { Self.makeRelease("0.2.0") })
        XCTAssertFalse(coordinator.isAutomaticCheckDue, "`swift run` has nothing to update")
        XCTAssertTrue(coordinator.isNewer(Self.makeRelease("0.0.1")), "but a manual check still shows what exists")
    }

    func testAFailedInstallLeavesTheMessageOnTheSheet() async throws {
        let release = Self.makeRelease("0.2.0")
        let coordinator = makeCoordinator(
            fetch: { release },
            install: { _ in throw UpdateInstaller.InstallError.signatureRejected("wrong team") }
        )
        coordinator.installAndRelaunch(release)
        XCTAssertEqual(coordinator.phase, .downloading(release))
        try await waitUntil("the failure") {
            if case .failed(let message) = coordinator.phase { return message.contains("wrong team") }
            return false
        }
    }

    // MARK: - UpdateInstaller.swap

    private func makeBundle(named name: String, marker: String) throws -> URL {
        let app = tempDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try marker.write(to: app.appendingPathComponent("Contents/marker"), atomically: true, encoding: .utf8)
        return app
    }

    func testSwapPutsTheNewBundleInPlaceAndLeavesNoDebris() throws {
        let current = try makeBundle(named: "LUTzy.app", marker: "old")
        let image = tempDirectory.appendingPathComponent("image", isDirectory: true)
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: true)
        let incoming = image.appendingPathComponent("LUTzy.app")
        try FileManager.default.createDirectory(
            at: incoming.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try "new".write(to: incoming.appendingPathComponent("Contents/marker"), atomically: true, encoding: .utf8)

        try UpdateInstaller.swap(newApp: incoming, into: current)

        XCTAssertEqual(try String(contentsOf: current.appendingPathComponent("Contents/marker"), encoding: .utf8), "new")
        XCTAssertTrue(FileManager.default.fileExists(atPath: incoming.path), "the mounted copy is untouched")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
            .filter { $0.hasPrefix(".LUTzy-") }
        XCTAssertTrue(leftovers.isEmpty, "no staged or retired bundle should remain: \(leftovers)")
    }

    func testSwapRefusesAReadOnlyDestination() throws {
        let folder = tempDirectory.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let current = folder.appendingPathComponent("LUTzy.app")
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        let incoming = try makeBundle(named: "Incoming.app", marker: "new")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        XCTAssertThrowsError(try UpdateInstaller.swap(newApp: incoming, into: current)) { error in
            guard case UpdateInstaller.InstallError.destinationNotWritable = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }
}
