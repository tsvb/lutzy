import Foundation

/// Which `AdjustmentNode` case a control belongs to, and where that node sits in the pipeline.
///
/// The raw values **are** the canonical order — `AdjustmentNode`'s own case-declaration order, which
/// is what `PHASE2_SPEC.md` §3 shows and what `RenderPipeline.applyAdjustments` folds. `Comparable`
/// on the raw value is what lets a sparse array stay sorted without a separate sort key.
enum AdjustmentSlot: Int, Sendable, CaseIterable, Comparable {
    case exposure = 0
    case colorControls
    case highlightShadow
    case temperatureTint
    case vibrance

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// A node of this slot's case that does nothing. The seed a control reads through to when the
    /// document holds no node for this slot, and the base a write is applied to.
    var neutralNode: AdjustmentNode {
        switch self {
        case .exposure: return .neutralExposure
        case .colorControls: return .neutralColorControls
        case .highlightShadow: return .neutralHighlightShadow
        case .temperatureTint: return .neutralTemperatureTint
        case .vibrance: return .neutralVibrance
        }
    }

    /// The controls that together fill this slot's node, in row order.
    var controls: [AdjustmentControl] {
        AdjustmentControl.allCases.filter { $0.slot == self }
    }

    /// Rebuild this slot's node from its controls' values.
    ///
    /// **No `default:` arm, deliberately** — the same reasoning as `DevelopControl.isToggle`. A sixth
    /// slot must be a compile error naming this file, not a silently-dropped adjustment.
    func node(from values: [AdjustmentControl: Double]) -> AdjustmentNode {
        func v(_ control: AdjustmentControl) -> Double { values[control] ?? control.neutral }
        switch self {
        case .exposure:
            return .exposure(ev: v(.exposure))
        case .colorControls:
            return .colorControls(brightness: v(.brightness), contrast: v(.contrast),
                                  saturation: v(.saturation))
        case .highlightShadow:
            return .highlightShadow(highlights: v(.highlights), shadows: v(.shadows))
        case .temperatureTint:
            return .temperatureTint(temp: v(.temperature), tint: v(.tint))
        case .vibrance:
            return .vibrance(amount: v(.vibrance))
        }
    }
}

extension AdjustmentNode {
    /// Which slot this node occupies. Total and exhaustive; there is no "other".
    var slot: AdjustmentSlot {
        switch self {
        case .exposure: return .exposure
        case .colorControls: return .colorControls
        case .highlightShadow: return .highlightShadow
        case .temperatureTint: return .temperatureTint
        case .vibrance: return .vibrance
        }
    }
}

/// One row in the Adjust inspector.
///
/// The `DevelopControl` analogue, and deliberately the same shape: a value rather than a set of
/// `if`s in a `ViewBuilder`, so which rows exist and what each one does can be asserted without
/// instantiating a view — this repo has no SwiftUI view tests. **The declaration order below is the
/// panel's layout order**, and it is canonical pipeline order with the multi-parameter nodes
/// expanded in place.
///
/// Nine rows over five nodes, rather than five rows with sub-sliders: "Colour Controls" is a
/// `CIFilter` name, not a photographer's, and grouping three unrelated knobs under it leaks an
/// implementation detail into the UI. See the Step 10b design doc §2.
enum AdjustmentControl: String, Sendable, CaseIterable, Hashable {
    case exposure
    case brightness
    case contrast
    case saturation
    case highlights
    case shadows
    case temperature
    case tint
    case vibrance

    var slot: AdjustmentSlot {
        switch self {
        case .exposure: return .exposure
        case .brightness, .contrast, .saturation: return .colorControls
        case .highlights, .shadows: return .highlightShadow
        case .temperature, .tint: return .temperatureTint
        case .vibrance: return .vibrance
        }
    }

    var title: String {
        switch self {
        case .exposure: return "Exposure"
        case .brightness: return "Brightness"
        case .contrast: return "Contrast"
        case .saturation: return "Saturation"
        case .highlights: return "Highlights"
        case .shadows: return "Shadows"
        case .temperature: return "Temperature"
        case .tint: return "Tint"
        case .vibrance: return "Vibrance"
        }
    }

    /// The value at which this control does nothing.
    ///
    /// Every one of these equals the value `AdjustmentNode.isIdentity` names *and* the filter's own
    /// `kCIAttributeIdentity`, checked by probing the runtime `CIFilter.attributes` dictionary on the
    /// macOS 26 SDK. `testEveryControlsNeutralMatchesTheNodesIdentity` asserts the first half of that
    /// agreement on every run; the second half was a one-off measurement, recorded on `range`.
    var neutral: Double {
        switch self {
        case .exposure: return 0
        case .brightness: return 0
        case .contrast: return 1
        case .saturation: return 1
        case .highlights: return 1
        case .shadows: return 0
        case .temperature: return 6500
        case .tint: return 0
        case .vibrance: return 0
        }
    }

