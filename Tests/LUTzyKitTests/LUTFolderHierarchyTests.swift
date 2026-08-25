import XCTest
@testable import LUTzyKit

final class LUTFolderHierarchyTests: XCTestCase {
    func testParentFolderRollsUpEveryDescendantCount() throws {
        let tree = LUTFolderHierarchy.tree(from: [
            "Sony": 2,
            "Sony/VENICE": 3,
            "Sony/VENICE/Creative": 4,
            "Panasonic": 5,
        ])

        let sony = try XCTUnwrap(tree.first { $0.path == "Sony" })
        let venice = try XCTUnwrap(sony.children.first { $0.path == "Sony/VENICE" })

        XCTAssertEqual(sony.count, 9)
        XCTAssertEqual(venice.count, 7)
        XCTAssertEqual(venice.children.map(\.path), ["Sony/VENICE/Creative"])
    }

    func testFolderMembershipUsesPathBoundaryRatherThanLoosePrefix() {
        XCTAssertTrue(LUTFolderHierarchy.contains(categoryPath: "Sony", in: "Sony"))
        XCTAssertTrue(LUTFolderHierarchy.contains(categoryPath: "Sony/VENICE", in: "Sony"))
        XCTAssertFalse(LUTFolderHierarchy.contains(categoryPath: "Sony Pictures", in: "Sony"))
        XCTAssertFalse(LUTFolderHierarchy.contains(categoryPath: "Panasonic/S1H", in: "Sony"))
        XCTAssertTrue(LUTFolderHierarchy.contains(categoryPath: "Panasonic/S1H", in: nil))
    }

    func testTreePreservesEveryComponentOfADeepFolderPath() throws {
        let components = (1...12).map { "Level \($0)" }
        let path = components.joined(separator: "/")
        var candidates = LUTFolderHierarchy.tree(from: [path: 3])

        for (index, component) in components.enumerated() {
            let node = try XCTUnwrap(candidates.first)
            XCTAssertEqual(node.name, component)
            XCTAssertEqual(node.path, components.prefix(index + 1).joined(separator: "/"))
            XCTAssertEqual(node.count, 3)
            XCTAssertEqual(candidates.count, 1)
            candidates = node.children
        }

        XCTAssertTrue(candidates.isEmpty)
    }
}
