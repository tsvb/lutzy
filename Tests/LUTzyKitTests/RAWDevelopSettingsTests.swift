import XCTest
import CoreImage
@testable import LUTzyKit

/// `RAWDevelopSettings` is the one Step 2 type with a foot in the framework: its whole job is to push
/// values onto a `CIRAWFilter` before `outputImage` is read.
///
/// Two things are worth proving. First that `.neutral` is genuinely nothing — the migration's promise
/// is that an untouched document renders byte-identically to today's `ImageDecoder.developRAWNeutral`,
/// which sets no properties at all. Second that the property set is the real one: an earlier draft of
/// the spec listed names (`isDustRemovalSupported`, `enableEDR`) that do not exist.
final class RAWDevelopSettingsTests: XCTestCase {

    // MARK: - Neutral

    /// `.neutral` has to be equal to a default-constructed value and to hold nothing, because `nil`
    /// is what stands for "leave the decoder alone". Several `CIRAWFilter` defaults vary per image,
    /// so there is no fixed number that could mean "untouched" — a numeric sentinel here would
    /// silently override a per-camera baseline.
    func testNeutralIsEmptyAndEqualsADefaultValue() {
        XCTAssertEqual(RAWDevelopSettings.neutral, RAWDevelopSettings())
        XCTAssertTrue(RAWDevelopSettings.neutral.isNeutral)
        XCTAssertTrue(RAWDevelopSettings().isNeutral)
        XCTAssertEqual(EditDocument().rawDevelop, .neutral)

        let neutral = RAWDevelopSettings.neutral
        XCTAssertNil(neutral.exposure)
        XCTAssertNil(neutral.baselineExposure)
        XCTAssertNil(neutral.shadowBias)
        XCTAssertNil(neutral.boostAmount)
        XCTAssertNil(neutral.boostShadowAmount)
        XCTAssertNil(neutral.neutralTemperature)
        XCTAssertNil(neutral.neutralTint)
        XCTAssertNil(neutral.sharpnessAmount)
        XCTAssertNil(neutral.contrastAmount)
        XCTAssertNil(neutral.detailAmount)
        XCTAssertNil(neutral.moireReductionAmount)
        XCTAssertNil(neutral.localToneMapAmount)
        XCTAssertNil(neutral.luminanceNoiseReductionAmount)
        XCTAssertNil(neutral.colorNoiseReductionAmount)
        XCTAssertNil(neutral.lensCorrectionEnabled)
        XCTAssertNil(neutral.gamutMappingEnabled)
        XCTAssertNil(neutral.extendedDynamicRangeAmount)
        XCTAssertNil(neutral.highlightRecoveryEnabled)
    }

    /// Every field has to break neutrality on its own — a knob that isn't compared is a knob whose
    /// change won't invalidate a cached render.
    func testAnySingleSettingBreaksNeutrality() throws {
        var mutations: [(String, RAWDevelopSettings)] = []
        func vary(_ name: String, _ mutate: (inout RAWDevelopSettings) -> Void) {
            var settings = RAWDevelopSettings.neutral
            mutate(&settings)
            mutations.append((name, settings))
        }

        vary("exposure") { $0.exposure = 1 }
        vary("baselineExposure") { $0.baselineExposure = 1 }
        vary("shadowBias") { $0.shadowBias = 1 }
        vary("boostAmount") { $0.boostAmount = 0 }
        vary("boostShadowAmount") { $0.boostShadowAmount = 0 }
        vary("neutralTemperature") { $0.neutralTemperature = 5000 }
        vary("neutralTint") { $0.neutralTint = 10 }
        vary("sharpnessAmount") { $0.sharpnessAmount = 0.5 }
        vary("contrastAmount") { $0.contrastAmount = 0.5 }
        vary("detailAmount") { $0.detailAmount = 1 }
        vary("moireReductionAmount") { $0.moireReductionAmount = 0.5 }
        vary("localToneMapAmount") { $0.localToneMapAmount = 0.5 }
        vary("luminanceNoiseReductionAmount") { $0.luminanceNoiseReductionAmount = 0.5 }
        vary("colorNoiseReductionAmount") { $0.colorNoiseReductionAmount = 0.5 }
        vary("lensCorrectionEnabled") { $0.lensCorrectionEnabled = true }
        vary("gamutMappingEnabled") { $0.gamutMappingEnabled = false }
        vary("extendedDynamicRangeAmount") { $0.extendedDynamicRangeAmount = 1 }
        vary("highlightRecoveryEnabled") { $0.highlightRecoveryEnabled = false }

        XCTAssertEqual(mutations.count, 18, "a new property needs a case here")
        for (name, settings) in mutations {
            XCTAssertFalse(settings.isNeutral, "\(name) should count as an edit")
            XCTAssertNotEqual(settings, .neutral, "\(name) should be part of equality")
        }
        // And no two of them collide, which would mean one field is being compared as another.
        let encoded = try mutations.map { try JSONEncoder().encode($0.1) }
        XCTAssertEqual(Set(encoded).count, 18)
    }

