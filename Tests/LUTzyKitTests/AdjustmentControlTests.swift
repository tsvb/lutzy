import XCTest
@testable import LUTzyKit

/// Phase 2 Step 10b. Pure-value tests: no engine, no `CIContext`, no image, no RAW — so all of this
/// runs on CI, which has none of those.
final class AdjustmentControlTests: XCTestCase {

    /// Every slot's neutral node must actually be an identity node — the base a write is applied to,
    /// and the value a read falls through to. The per-control half of this claim needs `value(in:)`
    /// and so lives in Task 4's `testEveryControlsNeutralMatchesTheNodesIdentity`.
    func testEverySlotsNeutralNodeIsAnIdentityNode() {
        for slot in AdjustmentSlot.allCases {
            XCTAssertTrue(slot.neutralNode.isIdentity,
                          "\(slot)'s neutral node must be an identity node")
            XCTAssertEqual(slot.neutralNode.slot, slot, "\(slot)'s neutral node is the wrong case")
        }
    }

    /// 10a's `testEveryPerImageSeedLandsStrictlyInsideItsSliderRange`, adapted — with the one
    /// exception the probe turned up.
    ///
    /// `CIHighlightShadowAdjust.inputHighlightAmount` has a slider floor of **0.3** and its identity
    /// is **1**, the range *maximum*. That is the filter's own definition, not a mistake here: the
    /// Highlights slider travels in one direction only, downward, recovering highlights. Every other
    /// control's neutral sits strictly inside its range, and this test says so control by control so
    /// that a second boundary case has to be added here deliberately.
    func testEveryNeutralSitsInsideItsRangeExceptHighlights() {
        for control in AdjustmentControl.allCases {
            XCTAssertTrue(
                control.range.contains(control.neutral),
                "\(control)'s neutral \(control.neutral) is outside its range \(control.range)"
            )
            if control == .highlights {
                XCTAssertEqual(control.neutral, control.range.upperBound,
                               "highlights' identity is documented to sit at the range maximum")
            } else {
                XCTAssertGreaterThan(control.neutral, control.range.lowerBound, "\(control)")
                XCTAssertLessThan(control.neutral, control.range.upperBound, "\(control)")
            }
        }
    }

    /// The nine controls are the five nodes' parameters, with none missed and none invented.
    func testEverySlotsControlsCoverItExactlyOnce() {
        XCTAssertEqual(AdjustmentControl.allCases.count, 9)
        let fromSlots = AdjustmentSlot.allCases.flatMap(\.controls)
        XCTAssertEqual(fromSlots, AdjustmentControl.allCases,
                       "slot order × within-slot order must equal declaration order")
    }

    /// Declaration order is layout order is canonical pipeline order — the order
    /// `RenderPipeline.applyAdjustments` folds. Pinned, because nothing else would notice it moving.
    func testSlotOrderMatchesTheNodeDeclarationOrder() {
        XCTAssertEqual(AdjustmentNode.neutralExposure.slot, .exposure)
        XCTAssertEqual(AdjustmentNode.neutralColorControls.slot, .colorControls)
        XCTAssertEqual(AdjustmentNode.neutralHighlightShadow.slot, .highlightShadow)
        XCTAssertEqual(AdjustmentNode.neutralTemperatureTint.slot, .temperatureTint)
        XCTAssertEqual(AdjustmentNode.neutralVibrance.slot, .vibrance)
        XCTAssertEqual(AdjustmentSlot.allCases.map(\.rawValue), [0, 1, 2, 3, 4])
    }

    /// Every title is human-facing and none is a `CIFilter` name.
    func testTitlesAreSetAndNotFilterNames() {
        for control in AdjustmentControl.allCases {
            XCTAssertFalse(control.title.isEmpty, "\(control) has no title")
            XCTAssertFalse(control.title.hasPrefix("CI"), "\(control)'s title is a filter name")
        }
    }

    /// The panel's two sections: exact membership, and — since `AdjustInspectorView` builds each
    /// section as `AdjustmentControl.allCases.filter { $0.group == … }` — every control belongs to
    /// exactly one group, and filtering by group preserves `allCases`' own relative order within
    /// it. The panel itself lists the Light section before the Color section (two `Section`s in
    /// that order), independent of the enum's declaration order.
    func testGroupMembershipAndPanelOrder() {
        let light: Set<AdjustmentControl> = [.exposure, .brightness, .contrast, .highlights, .shadows]
        let color: Set<AdjustmentControl> = [.saturation, .vibrance, .temperature, .tint]
        XCTAssertEqual(light.union(color), Set(AdjustmentControl.allCases),
                       "every control must belong to exactly one group")
        XCTAssertEqual(light.intersection(color), [], "no control may belong to both groups")

        for control in AdjustmentControl.allCases {
            let expected: AdjustmentGroup = light.contains(control) ? .light : .color
            XCTAssertEqual(control.group, expected, "\(control)")
        }

        // Filtering by group must not reorder the rows within it.
        let lightRows = AdjustmentControl.allCases.filter { $0.group == .light }
        let colorRows = AdjustmentControl.allCases.filter { $0.group == .color }
        XCTAssertEqual(Set(lightRows), light)
        XCTAssertEqual(Set(colorRows), color)
        XCTAssertEqual(lightRows, AdjustmentControl.allCases.filter(light.contains),
                       "the Light section must keep allCases' own relative order")
        XCTAssertEqual(colorRows, AdjustmentControl.allCases.filter(color.contains),
                       "the Color section must keep allCases' own relative order")
    }

