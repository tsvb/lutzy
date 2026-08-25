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
}
