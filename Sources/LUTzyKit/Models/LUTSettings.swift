import Foundation

/// A stable reference to a LUT, stored in an `EditDocument` in place of the LUT itself.
///
/// `CubeLUT` holds a non-`Codable` float table that runs to megabytes at 65³. Embedding one would
/// make `EditDocument` non-`Codable` and would copy the whole table into every undo snapshot, so the
/// document stores an ID and resolves it against the library.
///
/// Existing path strings remain decodable for migration. New on-disk records
/// use `record://<uuid>` and resolve through `LUTCatalog`; unsaved LUTs use
/// `derived://…` until save adopts a durable record.
struct LUTID: Codable, Sendable, Hashable {
    let raw: String

    init(raw: String) {
        self.raw = raw
    }

    init(recordUUID: UUID) {
        self.raw = "record://\(recordUUID.uuidString.lowercased())"
    }

    /// The durable record when present, otherwise the legacy path/transient ID.
    init(_ lut: CubeLUT) {
        self = lut.recordID ?? LUTID(raw: lut.id)
    }

    /// True for a LUT that exists only in memory (a freshly derived one, before the user saves it).
    ///
    /// Its ID carries a `UUID`, so it *cannot* resolve after a relaunch. Persisting such a document
    /// is not wrong, but the LUT reference in it is expected to dangle; anything that writes
    /// documents to disk should decide deliberately what to do here rather than discover it later.
    var isDerived: Bool { raw.hasPrefix("derived://") }
    var isRecord: Bool { raw.hasPrefix("record://") }

    // Encoded as a bare string rather than `{"raw": "…"}`. This is a newtype over the path, and the
    // JSON should read like one.
    init(from decoder: Decoder) throws {
        self.raw = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}

extension CubeLUT {
    /// This LUT's document-level identity.
    var lutID: LUTID { LUTID(self) }
}

extension Sequence where Element == CubeLUT {
    /// Resolve a document's `LUTID` against a scanned library.
    ///
    /// Deliberately a plain lookup over the scan results rather than a cached map: the library is
    /// re-scanned often enough that a cache would be the thing to go stale, and the ID is
    /// deterministic precisely so a fresh scan can answer this.
    func first(matching id: LUTID) -> CubeLUT? {
        first { $0.lutID == id || $0.id == id.raw }
    }
}

/// The LUT half of an `EditDocument`: which LUT, and how much of it.
struct LUTSettings: Codable, Sendable, Equatable {
    /// `nil` means no LUT — the document passes colour through untouched.
    var lutID: LUTID?
    /// 0…1. Values outside that range are clamped where the LUT is applied
    /// (`CubeLUT.apply(to:intensity:)`), so a corrupt document cannot produce a nonsense render.
    var intensity: Double = 1.0

    /// No LUT. The starting state of every document.
    static let none = LUTSettings(lutID: nil, intensity: 1.0)

    /// True when this contributes nothing to the render — no LUT set, or a LUT at zero strength.
    var isIdentity: Bool { lutID == nil || intensity <= 0 }
}