    /// Temperature alone carries a unit; every other row is a plain number.
    func testOnlyTemperatureHasAUnit() {
        for control in AdjustmentControl.allCases {
            if control == .temperature {
                XCTAssertEqual(control.unit, "K")
            } else {
                XCTAssertNil(control.unit, "\(control)")
            }
        }
    }
}

// MARK: - The sparse contract

extension AdjustmentControlTests {

    /// Every control's neutral must be the value `AdjustmentNode.isIdentity` already names.
    ///
    /// Looped rather than spelled out nine times, so a tenth control cannot ship with a neutral that
    /// silently disagrees with the model — which would show a slider parked away from where the
    /// picture actually is, the same defect 10a's white-balance seed was added to prevent.
    func testEveryControlsNeutralMatchesTheNodesIdentity() {
        for slot in AdjustmentSlot.allCases {
            for control in slot.controls {
                XCTAssertEqual(
                    control.value(in: [slot.neutralNode]), control.neutral, accuracy: 1e-12,
                    "\(control)'s neutral disagrees with its node's identity value"
                )
            }
        }
    }

    /// Reading a control whose node is absent returns its neutral. This is what lets the document
    /// stay empty until the user actually touches something — the same "reading never writes"
    /// property `developBinding(for:)` has, and for the same reason: seeding every field when the
    /// panel opened would silently make every document non-neutral.
    func testReadingAnAbsentNodeReturnsNeutral() {
        for control in AdjustmentControl.allCases {
            XCTAssertEqual(control.value(in: []), control.neutral, accuracy: 1e-12, "\(control)")
        }
    }

    /// Writing a non-neutral value into an empty document creates exactly one node.
    func testWritingCreatesExactlyOneNode() {
        let result = AdjustmentControl.contrast.setting(1.4, in: [])
        XCTAssertEqual(result, [.colorControls(brightness: 0, contrast: 1.4, saturation: 1)])
    }

    /// Round-trip: what you write is what you read, for every control.
    func testEveryControlRoundTrips() {
        for control in AdjustmentControl.allCases {
            // A value that is inside the range and is definitely not the neutral.
            let midpoint = (control.range.lowerBound + control.range.upperBound) / 2
            let value = midpoint == control.neutral
                ? (midpoint + control.range.upperBound) / 2
                : midpoint
            XCTAssertNotEqual(value, control.neutral, "\(control): test value must not be neutral")

            let written = control.setting(value, in: [])
            XCTAssertEqual(control.value(in: written), value, accuracy: 1e-12, "\(control)")
        }
    }

    /// Writing one parameter must not disturb its siblings in the same node.
    func testWritingOneParameterPreservesItsSiblings() {
        var adjustments = AdjustmentControl.contrast.setting(1.4, in: [])
        adjustments = AdjustmentControl.saturation.setting(0.5, in: adjustments)

        XCTAssertEqual(AdjustmentControl.contrast.value(in: adjustments), 1.4, accuracy: 1e-12)
        XCTAssertEqual(AdjustmentControl.saturation.value(in: adjustments), 0.5, accuracy: 1e-12)
        XCTAssertEqual(AdjustmentControl.brightness.value(in: adjustments), 0, accuracy: 1e-12)
        XCTAssertEqual(adjustments.count, 1, "all three share one colorControls node")
    }

    /// Returning the last non-neutral parameter of a node to its neutral removes the node entirely.
    /// This is what keeps `EditDocument() == []` true after an edit is undone by hand, which §5's
    /// "empty document is identity" invariant and `originalForComparison` both rest on.
    func testReturningToNeutralRemovesTheNode() {
        var adjustments = AdjustmentControl.contrast.setting(1.4, in: [])
        XCTAssertEqual(adjustments.count, 1)

        adjustments = AdjustmentControl.contrast.setting(AdjustmentControl.contrast.neutral, in: adjustments)
        XCTAssertEqual(adjustments, [], "a node at its identity must not linger in the document")
    }

    /// A node whose siblings are still non-neutral must survive one parameter going back to neutral.
    func testReturningOneParameterToNeutralKeepsANodeItsSiblingsStillNeed() {
        var adjustments = AdjustmentControl.contrast.setting(1.4, in: [])
        adjustments = AdjustmentControl.saturation.setting(0.5, in: adjustments)
        adjustments = AdjustmentControl.contrast.setting(1, in: adjustments)

        XCTAssertEqual(adjustments, [.colorControls(brightness: 0, contrast: 1, saturation: 0.5)])
    }