    func testSettingsRoundTripAndOmitNilFields() throws {
        let settings = RAWDevelopSettings(exposure: -1.25, neutralTint: 33, gamutMappingEnabled: false)
        let data = try JSONEncoder().encode(settings)

        XCTAssertEqual(try JSONDecoder().decode(RAWDevelopSettings.self, from: data), settings)

        // `nil` means "decoder default", so it should not be written at all — a document full of
        // explicit nulls is both larger and easy to misread as "set to zero".
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["exposure", "neutralTint", "gamutMappingEnabled"])

        XCTAssertEqual(try JSONDecoder().decode(RAWDevelopSettings.self, from: Data("{}".utf8)), .neutral)
    }

    // MARK: - Application to a real CIRAWFilter

    /// The knob names are checked by the compiler; what this checks is that they *do something* —
    /// that each one round-trips through a real `CIRAWFilter` built from a real RAW.
    ///
    /// Skipped wherever there is no RAW to hand, which includes CI. See `Fixtures.localRAWURL`.
    func testApplyPushesEverySupportedKnobOntoARealFilter() throws {
        guard let url = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW to develop; see Fixtures.localRAWURL")
        }

        let filter = try XCTUnwrap(CIRAWFilter(imageURL: url), "CIRAWFilter could not decode \(url.lastPathComponent)")

        let settings = RAWDevelopSettings(
            exposure: 0.5,
            baselineExposure: 0.25,
            shadowBias: -0.1,
            boostAmount: 0.75,
            boostShadowAmount: 1.5,
            neutralTemperature: 5200,
            neutralTint: 12,
            sharpnessAmount: 0.4,
            contrastAmount: 0.6,
            detailAmount: 1.5,
            moireReductionAmount: 0.2,
            localToneMapAmount: 0.3,
            luminanceNoiseReductionAmount: 0.7,
            colorNoiseReductionAmount: 0.8,
            // Both booleans are written as `false` on purpose. `CIRAWFilter` defaults them to
            // *true* for this file, so a test that set `true` and asserted `true` would pass just as
            // happily against an `apply(to:)` that skipped them entirely — which is exactly what a
            // mutation check caught it doing.
            lensCorrectionEnabled: false,
            gamutMappingEnabled: false,
            extendedDynamicRangeAmount: 1.0,
            highlightRecoveryEnabled: false
        )
        settings.apply(to: filter)

        XCTAssertEqual(filter.exposure, 0.5, accuracy: 0.0001)
        XCTAssertEqual(filter.baselineExposure, 0.25, accuracy: 0.0001)
        XCTAssertEqual(filter.shadowBias, -0.1, accuracy: 0.0001)
        XCTAssertEqual(filter.boostAmount, 0.75, accuracy: 0.0001)
        XCTAssertEqual(filter.boostShadowAmount, 1.5, accuracy: 0.0001)
        XCTAssertEqual(filter.neutralTemperature, 5200, accuracy: 1)
        XCTAssertEqual(filter.neutralTint, 12, accuracy: 0.5)
        XCTAssertFalse(filter.isGamutMappingEnabled)
        XCTAssertEqual(filter.extendedDynamicRangeAmount, 1.0, accuracy: 0.0001)

        // The gated knobs: assert only where this file's decoder offers the adjustment. Whether a
        // given camera supports moire reduction is not this test's business; whether the value lands
        // when it does is.
        if filter.isSharpnessSupported { XCTAssertEqual(filter.sharpnessAmount, 0.4, accuracy: 0.0001) }
        if filter.isContrastSupported { XCTAssertEqual(filter.contrastAmount, 0.6, accuracy: 0.0001) }
        if filter.isDetailSupported { XCTAssertEqual(filter.detailAmount, 1.5, accuracy: 0.0001) }
        if filter.isMoireReductionSupported { XCTAssertEqual(filter.moireReductionAmount, 0.2, accuracy: 0.0001) }
        if filter.isLocalToneMapSupported { XCTAssertEqual(filter.localToneMapAmount, 0.3, accuracy: 0.0001) }
        if filter.isLuminanceNoiseReductionSupported {
            XCTAssertEqual(filter.luminanceNoiseReductionAmount, 0.7, accuracy: 0.0001)
        }
        if filter.isColorNoiseReductionSupported {
            XCTAssertEqual(filter.colorNoiseReductionAmount, 0.8, accuracy: 0.0001)
        }
        if filter.isLensCorrectionSupported { XCTAssertFalse(filter.isLensCorrectionEnabled) }
        #if compiler(>=6.2)
            if #available(macOS 26, *), filter.isHighlightRecoverySupported {
                XCTAssertFalse(filter.isHighlightRecoveryEnabled)
            }
        #endif

        XCTAssertNotNil(filter.outputImage, "a configured filter must still produce an image")
    }

    /// The migration's actual promise: applying `.neutral` leaves the filter exactly as the decoder
    /// built it, so an untouched document renders identically to today's `developRAWNeutral`.
    func testApplyingNeutralChangesNothingOnARealFilter() throws {
        guard let url = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW to develop; see Fixtures.localRAWURL")
        }

        // Two filters from the same file start identical; only one of them is touched.
        let reference = try XCTUnwrap(CIRAWFilter(imageURL: url))
        let subject = try XCTUnwrap(CIRAWFilter(imageURL: url))
        RAWDevelopSettings.neutral.apply(to: subject)

        XCTAssertEqual(subject.exposure, reference.exposure)
        XCTAssertEqual(subject.baselineExposure, reference.baselineExposure)
        XCTAssertEqual(subject.shadowBias, reference.shadowBias)
        XCTAssertEqual(subject.boostAmount, reference.boostAmount)
        XCTAssertEqual(subject.boostShadowAmount, reference.boostShadowAmount)
        XCTAssertEqual(subject.neutralTemperature, reference.neutralTemperature)
        XCTAssertEqual(subject.neutralTint, reference.neutralTint)
        XCTAssertEqual(subject.sharpnessAmount, reference.sharpnessAmount)
        XCTAssertEqual(subject.contrastAmount, reference.contrastAmount)
        XCTAssertEqual(subject.detailAmount, reference.detailAmount)
        XCTAssertEqual(subject.moireReductionAmount, reference.moireReductionAmount)
        XCTAssertEqual(subject.localToneMapAmount, reference.localToneMapAmount)
        XCTAssertEqual(subject.luminanceNoiseReductionAmount, reference.luminanceNoiseReductionAmount)
        XCTAssertEqual(subject.colorNoiseReductionAmount, reference.colorNoiseReductionAmount)
        XCTAssertEqual(subject.isLensCorrectionEnabled, reference.isLensCorrectionEnabled)
        XCTAssertEqual(subject.isGamutMappingEnabled, reference.isGamutMappingEnabled)
        XCTAssertEqual(subject.extendedDynamicRangeAmount, reference.extendedDynamicRangeAmount)
        #if compiler(>=6.2)
            if #available(macOS 26, *) {
                XCTAssertEqual(subject.isHighlightRecoveryEnabled, reference.isHighlightRecoveryEnabled)
            }
        #endif
    }

    // MARK: - The gates themselves, which leave no runtime trace to assert on

    /// Every per-file adjustment in `apply(to:)` must be written **only** inside a condition naming
    /// its own `is*Supported` flag.
    ///
    /// **This reads source text, and for the same reason `RenderStackTests` and
    /// `RAWCapabilitiesTests.testEveryGatedSeedIsReadBehindItsOwnSupportedFlag` do.** The property is
    /// invisible at runtime because the framework itself masks it: `CIRAWFilter` silently discards a
    /// write to an adjustment its decoder does not implement, so a pixel comparison cannot tell "our
    /// gate ran" from "our gate was deleted and the framework's own discard covered for it".
    /// Confirmed directly —
    /// `RAWCapabilitiesTests.testAValueWrittenToAnUnsupportedAdjustmentChangesNothing` measures a
    /// worst pixel delta of exactly **0** on the Leica in `realworldtest/` whether
    /// `filter.isLocalToneMapSupported` is checked or not. The only way to keep the gate honest is to
    /// look at the source.
    ///
    /// Deliberately narrow, like its `RAWCapabilitiesTests` sibling: it checks that each property's
    /// `if let` condition names its own flag, not what the rest of the expression does with it. A
    /// rewrite that keeps the flag but inverts the check would slip through — this guards against
    /// deletion and mis-pairing, which are the failures that actually happen (see the mutation tests
    /// this shipped with).
    func testEveryGatedAdjustmentIsAppliedOnlyBehindItsOwnSupportedFlag() throws {
        let source = URL(fileURLWithPath: #filePath)            // Tests/LUTzyKitTests/…
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()                         // package root
            .appendingPathComponent("Sources/LUTzyKit/Models/RAWDevelopSettings.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        let signature = "func apply(to filter: CIRAWFilter) {"
        let start = try XCTUnwrap(text.range(of: signature),
                                  "could not find apply(to:) — was it renamed?")
        let rest = text[start.upperBound...]
        let end = try XCTUnwrap(rest.range(of: "\n    }"), "could not find the end of the method")
        let body = String(rest[..<end.lowerBound])

        /// The condition guarding `property`'s `if let` binding — from `if let <property>` up to (but
        /// not including) the opening brace of that `if` statement.
        ///
        /// **Must fail, not fail open, when `property` cannot be found.** A property renamed, moved
        /// out of `apply(to:)`, or written some other way (e.g. `if settings.property != nil`) is
        /// exactly the kind of drift this test exists to catch, so a miss here is `XCTFail`, not a
        /// vacuous pass.
        func condition(for property: String) throws -> String {
            let needle = "if let \(property)"
            guard let range = body.range(of: needle) else {
                XCTFail(
                    "\(needle) not found in apply(to:) — \(property) was renamed, removed, or is no "
                    + "longer written behind an `if let` binding, so this test can no longer vouch for it"
                )
                return ""
            }
            let after = body[range.lowerBound...]
            guard let braceRange = after.range(of: "{") else {
                XCTFail("could not find the opening brace of \(property)'s if statement")
                return ""
            }
            return String(after[..<braceRange.lowerBound])
        }

        // The eight per-file adjustments, each paired with the flag that must gate it. A row here
        // pairing a property with the *wrong* flag would still parse and still find a `Supported`
        // substring — `contains(flag)` below only passes when the flag named is this property's own.
        let gated: [(property: String, flag: String)] = [
            ("sharpnessAmount", "isSharpnessSupported"),
            ("contrastAmount", "isContrastSupported"),
            ("detailAmount", "isDetailSupported"),
            ("moireReductionAmount", "isMoireReductionSupported"),
            ("localToneMapAmount", "isLocalToneMapSupported"),
            ("luminanceNoiseReductionAmount", "isLuminanceNoiseReductionSupported"),
            ("colorNoiseReductionAmount", "isColorNoiseReductionSupported"),
            ("lensCorrectionEnabled", "isLensCorrectionSupported"),
        ]

        for (property, flag) in gated {
            let condition = try condition(for: property)
            XCTAssertTrue(
                condition.contains(flag),
                "\(property) is written without checking \(flag) — writing it unconditionally would "
                + "push it onto a CIRAWFilter whose decoder may not implement it. Condition found: "
                + "\"\(condition.trimmingCharacters(in: .whitespacesAndNewlines))\""
            )
        }

        // `highlightRecoveryEnabled` is gated on BOTH `#available(macOS 26, *)` and its own
        // `isHighlightRecoverySupported` flag — the only knob newer than the deployment target. Both
        // conditions have to survive, or the test would pass against code that dropped either one.
        let highlightCondition = try condition(for: "highlightRecoveryEnabled")
        XCTAssertTrue(
            highlightCondition.contains("isHighlightRecoverySupported"),
            "highlightRecoveryEnabled is written without checking isHighlightRecoverySupported. "
            + "Condition found: \"\(highlightCondition.trimmingCharacters(in: .whitespacesAndNewlines))\""
        )
        XCTAssertTrue(
            highlightCondition.contains("#available"),
            "highlightRecoveryEnabled is written without an #available guard — this is the one knob "
            + "newer than the macOS 14 deployment target. "
            + "Condition found: \"\(highlightCondition.trimmingCharacters(in: .whitespacesAndNewlines))\""
        )

        // The ungated properties must NOT be behind a `Supported` condition — otherwise a change that
        // gated *everything* (including these) would still pass the loop above, which only checks
        // that the eight it lists are gated, not that gating stops there.
        let ungated = [
            "exposure", "baselineExposure", "shadowBias", "boostAmount", "boostShadowAmount",
            "neutralTemperature", "neutralTint", "gamutMappingEnabled", "extendedDynamicRangeAmount",
        ]
        for property in ungated {
            let condition = try condition(for: property)
            XCTAssertFalse(
                condition.contains("Supported"),
                "\(property) is documented and tested as ungated, but apply(to:) now guards it with "
                + "a Supported flag: \"\(condition.trimmingCharacters(in: .whitespacesAndNewlines))\" "
                + "— if that's deliberate, move it into the `gated` table above and update its doc "
                + "comment in RAWDevelopSettings.swift in the same commit"
            )
        }

        // Completeness: every stored property of RAWDevelopSettings must appear in exactly one of the
        // three lists above (gated, highlightRecoveryEnabled, or ungated), or a new knob could land in
        // apply(to:) — gated correctly or not — without this test ever looking at it. Read via
        // `Mirror` rather than hardcoded a third time, so the source of truth is the type itself.
        let allProperties = Set(Mirror(reflecting: RAWDevelopSettings()).children.compactMap(\.label))
        let covered = Set(gated.map(\.property)).union(ungated).union(["highlightRecoveryEnabled"])
        XCTAssertEqual(
            allProperties, covered,
            "RAWDevelopSettings gained or lost a stored property that this test doesn't account for "
            + "— add it to the `gated` table or the `ungated` list above, whichever apply(to:) does"
        )
    }
}
