import XCTest
@testable import LUTzyKit

@MainActor
final class LUTCatalogTests: TempDirectoryTestCase {
    private func makeLibrary() -> LUTLibrary {
        let catalog = LUTCatalog(fileURL: tempDirectory.appendingPathComponent("catalog.json"))
        return LUTLibrary(catalog: catalog)
    }

    private func waitForScan(_ library: LUTLibrary, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while library.isScanning {
            if Date() > deadline { XCTFail("scan timed out"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testIdenticalFilesReceiveIndependentDurableRecords() async throws {
        let a = tempDirectory.appendingPathComponent("A")
        let b = tempDirectory.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let cube = Fixtures.identityCubeText(size: 2)
        try Fixtures.writeCube(cube, named: "Same.cube", in: a)
        try Fixtures.writeCube(cube, named: "Same.cube", in: b)

        let library = makeLibrary()
        library.scan(tempDirectory)
        try await waitForScan(library)

        XCTAssertEqual(library.allLUTs.count, 2)
        let ids = Set(library.allLUTs.map(\.lutID))
        XCTAssertEqual(ids.count, 2)
        XCTAssertTrue(ids.allSatisfy(\.isRecord))
    }

    func testRecordIdentityAndMetadataSurviveRescan() async throws {
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "Look.cube", in: tempDirectory)
        let library = makeLibrary()
        library.scan(tempDirectory)
        try await waitForScan(library)
        let first = try XCTUnwrap(library.allLUTs.first)
        library.catalog.addTag("低飽和", to: [first.lutID])
        library.catalog.setOrigin(.vendor("Panasonic"), for: [first.lutID])

        library.scan(tempDirectory)
        try await waitForScan(library)
        let rescanned = try XCTUnwrap(library.allLUTs.first)

        XCTAssertEqual(rescanned.lutID, first.lutID)
        XCTAssertEqual(library.catalog.typedTags(for: rescanned), ["低飽和"])
        XCTAssertEqual(library.catalog.origin(for: rescanned), .vendor("Panasonic"))
    }

    func testMeasuredTagExclusionIsPerRecordAndSurvivesRelaunch() throws {
        let firstURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "First.cube", in: tempDirectory
        )
        let secondURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Second.cube", in: tempDirectory
        )
        let catalogURL = tempDirectory.appendingPathComponent("tag-exclusions.json")
        let catalog = LUTCatalog(fileURL: catalogURL)
        let firstID = try XCTUnwrap(catalog.adoptSavedLUT(try CubeLUT(url: firstURL)))
        let secondID = try XCTUnwrap(catalog.adoptSavedLUT(try CubeLUT(url: secondURL)))

        catalog.removeTag("高對比", from: [firstID], hidingMeasuredFor: [firstID])
        catalog.removeTag("混合自動", from: [firstID, secondID], hidingMeasuredFor: [firstID])

        let relaunched = LUTCatalog(fileURL: catalogURL)
        XCTAssertEqual(relaunched.excludedMeasuredTags(for: firstID), ["混合自動", "高對比"])
        XCTAssertEqual(relaunched.excludedMeasuredTags(for: secondID), [])

        relaunched.addTag("高對比", to: [firstID])
        XCTAssertEqual(relaunched.excludedMeasuredTags(for: firstID), ["混合自動"])
        XCTAssertEqual(relaunched.record(for: firstID)?.typedTags, ["高對比"])
    }

    func testOneMissingAndTwoUnmatchedIdenticalFilesIsAmbiguousAsABatch() async throws {
        let original = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Original.cube", in: tempDirectory
        )
        let library = makeLibrary()
        library.scan(tempDirectory)
        try await waitForScan(library)
        let missingID = try XCTUnwrap(library.allLUTs.first?.lutID)
        library.catalog.addTag("keep-with-missing", to: [missingID])

        let moved = tempDirectory.appendingPathComponent("Moved")
        try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)
        let text = try String(contentsOf: original, encoding: .utf8)
        try FileManager.default.removeItem(at: original)
        try Fixtures.writeCube(text, named: "Copy 1.cube", in: moved)
        try Fixtures.writeCube(text, named: "Copy 2.cube", in: moved)

        library.scan(tempDirectory)
        try await waitForScan(library)

