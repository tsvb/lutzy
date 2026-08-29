import Foundation

/// Conservative, path-only input-profile inference shared by the curator and
/// its durable checks. Brand names by themselves are deliberately not treated
/// as input-profile evidence: a Fujifilm-look LUT can still consume V-Log.
public enum LUTInputProfileInference {
    public static func profile(relativePath: String) -> String {
        let path = relativePath.localizedLowercase
        let name = URL(fileURLWithPath: relativePath)
            .deletingPathExtension().lastPathComponent.localizedLowercase

        // Detect profiles whose tokens begin with `Log` before F-/S-/C-Log.
        // Creative names such as `Cliff-LogC4`, `Arrakis-LogC4`, and
        // `Gems-Log3G10` otherwise create false cross-boundary matches.
        if path.contains("log3g10") || path.contains("rg4") { return "RED Log3G10" }
        if path.contains("redlogfilm") || path.contains("rlf") { return "REDlogFilm" }
        if path.contains("logc4") || path.contains("log c4") { return "ARRI LogC4" }
        if path.contains("logc3") || path.contains("log c3") { return "ARRI LogC3" }
        if path.contains("arri logc") || name.hasPrefix("logc")
            || name.contains("-logc") || name.contains("_logc") || name.contains(" logc") {
            return "ARRI LogC"
        }
        if path.contains("flog2") || path.contains("f-log2") { return "Fujifilm F-Log2" }
        if path.contains("flog") || path.contains("f-log") { return "Fujifilm F-Log" }
        if path.contains("slog3") || path.contains("s-log3") || name.hasPrefix("sl3") { return "Sony S-Log3" }
        if path.contains("slog2") || path.contains("s-log2") { return "Sony S-Log2" }
        if path.contains("slog") || path.contains("s-log") { return "Sony S-Log" }
        if path.contains("canonlog3") || path.contains("canon log 3") || path.contains("c-log3") || path.contains("clog3") { return "Canon C-Log 3" }
        if path.contains("canonlog2") || path.contains("canon log 2") || path.contains("c-log2") || path.contains("clog2") { return "Canon C-Log 2" }
        if path.contains("canonlog") || path.contains("canon log") || path.contains("c-log") || path.contains("clog") { return "Canon C-Log" }
        if path.contains("d-log m") || path.contains("dlog-m") || path.contains("dlogm") { return "DJI D-Log M" }
        if path.contains("d-log") || path.contains("dlog") { return "DJI D-Log" }
        if path.contains("n-log") || path.contains("nlog") { return "Nikon N-Log" }
        if path.contains("v-log") || path.contains("vlog") { return "Panasonic V-Log" }
        if path.contains("blackmagic gen 5 film") { return "Blackmagic Film Gen 5" }
        if path.contains("bmdfilm") || path.contains("blackmagic") && path.contains(" film") { return "Blackmagic Film" }
        if path.contains("gplog") || path.contains("gp-log") { return "GoPro GP-Log" }
        if path.contains("protune") { return "GoPro Protune" }
        if path.contains("l-log") { return "Leica L-Log" }
        if path.contains("apple log") || path.contains("applelog") { return "Apple Log" }
        if name.hasPrefix("cineon") || name.contains("cineon to") { return "Cineon Log" }

        // A package-level folder is valid evidence even when its individual
        // filenames are creative look names with no profile token.
        if path.contains("rec.709 to color grading luts")
            || path.contains("rec709 to color grading luts") {
            return "Display / Rec.709"
        }

        // Only infer a display/linear profile from the source side of an
        // explicit transform name. A destination named Rec.709 proves nothing.
        if name.hasPrefix("rec.709 to") || name.hasPrefix("rec709 to")
            || name.hasPrefix("srgb to") || name.hasPrefix("gamma 2") {
            return "Display / Rec.709"
        }
        if name.hasPrefix("linear to") || name.hasPrefix("dci to") {
            return "Display / Linear"
        }
        return "Unknown"
    }
}

/// Repository-side metadata that travels with a curated LUT corpus without
/// rewriting third-party CUBE bytes. The immutable content fingerprint is the
/// join, so import-time renames and later Manager moves do not break it.
struct CuratedLUTMetadata: Sendable, Equatable {
    let seedID: String
    let fingerprint: String
    let origin: LUTOrigin
    /// Authored package/project provenance. Source is independent of Brand:
    /// two Fujifilm looks may come from Codex and Claude respectively.
    let sourceLabel: String
    let inputProfile: String
    let tags: [String]
    /// One measured visual family, seeded into a user-editable Collection.
    let visualCluster: LUTVisualCluster?
    let description: String
}

struct CuratedLUTManifest: Codable, Sendable, Equatable {
    static let fileName = ".lutzy-library.json"
    static let supportedVersion = 1

    struct Source: Codable, Sendable, Equatable {
        let label: String
        let description: String
        let reference: String?
        let license: String
    }

    struct Entry: Codable, Sendable, Equatable {
        let relativePath: String
        let sha256: String
        /// SHA-256 of the exact CUBE file bytes. Optional for old manifests;
        /// current manifests use it to validate a fast, header-only scan.
        let fileSHA256: String?
        let brand: String
        /// Human-facing encoded input contract (for example Panasonic V-Log,
        /// Sony S-Log3, or Unknown). Optional keeps version-1 sidecars written
        /// before this field was introduced decodable.
        let inputProfile: String?
        let tags: [String]
        let sourceID: String
        /// Optional keeps pre-clustering version-1 sidecars decodable.
        let visualCluster: String?
        let description: String?
    }

    struct Duplicate: Codable, Sendable, Equatable {
        let sourcePath: String
        let canonicalRelativePath: String
        let sha256: String
    }

