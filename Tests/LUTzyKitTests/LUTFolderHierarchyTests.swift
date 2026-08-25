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
}
