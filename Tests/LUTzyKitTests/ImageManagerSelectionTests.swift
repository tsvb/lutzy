import XCTest
@testable import LUTzyKit

final class ImageManagerSelectionTests: XCTestCase {
    private let ids = ["a", "b", "c", "d"]

    func testPlainSelectionReplacesTheCurrentSelection() {
        let result = ImageManagerSelection.selecting(
            "c", orderedIDs: ids, current: ["a", "b"], anchor: "a",
            toggling: false, extending: false
        )

        XCTAssertEqual(result.selection, ["c"])
        XCTAssertEqual(result.anchor, "c")
    }

    func testCommandSelectionTogglesOneImage() {
        let added = ImageManagerSelection.selecting(
            "c", orderedIDs: ids, current: ["a"], anchor: "a",
            toggling: true, extending: false
        )
        XCTAssertEqual(added.selection, ["a", "c"])
        XCTAssertEqual(added.anchor, "c")

        let removed = ImageManagerSelection.selecting(
            "a", orderedIDs: ids, current: added.selection, anchor: added.anchor,
            toggling: true, extending: false
        )
        XCTAssertEqual(removed.selection, ["c"])
    }

    func testShiftSelectionBuildsAContiguousRange() {
        let result = ImageManagerSelection.selecting(
            "d", orderedIDs: ids, current: ["b"], anchor: "b",
            toggling: false, extending: true
        )

        XCTAssertEqual(result.selection, ["b", "c", "d"])
        XCTAssertEqual(result.anchor, "b")
    }

    func testCommandShiftAddsARangeToTheSelection() {
        let result = ImageManagerSelection.selecting(
            "d", orderedIDs: ids, current: ["a"], anchor: "c",
            toggling: true, extending: true
        )

        XCTAssertEqual(result.selection, ["a", "c", "d"])
        XCTAssertEqual(result.anchor, "c")
    }

    func testMissingAnchorFallsBackToPlainSelection() {
        let result = ImageManagerSelection.selecting(
            "b", orderedIDs: ids, current: ["a"], anchor: "missing",
            toggling: false, extending: true
        )

        XCTAssertEqual(result.selection, ["b"])
        XCTAssertEqual(result.anchor, "b")
    }

    func testImagesAndLUTManagerHaveSeparateNavigationOwnership() {
        XCTAssertEqual(AppSection.images.label, "Images")
        XCTAssertEqual(AppSection.manager.label, "LUT Manager")
        XCTAssertEqual(AppSection.workspaceSections, [.viewer, .manager, .editor])
    }
}
