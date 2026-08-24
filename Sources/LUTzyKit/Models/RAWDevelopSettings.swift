import Foundation
import CoreImage

/// The RAW develop half of an `EditDocument` — the knobs that have to be set on a `CIRAWFilter`
/// *before* `outputImage` is read.
///
/// **Why this is a field and not an `AdjustmentNode`.** `CIRAWFilter` must be rebuilt from the source
/// and configured before it produces an image; you cannot chain develop onto an already-developed
/// `CIImage`. So develop is consumed at the source stage of the pipeline, and `ImageSource` carries a
/// URL or `Data` rather than an image so the RAW can be re-developed per render. The asymmetry is
/// forced by the framework, not a modelling preference. See `docs/PHASE2_SPEC.md` §4.2.
///
/// **Every property is optional, and `nil` means "leave `CIRAWFilter` at its decoder default".** That
/// is not a stylistic choice: several of these defaults *vary per image* (`baselineExposure`,
/// `shadowBias`, the noise-reduction and sharpening amounts), so there is no fixed number that stands
/// for "untouched". Storing `nil` is the only way to make `.neutral` byte-identical to today's
/// `ImageDecoder.developRAWNeutral`, which sets nothing at all.
///
/// Property names mirror `CIRAWFilter`'s exactly so there is no translation layer to get wrong. The
/// set below is header-verified (`docs/PHASE2_SPEC.md` §9); an earlier draft of the spec contained
/// fabricated names.
///
/// Note `scaleFactor` and `draftModeEnabled` are absent by design — they are properties of *how* a
/// render is being done, not of the edit, and belong to `RenderScale`.
struct RAWDevelopSettings: Codable, Sendable, Equatable {

    // MARK: - Tone

    /// Stops of exposure. `CIRAWFilter` default: 0.
    var exposure: Double?
    /// Baseline exposure. Default varies per image.
    var baselineExposure: Double?
    /// Amount subtracted from shadows. Default varies per image.
    var shadowBias: Double?
    /// Global tone curve, 0…1 (0 = linear response). Default: 1.
    var boostAmount: Double?
    /// Shadow lift, 0…2 (<1 darkens, >1 lightens). No effect when `boostAmount` is 0. Default: 1.
    var boostShadowAmount: Double?

    // MARK: - White balance

    /// 2000…50000 K. Queried from the file's as-shot value unless set.
    var neutralTemperature: Double?
    /// -150…150. Queried from the file's as-shot value unless set.
    var neutralTint: Double?

    // MARK: - Detail — each gated on its own `is*Supported` flag

    /// 0…1. Only applied when `isSharpnessSupported`.
    var sharpnessAmount: Double?
    /// Local contrast, 0…1. Only applied when `isContrastSupported`.
    var contrastAmount: Double?
    /// Detail enhancement, 0…3. Only applied when `isDetailSupported`.
    var detailAmount: Double?
    /// 0…1. Only applied when `isMoireReductionSupported`.
    var moireReductionAmount: Double?
    /// Local tone curve, 0…1. Only applied when `isLocalToneMapSupported`.
    var localToneMapAmount: Double?
    /// 0…1. Only applied when `isLuminanceNoiseReductionSupported`.
    var luminanceNoiseReductionAmount: Double?
    /// Chroma noise reduction, 0…1. Only applied when `isColorNoiseReductionSupported`.
    var colorNoiseReductionAmount: Double?
    /// Only applied when `isLensCorrectionSupported`. Default varies per image.
    var lensCorrectionEnabled: Bool?

    // MARK: - Gamut and dynamic range

    /// Default: true.
    var gamutMappingEnabled: Bool?
    /// 0…2 (0 = no EDR, 1 = default, 2 = maximum). Default: 0.
    ///
    /// This is the *only* EDR knob `CIRAWFilter` has, it carries no availability macro, and it is
    /// callable unguarded on the macOS 14 deployment target. There is no `enableEDR` or
    /// `isEDRModeEnabled`; the spec's earlier draft invented both.
    var extendedDynamicRangeAmount: Double?

    /// The one knob here that is newer than the deployment target — see `apply(to:)`. Default: true.
    ///
    /// Stored unconditionally, applied only where the OS has it. A document is a value, not a
    /// capability probe: the same edit opened on macOS 26 and on macOS 14 should be the same
    /// document, so a machine that gains the API honours a document written before it.
    var highlightRecoveryEnabled: Bool?

