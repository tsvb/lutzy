import XCTest
@testable import LUTzyKit

@MainActor
final class MediaLibraryTests: TempDirectoryTestCase {
    private var manifestURL: URL {
        tempDirectory.appendingPathComponent("media-manifest.json")
    }

    private var managedRoot: URL {
        tempDirectory.appendingPathComponent("Managed", isDirectory: true)
    }

    func testMigratesEveryLegacyProjectWithCollidingNestedNamesIdempotently() throws {
        let projects = ProjectStore(root: tempDirectory.appendingPathComponent("Projects"))
        let alpha = projects.create(named: "Alpha")
        let beta = projects.create(named: "Beta")
        for project in [alpha, beta] {
            let nested = projects.imagesFolder(for: project)
                .appendingPathComponent("Shoot/Day 1", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data(project.name.utf8).write(to: nested.appendingPathComponent("frame.png"))
        }

        let media = MediaLibrary(root: managedRoot, manifestURL: manifestURL)
        media.migrateLegacyProjects(projects)

        XCTAssertEqual(media.records.count, 2)
        XCTAssertEqual(Set(media.records.map(\.id)).count, 2)
        XCTAssertEqual(Set(media.records.map(\.logicalPath)), ["Shoot/Day 1/frame.png"])
        XCTAssertEqual(Set(media.records.compactMap(\.legacySourceName)), ["Alpha", "Beta"])
        XCTAssertTrue(media.records.allSatisfy { $0.locator.hasPrefix(managedRoot.path) == false })
        XCTAssertTrue(media.records.allSatisfy { media.disambiguator(for: $0) != nil })

        let firstIDs = Set(media.records.map(\.id))
        media.migrateLegacyProjects(projects)
        XCTAssertEqual(media.records.count, 2)
        XCTAssertEqual(Set(media.records.map(\.id)), firstIDs)

        let relaunched = MediaLibrary(root: managedRoot, manifestURL: manifestURL)
        XCTAssertEqual(Set(relaunched.records.map(\.id)), firstIDs)
    }

    func testNestedMixedImportPreservesHierarchyAndDeduplicatesByContent() async throws {
        let source = tempDirectory.appendingPathComponent("Shoot", isDirectory: true)
        let nested = source.appendingPathComponent("Day 1/Stills", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let imageBytes = Data([0x89, 0x50, 0x4e, 0x47, 1, 2, 3])
        try imageBytes.write(to: nested.appendingPathComponent("hero.png"))
        try imageBytes.write(to: nested.appendingPathComponent("hero-copy.png"))
        try Data([0, 0, 0, 20, 0x66, 0x74, 0x79, 0x70]).write(
            to: source.appendingPathComponent("clip.mov")
        )

        let media = MediaLibrary(root: managedRoot, manifestURL: manifestURL)
        let result = await media.importMedia(from: [source])

        XCTAssertEqual(result.imported, 2)
        XCTAssertEqual(result.duplicates, 1)
        XCTAssertEqual(result.failed, 0)
        XCTAssertTrue(media.records.contains { $0.kind == .image })
        XCTAssertTrue(media.records.contains { $0.kind == .video })
        XCTAssertTrue(media.records.contains { $0.logicalPath == "Shoot/Day 1/Stills/hero.png" })
        XCTAssertTrue(media.records.contains { $0.logicalPath == "Shoot/clip.mov" })
        XCTAssertTrue(media.records.allSatisfy { $0.locator.hasPrefix(managedRoot.path + "/") })

        let firstIDs = Set(media.records.map(\.id))
        let second = await media.importMedia(from: [source])
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.duplicates, 3)
        XCTAssertEqual(Set(media.records.map(\.id)), firstIDs)

        let relaunched = MediaLibrary(root: managedRoot, manifestURL: manifestURL)
        XCTAssertEqual(Set(relaunched.records.map(\.id)), firstIDs)
        XCTAssertEqual(Set(relaunched.records.map(\.logicalPath)), Set(media.records.map(\.logicalPath)))
    }

    func testPhotosDataUsesGlobalManifestAndSurvivesRelaunch() throws {
        let media = MediaLibrary(root: managedRoot, manifestURL: manifestURL)
        let png = try Fixtures.writeGradientPNG(
            width: 8, height: 8, named: "fixture.png", in: tempDirectory
        )
        let data = try Data(contentsOf: png)

        let result = media.importImageData([(name: "Photo 1", data: data)])
        XCTAssertEqual(result.imported, 1)
        let record = try XCTUnwrap(media.records.first)
        XCTAssertEqual(record.kind, .image)
        XCTAssertEqual(record.logicalFolder, "Photos")
        XCTAssertTrue(record.url.path.hasPrefix(managedRoot.path + "/"))

        let relaunched = MediaLibrary(root: managedRoot, manifestURL: manifestURL)
        XCTAssertEqual(relaunched.records.first?.id, record.id)
        XCTAssertEqual(relaunched.records.first?.logicalPath, record.logicalPath)
    }
}
