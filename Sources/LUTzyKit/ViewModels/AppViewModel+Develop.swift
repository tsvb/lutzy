import SwiftUI

/// `AppViewModel`'s RAW develop bindings, split out at Step 10b.
///
/// Pure code motion — every member below arrived here unchanged from `AppViewModel.swift`, where it
/// was written in Step 10a. The split happened because Step 10b adds a second inspector panel's
/// worth of bindings to a file that had already reached 1004 lines, and a four-figure view model is
/// where the next reader stops being able to hold the whole thing in their head.
///
/// `private` members do not survive a file split in Swift — `setDevelop` is now `fileprivate`, which
/// is the same guarantee (nothing outside this file can call it) expressed at file scope.
extension AppViewModel {
    // MARK: - RAW develop

    /// A two-way binding for one develop control.
    ///
    /// **Reading never writes.** Every `RAWDevelopSettings` property is `Optional`, with `nil`
    /// meaning "leave `CIRAWFilter` at its decoder default", and `.neutral` is byte-identical to
    /// `ImageDecoder.developRAWNeutral` precisely *because it sets nothing*. So the getter falls back
    /// to the decoder's own value — a fixed default where there is one, otherwise the per-image seed
    /// from `rawCapabilities` — and only the setter stores anything. Seeding every field when the
    /// panel opened would silently make every document non-neutral.
    ///
    /// **Writes for a toggle control are immediate, not debounced.** `updateDocument(debounced:)`'s
    /// own doc comment is explicit that debouncing is for continuous controls only — "a checkbox that
    /// lagged 60 ms would feel broken" — and this binding backs both sliders and the three Bool
    /// controls (`lensCorrection`, `gamutMapping`, `highlightRecovery`), routed through `Toggle` in
    /// the view. Only sliders get the 60 ms coalescing.
    func developBinding(for control: DevelopControl) -> Binding<Double> {
        Binding(
            get: { self.developValue(for: control) },
            set: { newValue in
                self.updateDocument(debounced: !control.isToggle) { document in
                    Self.setDevelop(control, to: newValue, in: &document.rawDevelop)
                }
            }
        )
    }

    /// What a control should display: the stored setting, else the decoder's own starting point.
    ///
    /// **A literal appears here only where `CIRAWFilter` documents a fixed default** — `exposure` 0,
    /// `boost`/`boostShadow` 1, `extendedDynamicRange` 0, `gamutMapping`/`highlightRecovery` true.
    /// Everything else reads a per-image seed off `rawCapabilities`, because everything else *has* no
    /// fixed default: `RAWDevelopSettings`' type doc says outright that the baseline exposure, shadow
    /// bias, noise-reduction and sharpening defaults vary per image, and as-shot white balance on the
    /// Leica in `realworldtest/` is 5842.2 K, not a round number. Guessing 0 for those would open the
    /// slider away from where the picture actually is, and the first nudge would jump it — the exact
    /// defect the white-balance seed was added to prevent.
    ///
    /// The trailing `?? 0` after each seed is only the no-image / not-a-RAW case: `rawCapabilities`
    /// is `nil` until the probe lands, and while it is nil the panel is showing
    /// `DevelopPanelState.probing` or `.noDevelopStage`, neither of which draws a control.
    ///
    /// **That `0` is uniform, including white balance.** It used to be `?? 6500` for
    /// `neutralTemperature` alone — D65, a plausible-looking Kelvin — which made the sentence above
    /// untrue for exactly one line and, worse, made the unreachable branch return a number that
    /// *looks* like a real answer. Nothing distinguishes a seed that failed to arrive from a decoder
    /// that genuinely reports 6500 K. Every seeded control now falls back the same way, so the
    /// fallback is legible as "no answer" wherever it surfaces.
    func developValue(for control: DevelopControl) -> Double {
        let develop = document.rawDevelop
        let seed = rawCapabilities
        switch control {
        case .exposure: return develop.exposure ?? 0
        case .baselineExposure: return develop.baselineExposure ?? seed?.baselineExposure ?? 0
        case .shadowBias: return develop.shadowBias ?? seed?.shadowBias ?? 0
        case .boost: return develop.boostAmount ?? 1
        case .boostShadow: return develop.boostShadowAmount ?? 1
        case .whiteBalance: return develop.neutralTemperature ?? seed?.asShotTemperature ?? 0
        case .sharpness: return develop.sharpnessAmount ?? seed?.sharpnessAmount ?? 0
        case .contrast: return develop.contrastAmount ?? seed?.contrastAmount ?? 0
        case .detail: return develop.detailAmount ?? seed?.detailAmount ?? 0
        case .moireReduction:
            return develop.moireReductionAmount ?? seed?.moireReductionAmount ?? 0
        case .localToneMap: return develop.localToneMapAmount ?? seed?.localToneMapAmount ?? 0
        case .luminanceNoiseReduction:
            return develop.luminanceNoiseReductionAmount ?? seed?.luminanceNoiseReductionAmount ?? 0
        case .colorNoiseReduction:
            return develop.colorNoiseReductionAmount ?? seed?.colorNoiseReductionAmount ?? 0
        case .lensCorrection:
            return (develop.lensCorrectionEnabled ?? seed?.lensCorrectionEnabled ?? false) ? 1 : 0
        case .gamutMapping: return (develop.gamutMappingEnabled ?? true) ? 1 : 0
        case .extendedDynamicRange: return develop.extendedDynamicRangeAmount ?? 0
        case .highlightRecovery: return (develop.highlightRecoveryEnabled ?? true) ? 1 : 0
        }
    }