    struct Unsupported: Codable, Sendable, Equatable {
        let sourcePath: String
        let reason: String
        let retainedRelativePath: String?
    }

    enum ManifestError: LocalizedError {
        case unsupportedVersion(Int)
        case invalidEntry(String)
        case missingSource(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return "Unsupported curated LUT manifest version \(version)."
            case .invalidEntry(let path):
                return "Invalid curated LUT manifest entry for \(path)."
            case .missingSource(let id):
                return "Curated LUT manifest references missing source \(id)."
            }
        }
    }

    let version: Int
    let sources: [String: Source]
    let entries: [Entry]
    let duplicates: [Duplicate]
    let unsupported: [Unsupported]

    static func load(from url: URL) throws -> CuratedLUTManifest {
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(CuratedLUTManifest.self, from: data)
        try manifest.validate(checkingClusterNames: true)
        return manifest
    }

    /// The one reader allowed to see a manifest whose recorded visual families
    /// predate the current rules: `LUTCorpusCurator.reclassify`, whose whole
    /// job is to replace them. Every other reader gets the strict `load`, so a
    /// stale family name still fails loudly everywhere it would be believed.
    static func loadIgnoringClusterNames(from url: URL) throws -> CuratedLUTManifest {
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(CuratedLUTManifest.self, from: data)
        try manifest.validate(checkingClusterNames: false)
        return manifest
    }

    /// First manifest in path order wins a fingerprint collision. A curated
    /// corpus already guarantees one active fingerprint; deterministic merge
    /// keeps a malformed extra package from making scan order observable.
    static func metadataUnder(_ root: URL) -> [String: CuratedLUTMetadata] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [:] }

        var urls: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == fileName { urls.append(url) }
        }

        var result: [String: CuratedLUTMetadata] = [:]
        for url in urls.sorted(by: { $0.path < $1.path }) {
            guard let manifest = try? load(from: url) else { continue }
            for (fingerprint, metadata) in manifest.metadataByFingerprint
                where result[fingerprint] == nil {
                result[fingerprint] = metadata
            }
        }
        return result
    }

    struct ScanHint: Sendable, Equatable {
        let fingerprint: String
        let fileSHA256: String
    }

    /// Resolve current sidecars to exact file paths. A hint is usable only
    /// when it carries the raw-byte digest added by the curator; older
    /// manifests safely fall back to a full parse.
    static func scanHintsUnder(_ root: URL) -> [String: ScanHint] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: []
        ) else { return [:] }
        var manifests: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == fileName { manifests.append(url) }
        }
        var result: [String: ScanHint] = [:]
        for url in manifests.sorted(by: { $0.path < $1.path }) {
            guard let manifest = try? load(from: url) else { continue }
            let base = url.deletingLastPathComponent()
            for entry in manifest.entries {
                guard let fileHash = entry.fileSHA256?.lowercased() else { continue }
                let path = base.appendingPathComponent(entry.relativePath)
                    .standardizedFileURL.resolvingSymlinksInPath().path
                result[path] = ScanHint(
                    fingerprint: entry.sha256.lowercased(), fileSHA256: fileHash
                )
            }
        }
        return result
    }

    var metadataByFingerprint: [String: CuratedLUTMetadata] {
        var result: [String: CuratedLUTMetadata] = [:]
        for entry in entries.sorted(by: { $0.relativePath < $1.relativePath }) {
            let fingerprint = entry.sha256.lowercased()
            guard result[fingerprint] == nil, let source = sources[entry.sourceID] else { continue }
            let explicit = entry.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceDescription = source.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = explicit?.isEmpty == false ? explicit! : sourceDescription
            let input = entry.inputProfile?.trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = Array(Set(entry.tags.compactMap { value -> String? in
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleaned.isEmpty == false, cleaned.hasPrefix("input:") == false else { return nil }
                return cleaned
            })).sorted()
            result[fingerprint] = CuratedLUTMetadata(
                seedID: "manifest-v\(version):\(fingerprint)",
                fingerprint: fingerprint,
                origin: .vendor(entry.brand.trimmingCharacters(in: .whitespacesAndNewlines)),
                sourceLabel: source.label.trimmingCharacters(in: .whitespacesAndNewlines),
                inputProfile: input?.isEmpty == false ? input! : "Unknown",
                tags: tags,
                visualCluster: entry.visualCluster.flatMap(LUTVisualCluster.init(rawValue:)),
                description: description
            )
        }
        return result
    }

    private func validate(checkingClusterNames: Bool) throws {
        guard version == Self.supportedVersion else { throw ManifestError.unsupportedVersion(version) }
        var paths: Set<String> = []
        var fingerprints: Set<String> = []
        for entry in entries {
            let path = entry.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
            let brand = entry.brand.trimmingCharacters(in: .whitespacesAndNewlines)
            let hash = entry.sha256.lowercased()
            let fileHash = entry.fileSHA256?.lowercased()
            guard path.isEmpty == false,
                  path.hasPrefix("/") == false,
                  path.split(separator: "/").contains("..") == false,
                  brand.isEmpty == false,
                  hash.count == 64,
                  hash.allSatisfy({ $0.isHexDigit }),
                  paths.insert(path).inserted,
                  fingerprints.insert(hash).inserted
            else { throw ManifestError.invalidEntry(entry.relativePath) }
            if let fileHash,
               fileHash.count != 64 || fileHash.allSatisfy({ $0.isHexDigit }) == false {
                throw ManifestError.invalidEntry(entry.relativePath)
            }
            guard sources[entry.sourceID] != nil else { throw ManifestError.missingSource(entry.sourceID) }
            if checkingClusterNames,
               let cluster = entry.visualCluster,
               LUTVisualCluster(rawValue: cluster) == nil {
                throw ManifestError.invalidEntry(entry.relativePath)
            }
        }
    }
}
