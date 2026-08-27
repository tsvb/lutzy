import Foundation

/// Repository-side metadata that travels with a curated LUT corpus without
/// rewriting third-party CUBE bytes. The immutable content fingerprint is the
/// join, so import-time renames and later Manager moves do not break it.
struct CuratedLUTMetadata: Sendable, Equatable {
    let seedID: String
    let fingerprint: String
    let origin: LUTOrigin
    let inputProfile: String
    let tags: [String]
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
        let brand: String
        /// Human-facing encoded input contract (for example Panasonic V-Log,
        /// Sony S-Log3, or Unknown). Optional keeps version-1 sidecars written
        /// before this field was introduced decodable.
        let inputProfile: String?
        let tags: [String]
        let sourceID: String
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
        try manifest.validate()
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

    var metadataByFingerprint: [String: CuratedLUTMetadata] {
        var result: [String: CuratedLUTMetadata] = [:]
        for entry in entries.sorted(by: { $0.relativePath < $1.relativePath }) {
            guard result[entry.sha256] == nil, let source = sources[entry.sourceID] else { continue }
            let explicit = entry.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceDescription = source.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = explicit?.isEmpty == false ? explicit! : sourceDescription
            let input = entry.inputProfile?.trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = Array(Set(entry.tags.compactMap { value -> String? in
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleaned.isEmpty == false, cleaned.hasPrefix("input:") == false else { return nil }
                return cleaned
            })).sorted()
            result[entry.sha256] = CuratedLUTMetadata(
                seedID: "manifest-v\(version):\(entry.sha256)",
                fingerprint: entry.sha256,
                origin: .vendor(entry.brand.trimmingCharacters(in: .whitespacesAndNewlines)),
                inputProfile: input?.isEmpty == false ? input! : "Unknown",
                tags: tags,
                description: description
            )
        }
        return result
    }

    private func validate() throws {
        guard version == Self.supportedVersion else { throw ManifestError.unsupportedVersion(version) }
        var paths: Set<String> = []
        var fingerprints: Set<String> = []
        for entry in entries {
            let path = entry.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
            let brand = entry.brand.trimmingCharacters(in: .whitespacesAndNewlines)
            let hash = entry.sha256.lowercased()
            guard path.isEmpty == false,
                  path.hasPrefix("/") == false,
                  path.split(separator: "/").contains("..") == false,
                  brand.isEmpty == false,
                  hash.count == 64,
                  hash.allSatisfy({ $0.isHexDigit }),
                  paths.insert(path).inserted,
                  fingerprints.insert(hash).inserted
            else { throw ManifestError.invalidEntry(entry.relativePath) }
            guard sources[entry.sourceID] != nil else { throw ManifestError.missingSource(entry.sourceID) }
        }
    }
}