    /// What `developValue(for:)` would read immediately after `resetDevelop(_:)` — the decoder's own
    /// default, used as `AdjustmentRow`'s reset target and as the "off neutral" comparison that
    /// decides whether its reset button is shown.
    ///
    /// Mirrors `developValue(for:)` exactly, with every stored (non-`nil`) half of the `??` chains
    /// removed — which is what "as if this control had just been reset" means, since a reset writes
    /// `nil`, not a literal. Kept beside it rather than derived from it (e.g. by resetting a scratch
    /// copy of `document.rawDevelop`) so the two stay a single switch apart for review, the same
    /// choice `setDevelop`/`resetDevelop` already made for the write side.
    func developNeutralValue(for control: DevelopControl) -> Double {
        let seed = rawCapabilities
        switch control {
        case .exposure: return 0
        case .baselineExposure: return seed?.baselineExposure ?? 0
        case .shadowBias: return seed?.shadowBias ?? 0
        case .boost: return 1
        case .boostShadow: return 1
        case .whiteBalance: return seed?.asShotTemperature ?? 0
        case .sharpness: return seed?.sharpnessAmount ?? 0
        case .contrast: return seed?.contrastAmount ?? 0
        case .detail: return seed?.detailAmount ?? 0
        case .moireReduction: return seed?.moireReductionAmount ?? 0
        case .localToneMap: return seed?.localToneMapAmount ?? 0
        case .luminanceNoiseReduction: return seed?.luminanceNoiseReductionAmount ?? 0
        case .colorNoiseReduction: return seed?.colorNoiseReductionAmount ?? 0
        case .lensCorrection: return (seed?.lensCorrectionEnabled ?? false) ? 1 : 0
        case .gamutMapping: return 1
        case .extendedDynamicRange: return 0
        case .highlightRecovery: return 1
        }
    }

    /// The tint half of white balance. Separate because `whiteBalance` is one row with two sliders.
    func developTintBinding() -> Binding<Double> {
        Binding(
            get: { self.document.rawDevelop.neutralTint ?? self.rawCapabilities?.asShotTint ?? 0 },
            set: { newValue in
                self.updateDocument(debounced: true) { $0.rawDevelop.neutralTint = newValue }
            }
        )
    }

    fileprivate static func setDevelop(
        _ control: DevelopControl, to value: Double, in develop: inout RAWDevelopSettings
    ) {
        switch control {
        case .exposure: develop.exposure = value
        case .baselineExposure: develop.baselineExposure = value
        case .shadowBias: develop.shadowBias = value
        case .boost: develop.boostAmount = value
        case .boostShadow: develop.boostShadowAmount = value
        case .whiteBalance: develop.neutralTemperature = value
        case .sharpness: develop.sharpnessAmount = value
        case .contrast: develop.contrastAmount = value
        case .detail: develop.detailAmount = value
        case .moireReduction: develop.moireReductionAmount = value
        case .localToneMap: develop.localToneMapAmount = value
        case .luminanceNoiseReduction: develop.luminanceNoiseReductionAmount = value
        case .colorNoiseReduction: develop.colorNoiseReductionAmount = value
        case .lensCorrection: develop.lensCorrectionEnabled = value != 0
        case .gamutMapping: develop.gamutMappingEnabled = value != 0
        case .extendedDynamicRange: develop.extendedDynamicRangeAmount = value
        case .highlightRecovery: develop.highlightRecoveryEnabled = value != 0
        }
    }

    /// Return one control to "decoder default" — `nil`, not zero.
    func resetDevelop(_ control: DevelopControl) {
        updateDocument { document in
            switch control {
            case .exposure: document.rawDevelop.exposure = nil
            case .baselineExposure: document.rawDevelop.baselineExposure = nil
            case .shadowBias: document.rawDevelop.shadowBias = nil
            case .boost: document.rawDevelop.boostAmount = nil
            case .boostShadow: document.rawDevelop.boostShadowAmount = nil
            case .whiteBalance:
                document.rawDevelop.neutralTemperature = nil
                document.rawDevelop.neutralTint = nil
            case .sharpness: document.rawDevelop.sharpnessAmount = nil
            case .contrast: document.rawDevelop.contrastAmount = nil
            case .detail: document.rawDevelop.detailAmount = nil
            case .moireReduction: document.rawDevelop.moireReductionAmount = nil
            case .localToneMap: document.rawDevelop.localToneMapAmount = nil
            case .luminanceNoiseReduction: document.rawDevelop.luminanceNoiseReductionAmount = nil
            case .colorNoiseReduction: document.rawDevelop.colorNoiseReductionAmount = nil
            case .lensCorrection: document.rawDevelop.lensCorrectionEnabled = nil
            case .gamutMapping: document.rawDevelop.gamutMappingEnabled = nil
            case .extendedDynamicRange: document.rawDevelop.extendedDynamicRangeAmount = nil
            case .highlightRecovery: document.rawDevelop.highlightRecoveryEnabled = nil
            }
        }
    }

    /// Return every develop control to the decoder's defaults.
    func resetAllDevelop() {
        updateDocument { $0.rawDevelop = .neutral }
    }
}