    /// **Inserted at the canonical index, not appended.** Order is meaningful to the render —
    /// `AdjustmentNode`'s doc comment is explicit that exposure-then-colorControls is not the same
    /// picture as the reverse — so writing the rows out of order must not produce a different graph
    /// from writing them in order.
    func testNodesLandInCanonicalOrderWhateverOrderTheyAreWrittenIn() {
        var backwards: [AdjustmentNode] = []
        backwards = AdjustmentControl.vibrance.setting(0.3, in: backwards)
        backwards = AdjustmentControl.temperature.setting(5000, in: backwards)
        backwards = AdjustmentControl.shadows.setting(0.2, in: backwards)
        backwards = AdjustmentControl.saturation.setting(1.2, in: backwards)
        backwards = AdjustmentControl.exposure.setting(0.5, in: backwards)

        XCTAssertEqual(backwards.map(\.slot), [.exposure, .colorControls, .highlightShadow,
                                               .temperatureTint, .vibrance])

        var forwards: [AdjustmentNode] = []
        forwards = AdjustmentControl.exposure.setting(0.5, in: forwards)
        forwards = AdjustmentControl.saturation.setting(1.2, in: forwards)
        forwards = AdjustmentControl.shadows.setting(0.2, in: forwards)
        forwards = AdjustmentControl.temperature.setting(5000, in: forwards)
        forwards = AdjustmentControl.vibrance.setting(0.3, in: forwards)

        XCTAssertEqual(backwards, forwards, "write order must not change the resulting graph")
    }

    /// No slot may ever appear twice. The UI is one-of-each even though the model permits stacking.
    func testNoSlotEverAppearsTwice() {
        var adjustments: [AdjustmentNode] = []
        for control in AdjustmentControl.allCases {
            let value = control == .highlights ? 0.5 : control.range.upperBound
            adjustments = control.setting(value, in: adjustments)
        }
        let slots = adjustments.map(\.slot)
        XCTAssertEqual(slots.count, Set(slots).count, "a slot appeared twice: \(slots)")
        XCTAssertEqual(slots, AdjustmentSlot.allCases, "all five slots, once each, in order")
    }
}

// MARK: - The temperature mapping

extension AdjustmentControlTests {

    /// The map is its own inverse, which is what lets one function serve both directions of the
    /// binding. A non-involutive map would need two functions that could drift apart.
    func testTheSliderMapIsItsOwnInverse() {
        for control in AdjustmentControl.allCases {
            for value in [control.range.lowerBound, control.neutral, control.range.upperBound] {
                XCTAssertEqual(control.sliderMapped(control.sliderMapped(value)), value,
                               accuracy: 1e-9, "\(control) at \(value)")
            }
        }
    }

    /// Only temperature maps. Everything else is the identity, and stays that way.
    func testOnlyTemperatureIsMapped() {
        for control in AdjustmentControl.allCases where control != .temperature {
            let midpoint = (control.range.lowerBound + control.range.upperBound) / 2
            XCTAssertEqual(control.sliderMapped(midpoint), midpoint, accuracy: 1e-12, "\(control)")
        }
    }

    /// **The reason the range is 2000…11000 and not Develop's 2000…50000.** The reflection must land
    /// back inside the range at both ends, or the slider has a dead zone at one end and demands a
    /// negative colour temperature at the other. Reflecting 2000…50000 about 6500 would ask
    /// `CITemperatureAndTint` for −37000 K.
    func testTheTemperatureRangeIsClosedUnderTheReflection() {
        let range = AdjustmentControl.temperature.range
        for value in [range.lowerBound, range.upperBound] {
            XCTAssertTrue(range.contains(AdjustmentControl.temperature.sliderMapped(value)),
                          "\(value) K reflects to \(AdjustmentControl.temperature.sliderMapped(value)) K, "
                          + "outside \(range)")
        }
    }

    /// Neutral is the fixed point, so identity survives the map — a panel at its defaults must still
    /// produce an empty adjustments array.
    func testNeutralIsTheFixedPointOfTheMap() {
        XCTAssertEqual(AdjustmentControl.temperature.sliderMapped(6500), 6500, accuracy: 1e-12)
    }

    /// Dragging the slider **right** must warm the picture, matching the Develop tab's white-balance
    /// slider and every other photo application. Since the node's own Kelvin cools as it rises
    /// (`PHASE2_SPEC.md` §8.7, `testRaisingKelvinCoolsTheImage`), a higher slider value has to reach
    /// the node as a *lower* stored temperature.
    func testDraggingRightWarmsByStoringALowerNodeTemperature() {
        let cool = AdjustmentControl.temperature.sliderMapped(3000)
        let warm = AdjustmentControl.temperature.sliderMapped(10000)
        XCTAssertLessThan(warm, cool,
                          "a higher slider reading must store a lower node temperature, because the "
                          + "node's Kelvin runs backwards — see PHASE2_SPEC.md §8.7")
    }
}