    /// The slider range.
    ///
    /// **Measured, not guessed.** `CIFilterBuiltins.h` documents no ranges at all — only prose. The
    /// numbers live in the runtime `CIFilter.attributes` dictionary, probed directly on the macOS 26
    /// SDK. What it reports, as `kCIAttributeSliderMin…Max` with `kCIAttributeIdentity` in brackets:
    /// `inputEV` −10…10 [0], `inputBrightness` −1…1 [0], `inputContrast` 0.25…4 [1] (with
    /// `kCIAttributeMin` 0 — see below),
    /// `inputSaturation` 0…2 [1], `inputHighlightAmount` **0.3…1** [1], `inputShadowAmount` −1…1 [0],
    /// `inputAmount` (vibrance) −1…1 [0]. `CITemperatureAndTint` reports no range, because its
    /// parameters are `CIVector`s.
    ///
    /// Four rows need their reasoning recorded, because each is a place a later reader would
    /// otherwise assume a mistake:
    ///
    /// **Exposure is narrowed to −4…4**, though the filter accepts −10…10. `DevelopControl.exposure`
    /// is −4…4 — a UI throw chosen in 10a, not a framework limit — and two exposure sliders one
    /// inspector tab apart with different travel is worse than either range on its own. Widen both
    /// together or neither.
    ///
    /// **Highlights runs 0.3…1 with its identity at the maximum.** That floor is the filter's, not
    /// ours. The slider therefore travels one way only: down, recovering highlights. It is the sole
    /// exception to "every neutral sits strictly inside its range" — see
    /// `testEveryNeutralSitsInsideItsRangeExceptHighlights`.
    ///
    /// **Temperature is 2000…11000 K, narrower than `DevelopControl.whiteBalance`'s 2000…50000.**
    /// Forced by the inversion, not chosen for taste — see `sliderMapped(_:)`.
    ///
    /// **Contrast is 0…2, not the filter's suggested 0.25…4.** The suggestion puts identity (1) a
    /// fifth of the way along the track: four fifths of the travel adds contrast and one fifth
    /// removes it, next to a Saturation slider that is symmetric about the same identity. 0…2 is
    /// symmetric, matches Saturation, and gives reducing contrast the same throw as adding it.
    ///
    /// Going below 0.25 is safe, and that was **measured rather than assumed** — the concern was a
    /// dead zone in the bottom eighth of the track, the same defect the temperature range exists to
    /// avoid. `inputContrast` reports `kCIAttributeSliderMin` 0.25 but `kCIAttributeMin` **0**: the
    /// 0.25 is a suggested UI bound, not a limit. Rendered on a black-to-white gradient, contrast
    /// 0.20 / 0.15 / 0.10 / 0.05 / 0 each differ from 0.25 and from each other, flattening
    /// monotonically to a uniform 128 at 0. Nothing clamps. What the top of the range gives up is
    /// real — the filter accepts up to 4 — but 2.0 already crushes a gradient to 2…253, so the
    /// travel above it is mostly ornamental.
    var range: ClosedRange<Double> {
        switch self {
        case .exposure: return -4...4
        case .brightness: return -1...1
        case .contrast: return 0...2
        case .saturation: return 0...2
        case .highlights: return 0.3...1
        case .shadows: return -1...1
        case .temperature: return 2000...11000
        case .tint: return -150...150
        case .vibrance: return -1...1
        }
    }

    /// Which of the two Adjust-panel sections this row belongs to.
    ///
    /// **No `default:` arm**, the same reasoning as `isToggle` on `DevelopControl`: a tenth control
    /// must be a compile error naming this file, not a row that silently drops into the wrong
    /// section — or neither.
    var group: AdjustmentGroup {
        switch self {
        case .exposure, .brightness, .contrast, .highlights, .shadows: return .light
        case .saturation, .vibrance, .temperature, .tint: return .color
        }
    }

    /// The unit suffix shown after the readout, or `nil` for a plain number.
    var unit: String? {
        switch self {
        case .temperature: return "K"
        case .exposure, .brightness, .contrast, .saturation, .highlights, .shadows, .tint, .vibrance:
            return nil
        }
    }
}

/// The two sections `AdjustInspectorView` lists its rows under.
///
/// `Light` is tone (exposure, brightness, contrast, highlights, shadows); `Color` is everything that
/// changes hue or chroma rather than luminance (saturation, vibrance, temperature, tint). The raw
/// value is the section header text.
enum AdjustmentGroup: String, CaseIterable, Sendable {
    case light = "Light"
    case color = "Color"
}

// MARK: - The sparse contract

