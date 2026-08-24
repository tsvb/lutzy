import Foundation

/// The look, as a value.
///
/// This is the spine of Phase 2. Today LUTzy holds a *baked* `processedImage`; after the migration it
/// holds one of these and rebuilds the image from it on demand. Being a `Codable`, `Sendable`,
/// `Equatable` value is what buys undo, presets, per-image edits, and a clean actor boundary all at
/// once — none of which a baked bitmap can give. See `docs/PHASE2_SPEC.md` §3.
///
/// **An empty document is the identity transform.** `EditDocument()` must render the source
/// unchanged; that invariant is what lets the migration introduce the new spine under the old
/// behaviour without moving a pixel.
struct EditDocument: Codable, Sendable, Equatable {

    /// Schema version, present from the very first release.
    ///
    /// Nothing reads it yet. It exists now because retrofitting a version field onto documents
    /// already written to disk means guessing what an unversioned one meant — and `EditDocument` is
    /// `Codable` precisely so it can be persisted later (§8.8).
    var version: Int = EditDocument.currentVersion

    /// Only meaningful for a RAW source; ignored for standard images, which have no develop stage.
    var rawDevelop: RAWDevelopSettings = .neutral

    /// Ordered tone/colour stages. Order matters and duplicates are allowed — see `AdjustmentNode`.
    var adjustments: [AdjustmentNode] = []

    /// Which LUT, at what strength.
    var lut: LUTSettings = .none

    /// What the source image is, for the benefit of a V-Log LUT. `.auto` lets
    /// the detector decide; the other two are the user overruling it. Ignored
    /// entirely by display-input LUTs, which is every ordinary creative LUT.
    var sourceSpace: SourceSpace = .auto

    /// The version this build writes.
    static let currentVersion = 1

    init(
        version: Int = EditDocument.currentVersion,
        rawDevelop: RAWDevelopSettings = .neutral,
        adjustments: [AdjustmentNode] = [],
        lut: LUTSettings = .none,
        sourceSpace: SourceSpace = .auto
    ) {
        self.version = version
        self.rawDevelop = rawDevelop
        self.adjustments = adjustments
        self.lut = lut
        self.sourceSpace = sourceSpace
    }

    /// True when this document would leave the source untouched.
    var isIdentity: Bool {
        rawDevelop.isNeutral && adjustments.allSatisfy(\.isIdentity) && lut.isIdentity
    }

    /// What "the original" means for A/B comparison: **develop applied, nothing else**.
    ///
    /// `docs/PHASE2_SPEC.md` §8.5 asked whether the comparison baseline should be develop-applied or
    /// the decoder's neutral defaults, and recommended develop-applied — holding Space should show
    /// the same photograph without the *look*, not a different rendering of the negative. This
    /// implements that.
    ///
    /// It is invisible today, because nothing sets `rawDevelop` until the Step 10 inspector exists,
    /// and a neutral develop is exactly the plain decode. It becomes load-bearing the moment that
    /// inspector ships, which is why it is decided here rather than then.
    ///
    /// Sharing `rawDevelop` with the full document is also what keeps the A/B swap cheap: the
    /// engine's developed-source memo is keyed on it, so both sides of the comparison hit the same
    /// entry instead of re-developing the RAW on every Space press.
    var originalForComparison: EditDocument {
        EditDocument(version: version, rawDevelop: rawDevelop, adjustments: [], lut: .none,
                     sourceSpace: sourceSpace)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case version, rawDevelop, adjustments, lut, sourceSpace
    }

    /// Decoded field by field rather than by synthesis, for two reasons.
    ///
    /// Synthesized `Decodable` ignores property defaults: a document missing any key would fail
    /// outright, so adding a field in v2 would break v1 documents. `decodeIfPresent` makes an absent
    /// field mean "the default", which is what every added field will want.
    ///
    /// And a document from a *newer* schema is rejected rather than silently narrowed. Loading a v2
    /// document into a v1 build would drop whatever v2 added, and the next save would write that loss
    /// back to disk. Refusing to open it is recoverable; quietly discarding an edit is not.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        guard version <= Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Edit was saved by a newer version of LUTzy (schema \(version); this build reads \(Self.currentVersion))."
            )
        }
        self.version = version
        self.rawDevelop = try container.decodeIfPresent(RAWDevelopSettings.self, forKey: .rawDevelop) ?? .neutral
        self.adjustments = try container.decodeIfPresent([AdjustmentNode].self, forKey: .adjustments) ?? []
        self.lut = try container.decodeIfPresent(LUTSettings.self, forKey: .lut) ?? .none
        self.sourceSpace = try container.decodeIfPresent(SourceSpace.self, forKey: .sourceSpace) ?? .auto
    }
}
