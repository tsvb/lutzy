import XCTest
import SwiftUI
@testable import LUTzyKit

/// The main window's plain-key shortcuts are a pure table, so the part that used to be checked by
/// hand — which key does what, and when it must stay out of the way — is asserted here. The focus
/// plumbing that delivers a press to the table is a SwiftUI view body, and this repo has no view
/// tests; that half is checked in the running app.
final class KeyCommandMapTests: XCTestCase {

    private func action(
        _ key: KeyEquivalent,
        _ phase: KeyPress.Phases = .down,
        modifiers: EventModifiers = [],
        collectionActive: Bool = true
    ) -> KeyAction? {
        KeyCommandMap.action(for: key, modifiers: modifiers, phase: phase, collectionActive: collectionActive)
    }

    func testCommandModifiedKeysAreLeftForTheMenuBar() {
        for key in KeyCommandMap.keys {
            XCTAssertNil(action(key, modifiers: .command), "⌘\(key.character) must reach the menu bar")
        }
    }

    func testArrowsCycleLUTsAndImages() {
        XCTAssertEqual(action(.upArrow), .previousLUT)
        XCTAssertEqual(action(.downArrow), .nextLUT)
        XCTAssertEqual(action(.leftArrow), .previousImage)
        XCTAssertEqual(action(.rightArrow), .nextImage)
        XCTAssertEqual(action("["), .previousImage)
        XCTAssertEqual(action("]"), .nextImage)
    }

    func testImageStepsAreIgnoredWithoutACollection() {
        XCTAssertNil(action(.leftArrow, collectionActive: false))
        XCTAssertNil(action(.rightArrow, collectionActive: false))
        XCTAssertNil(action("[", collectionActive: false))
        XCTAssertNil(action("]", collectionActive: false))
        XCTAssertEqual(action(.upArrow, collectionActive: false), .previousLUT,
                       "LUT cycling does not need a collection")
    }

    func testSpaceComparesWhileHeld() {
        XCTAssertEqual(action(.space, .down), .compareOriginal(true))
        XCTAssertEqual(action(.space, .up), .compareOriginal(false))
        XCTAssertNil(action(.space, .repeat), "holding Space keeps showing the original; nothing to redo")
    }

    func testVTogglesInEitherCase() {
        XCTAssertEqual(action("v"), .toggleSideBySide)
        XCTAssertEqual(action("V"), .toggleSideBySide)
        XCTAssertNil(action("v", .repeat), "a held V must not flap the layout")
        XCTAssertNil(action("v", .up))
    }

    func testRepeatsStepButReleasesDoNot() {
        XCTAssertEqual(action(.downArrow, .repeat), .nextLUT)
        XCTAssertEqual(action(.rightArrow, .repeat), .nextImage)
        XCTAssertNil(action(.downArrow, .up))
    }

    func testUnknownKeysPassThrough() {
        XCTAssertNil(action("x"))
        XCTAssertNil(action(.escape))
        XCTAssertNil(action(.return))
    }

    func testEverySubscribedKeyDoesSomethingInSomePhase() {
        for key in KeyCommandMap.keys {
            let anyPhase = [KeyPress.Phases.down, .repeat, .up].contains { action(key, $0) != nil }
            XCTAssertTrue(anyPhase, "\(key.character) is subscribed to but never mapped")
        }
    }
}