    // MARK: - Neutral

    /// Every knob left at the decoder's own default. Applying this to a `CIRAWFilter` sets nothing,
    /// so it renders byte-identically to `ImageDecoder.developRAWNeutral`.
    static let neutral = RAWDevelopSettings()

    /// True when nothing here would be pushed onto a `CIRAWFilter`.
    var isNeutral: Bool { self == .neutral }

    // MARK: - Application

    /// Push these settings onto a freshly-built `CIRAWFilter`, **before** reading `outputImage`.
    ///
    /// Nothing is set for a `nil` property, and nothing is set for a knob this particular file does
    /// not support — `CIRAWFilter` exposes an `is*Supported` flag per adjustment, and writing to an
    /// unsupported one is at best ignored. `.neutral` therefore touches nothing.
    ///
    /// Defined here rather than in the render pipeline because the mapping from stored value to
    /// framework property is a property of this type, and because keeping it here means the
    /// compiler checks the whole `CIRAWFilter` surface at Step 2 rather than at Step 3.
    func apply(to filter: CIRAWFilter) {
        // Ungated: these exist for every decodable RAW.
        if let exposure { filter.exposure = Float(exposure) }
        if let baselineExposure { filter.baselineExposure = Float(baselineExposure) }
        if let shadowBias { filter.shadowBias = Float(shadowBias) }
        if let boostAmount { filter.boostAmount = Float(boostAmount) }
        if let boostShadowAmount { filter.boostShadowAmount = Float(boostShadowAmount) }
        if let neutralTemperature { filter.neutralTemperature = Float(neutralTemperature) }
        if let neutralTint { filter.neutralTint = Float(neutralTint) }
        if let gamutMappingEnabled { filter.isGamutMappingEnabled = gamutMappingEnabled }
        if let extendedDynamicRangeAmount {
            filter.extendedDynamicRangeAmount = Float(extendedDynamicRangeAmount)
        }

        // Per-file: each of these is meaningless for a camera model whose decoder doesn't offer it.
        if let sharpnessAmount, filter.isSharpnessSupported {
            filter.sharpnessAmount = Float(sharpnessAmount)
        }
        if let contrastAmount, filter.isContrastSupported {
            filter.contrastAmount = Float(contrastAmount)
        }
        if let detailAmount, filter.isDetailSupported {
            filter.detailAmount = Float(detailAmount)
        }
        if let moireReductionAmount, filter.isMoireReductionSupported {
            filter.moireReductionAmount = Float(moireReductionAmount)
        }
        if let localToneMapAmount, filter.isLocalToneMapSupported {
            filter.localToneMapAmount = Float(localToneMapAmount)
        }
        if let luminanceNoiseReductionAmount, filter.isLuminanceNoiseReductionSupported {
            filter.luminanceNoiseReductionAmount = Float(luminanceNoiseReductionAmount)
        }
        if let colorNoiseReductionAmount, filter.isColorNoiseReductionSupported {
            filter.colorNoiseReductionAmount = Float(colorNoiseReductionAmount)
        }
        if let lensCorrectionEnabled, filter.isLensCorrectionSupported {
            filter.isLensCorrectionEnabled = lensCorrectionEnabled
        }

        // The only knob newer than the macOS 14 deployment target, so the only one needing
        // `#available`. The SDK header still marks it `16_0`, which the Swift importer maps onto the
        // renumbered macOS 26 — `26` is written because that is the version the compiler enforces.
        //
        // This guard is not optional politeness: with a 14.0 deployment target the compiler *refuses*
        // the reference without it. That is the point of building against a current SDK — the
        // requirement is checked rather than remembered. The compile-time guard additionally lets
        // older SDKs build the app; Xcode 26 is the first toolchain that declares this symbol.
        //
        // A no-op on macOS 14/15, where the document keeps the setting and the decoder never sees it.
        #if compiler(>=6.2)
            if let highlightRecoveryEnabled,
               #available(macOS 26, *),
               filter.isHighlightRecoverySupported {
                filter.isHighlightRecoveryEnabled = highlightRecoveryEnabled
            }
        #endif
    }
}