/// `EditDocument.adjustments` holds **only non-identity nodes**, kept in canonical order.
///
/// A row sitting at its neutral value contributes nothing to the array, which is what keeps
/// `EditDocument()` equal to `[]` — and with it §5's "empty document is identity" invariant, and
/// `originalForComparison`, which sets `adjustments: []` to build the A/B baseline. It also keeps
/// Step 11's undo snapshots small, since an untouched panel costs nothing to snapshot.
///
/// Both functions are pure — no view model, no `CIContext`, no image — which is what lets the whole
/// contract be asserted on CI.
extension AdjustmentControl {

    /// This control's current value: the stored one, or its neutral when no node holds it.
    ///
    /// **No `default:` arm** — exhaustive over `self`, so a tenth control is a compile error naming
    /// this file rather than a row that silently always reads neutral.
    func value(in adjustments: [AdjustmentNode]) -> Double {
        let node = adjustments.first { $0.slot == slot }
        switch self {
        case .exposure:
            guard case .exposure(let ev)? = node else { return neutral }
            return ev
        case .brightness:
            guard case .colorControls(let brightness, _, _)? = node else { return neutral }
            return brightness
        case .contrast:
            guard case .colorControls(_, let contrast, _)? = node else { return neutral }
            return contrast
        case .saturation:
            guard case .colorControls(_, _, let saturation)? = node else { return neutral }
            return saturation
        case .highlights:
            guard case .highlightShadow(let highlights, _)? = node else { return neutral }
            return highlights
        case .shadows:
            guard case .highlightShadow(_, let shadows)? = node else { return neutral }
            return shadows
        case .temperature:
            guard case .temperatureTint(let temp, _)? = node else { return neutral }
            return temp
        case .tint:
            guard case .temperatureTint(_, let tint)? = node else { return neutral }
            return tint
        case .vibrance:
            guard case .vibrance(let amount)? = node else { return neutral }
            return amount
        }
    }

    /// `adjustments` with this control set to `value` — still sparse, still in canonical order.
    ///
    /// Rebuilds the whole node from its controls (each read through `value(in:)`, so an absent node
    /// reads as neutral), then inserts it at its canonical index or drops it, according to
    /// `isIdentity`. Insertion is by slot rather than appended: order is meaningful to the render, so
    /// writing the rows bottom-up must produce the same graph as writing them top-down.
    func setting(_ value: Double, in adjustments: [AdjustmentNode]) -> [AdjustmentNode] {
        var values: [AdjustmentControl: Double] = [:]
        for sibling in slot.controls { values[sibling] = sibling.value(in: adjustments) }
        values[self] = value

        var result = adjustments.filter { $0.slot != slot }
        let updated = slot.node(from: values)
        guard !updated.isIdentity else { return result }

        let index = result.firstIndex { $0.slot > slot } ?? result.count
        result.insert(updated, at: index)
        return result
    }
}

// MARK: - Slider ↔ model mapping

extension AdjustmentControl {

    /// Convert between what the slider reads and what the node stores. **Self-inverse**, so one
    /// function serves both directions and they cannot drift apart.
    ///
    /// The identity for eight of the nine controls. Temperature is the exception, and the reason is
    /// measured rather than assumed:
    ///
    /// `RenderPipeline` pins `CITemperatureAndTint.neutral` at D65 and moves only `targetNeutral`,
    /// which makes the node's Kelvin run **backwards** — 3200 K warms, 9000 K cools
    /// (`PHASE2_SPEC.md` §8.7, pinned by `testRaisingKelvinCoolsTheImage`). `CIRAWFilter`'s
    /// `neutralTemperature`, one inspector tab away, runs the photographic way round
    /// (`RAWCapabilitiesTests.testRaisingNeutralTemperatureWarmsTheImage`). Two Kelvin sliders in one
    /// inspector that move opposite ways is not a defensible thing to ship, so this reflects the
    /// adjustment slider about D65 and the Develop slider is left alone.
    ///
    /// **The reflection is why the temperature range is 2000…11000 rather than Develop's
    /// 2000…50000.** `13000 − K` maps 2000…50000 onto 11000…−37000, and negative Kelvin is not a
    /// colour. A range symmetric about 6500 makes the map a closed involution over itself: no
    /// clamping, no dead zone, and 6500 as the fixed point so identity survives the round trip.
    /// 2000…11000 is also the more useful photographic throw — Develop's upper bound is
    /// `CIRAWFilter`'s documented limit, which is a limit rather than a recommendation.
    ///
    /// The model still stores filter-native values. Reversing this decision later means changing
    /// this one function.
    func sliderMapped(_ value: Double) -> Double {
        switch self {
        case .temperature:
            return 2 * Self.temperaturePivot - value
        case .exposure, .brightness, .contrast, .saturation, .highlights, .shadows, .tint, .vibrance:
            return value
        }
    }

    /// D65 — the fixed point of the temperature reflection, and `temperatureTint`'s identity.
    private static let temperaturePivot: Double = 6500
}