        XCTAssertEqual(library.allLUTs.count, 2)
        XCTAssertFalse(library.allLUTs.map(\.lutID).contains(missingID))
        XCTAssertEqual(Set(library.allLUTs.map(\.lutID)).count, 2)
        XCTAssertEqual(library.catalog.record(for: missingID)?.isAvailable, false)
        XCTAssertEqual(library.catalog.record(for: missingID)?.typedTags, ["keep-with-missing"])
    }

    func testCollectionsAreManyToManyMetadata() async throws {
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "One.cube", in: tempDirectory)
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 3), named: "Two.cube", in: tempDirectory)
        let library = makeLibrary()
        library.scan(tempDirectory)
        try await waitForScan(library)
        let ids = Set(library.allLUTs.map(\.lutID))
        let low = try XCTUnwrap(library.catalog.createCollection(named: "低飽和"))
        let travel = try XCTUnwrap(library.catalog.createCollection(named: "Travel"))

        library.catalog.setMembership(true, collectionID: low.id, recordIDs: ids)
        library.catalog.setMembership(true, collectionID: travel.id, recordIDs: [try XCTUnwrap(ids.first)])

        XCTAssertEqual(library.catalog.members(of: low.id), ids)
        XCTAssertEqual(library.catalog.members(of: travel.id).count, 1)
        for lut in library.allLUTs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: lut.url.path))
        }
    }

    func testOneMissingAndOneUnmatchedReconnectsTheSameRecord() async throws {
        let original = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Original.cube", in: tempDirectory
        )
        let library = makeLibrary()
        library.scan(tempDirectory)
        try await waitForScan(library)
        let originalID = try XCTUnwrap(library.allLUTs.first?.lutID)
        library.catalog.addTag("reconnect", to: [originalID])

        let movedFolder = tempDirectory.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.createDirectory(at: movedFolder, withIntermediateDirectories: true)
        let moved = movedFolder.appendingPathComponent("Renamed.cube")
        try FileManager.default.moveItem(at: original, to: moved)
        library.scan(tempDirectory)
        try await waitForScan(library)

        let reconnected = try XCTUnwrap(library.allLUTs.first)
        XCTAssertEqual(reconnected.lutID, originalID)
        XCTAssertEqual(library.catalog.typedTags(for: reconnected), ["reconnect"])
        XCTAssertEqual(library.catalog.record(for: originalID)?.locator, moved.resolvingSymlinksInPath().path)
    }

    func testCatalogLocatorUpdateAndCollectionMembershipSurviveRelaunch() throws {
        let file = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Look.cube", in: tempDirectory
        )
        let catalogURL = tempDirectory.appendingPathComponent("catalog-relaunch.json")
        let catalog = LUTCatalog(fileURL: catalogURL)
        let parsed = try CubeLUT(url: file)
        let id = try XCTUnwrap(catalog.adoptSavedLUT(parsed))
        let collection = try XCTUnwrap(catalog.createCollection(named: "低飽和"))
        catalog.setMembership(true, collectionID: collection.id, recordIDs: [id])
        catalog.setDisplayName("Soft Look", for: [id])
        catalog.setOrigin(.custom, for: [id])

        let moved = tempDirectory.appendingPathComponent("Renamed.cube")
        try FileManager.default.moveItem(at: file, to: moved)
        XCTAssertTrue(catalog.updateLocator(for: id, to: moved))

        let relaunched = LUTCatalog(fileURL: catalogURL)
        let loaded = try XCTUnwrap(relaunched.loadLUT(for: id))
        XCTAssertEqual(loaded.lutID, id)
        XCTAssertEqual(relaunched.members(of: collection.id), Set([id]))
        XCTAssertEqual(relaunched.effectiveName(for: loaded), "Soft Look")
        XCTAssertEqual(relaunched.origin(for: loaded), .custom)
    }

    func testKnownLocatorOverwriteKeepsMetadataAndRefreshesFingerprint() throws {
        let file = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Derived.cube", in: tempDirectory
        )
        let catalog = LUTCatalog(fileURL: tempDirectory.appendingPathComponent("overwrite.json"))
        let first = try CubeLUT(url: file)
        let id = try XCTUnwrap(catalog.adoptSavedLUT(first))
        catalog.addTag("keeper", to: [id])
        catalog.setStarred(true, for: [id])

        try Fixtures.writeCube(Fixtures.identityCubeText(size: 3), named: "Derived.cube", in: tempDirectory)
        let replacement = try CubeLUT(url: file)
        let adoptedID = try XCTUnwrap(catalog.adoptSavedLUT(replacement))

        XCTAssertEqual(adoptedID, id)
        XCTAssertNotEqual(replacement.contentHash, first.contentHash)
        XCTAssertEqual(catalog.record(for: id)?.fingerprint, replacement.contentHash)
        XCTAssertEqual(catalog.record(for: id)?.typedTags, ["keeper"])
        XCTAssertEqual(catalog.record(for: id)?.isStarred, true)
    }

    func testPendingDerivedSaveIsRecoveredOnCatalogRelaunch() throws {
        let manifest = tempDirectory.appendingPathComponent("recovery.json")
        let destination = tempDirectory.appendingPathComponent("Recovered.cube")
        let scratch = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Scratch.cube", in: tempDirectory
        )
        let serialized = try CubeLUT(url: scratch)
        let transientID = LUTID(raw: "derived://interrupted-save")
        let scopeBookmark = try tempDirectory.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
        )
        let first = LUTCatalog(fileURL: manifest)
        XCTAssertTrue(first.beginSaveRecovery(
            for: destination, replacing: transientID,
            expectedFingerprint: serialized.contentHash,
            bookmark: scopeBookmark,
            bookmarkRelativePath: destination.lastPathComponent
        ))
        try Fixtures.identityCubeText(size: 2).write(to: destination, atomically: true, encoding: .utf8)

        let relaunched = LUTCatalog(fileURL: manifest)
        let id = try XCTUnwrap(relaunched.recordID(for: destination))
        let resolved = try XCTUnwrap(relaunched.loadLUT(for: transientID))

        XCTAssertEqual(resolved.url.standardizedFileURL, destination.standardizedFileURL)
        XCTAssertTrue(id.isRecord)
        XCTAssertEqual(resolved.lutID, id, "the persisted derived:// session alias must adopt the recovered record")
    }

    func testRecoveryDoesNotAdoptAnUntouchedOverwriteDestination() throws {
        let manifest = tempDirectory.appendingPathComponent("stale-recovery.json")
        let destination = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Known.cube", in: tempDirectory
        )
        let replacement = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 3), named: "Replacement.cube", in: tempDirectory
        )
        let transientID = LUTID(raw: "derived://replacement-that-never-landed")
        let first = LUTCatalog(fileURL: manifest)
        XCTAssertTrue(first.beginSaveRecovery(
            for: destination, replacing: transientID,
            expectedFingerprint: try CubeLUT(url: replacement).contentHash
        ))

        let relaunched = LUTCatalog(fileURL: manifest)

        XCTAssertNil(relaunched.loadLUT(for: transientID))
        XCTAssertNil(relaunched.recordID(for: destination))
    }

    func testFailedFileWriteCanCancelPendingRecovery() throws {
        let manifest = tempDirectory.appendingPathComponent("cancel-recovery.json")
        let destination = tempDirectory.appendingPathComponent("Never Saved.cube")
        let first = LUTCatalog(fileURL: manifest)
        XCTAssertTrue(first.beginSaveRecovery(for: destination))
        first.cancelSaveRecovery(for: destination)
        try Fixtures.identityCubeText(size: 2).write(to: destination, atomically: true, encoding: .utf8)

        let relaunched = LUTCatalog(fileURL: manifest)
        XCTAssertNil(relaunched.recordID(for: destination))
    }

    func testPersistenceFailureDoesNotPublishNewRecord() throws {
        let file = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Derived.cube", in: tempDirectory
        )
        let blocker = tempDirectory.appendingPathComponent("not-a-directory")
        try Data("blocker".utf8).write(to: blocker)
        let catalog = LUTCatalog(fileURL: blocker.appendingPathComponent("catalog.json"))

        let result = catalog.adoptSavedLUT(try CubeLUT(url: file))

        XCTAssertNil(result)
        XCTAssertTrue(catalog.records.isEmpty)
    }

    func testExactLegacyPathReferenceMigratesButUnknownPathDoesNot() async throws {
        let file = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Legacy.cube", in: tempDirectory
        )
        let library = makeLibrary()
        library.scan(tempDirectory)
        try await waitForScan(library)
        let durableID = try XCTUnwrap(library.allLUTs.first?.lutID)

        XCTAssertEqual(library.migratedRecordID(for: LUTID(raw: file.path)), durableID)
        let missing = LUTID(raw: tempDirectory.appendingPathComponent("Missing.cube").path)
        XCTAssertEqual(library.migratedRecordID(for: missing), missing)
    }

    func testLegacyContentMetadataCopiesToEveryIdenticalRecord() async throws {
        let a = tempDirectory.appendingPathComponent("A", isDirectory: true)
        let b = tempDirectory.appendingPathComponent("B", isDirectory: true)
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let text = Fixtures.identityCubeText(size: 2)
        try Fixtures.writeCube(text, named: "Copy.cube", in: a)
        try Fixtures.writeCube(text, named: "Copy.cube", in: b)
        let library = makeLibrary()
        library.scan(tempDirectory)
        try await waitForScan(library)

        let legacy = LUTTagStore(fileURL: tempDirectory.appendingPathComponent("legacy-tags.json"))
        let representative = try XCTUnwrap(library.allLUTs.first)
        legacy.addTag("legacy-tag", to: representative)
        legacy.toggleFavourite(representative)
        library.catalog.migrateLegacyMetadata(for: library.allLUTs, from: legacy)

        XCTAssertEqual(library.allLUTs.count, 2)
        for lut in library.allLUTs {
            XCTAssertEqual(library.catalog.typedTags(for: lut), ["legacy-tag"])
            XCTAssertTrue(library.catalog.isStarred(lut))
        }
    }
}
