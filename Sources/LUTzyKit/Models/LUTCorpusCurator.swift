import Foundation
import CryptoKit

/// Deterministically builds a repository-local corpus from already classified
/// candidates. Source discovery and brand inference belong to the CLI; this
/// core owns the safety-critical parse, dedupe, copy, and manifest transaction.
public enum LUTCorpusCurator {
    public struct SourceDefinition: Sendable, Equatable {
        public let id: String
        public let label: String
        public let description: String
        public let reference: String?
        public let license: String

        public init(
            id: String, label: String, description: String,
            reference: String?, license: String
        ) {
            self.id = id
            self.label = label
            self.description = description
            self.reference = reference
            self.license = license
        }
    }

    public struct Candidate: Sendable, Equatable {
        public let url: URL
        public let sourceID: String
        public let sourcePath: String
        public let destinationRelativePath: String
        public let brand: String
        public let inputProfile: String
        public let tags: [String]
        public let priority: Int

        public init(
            url: URL, sourceID: String, sourcePath: String,
            destinationRelativePath: String, brand: String,
            inputProfile: String, tags: [String], priority: Int
        ) {
            self.url = url
            self.sourceID = sourceID
            self.sourcePath = sourcePath
            self.destinationRelativePath = destinationRelativePath
            self.brand = brand
            self.inputProfile = inputProfile
            self.tags = tags
            self.priority = priority
        }
    }

    public struct Result: Sendable, Equatable {
        public let active: Int
        public let duplicates: Int
        public let unsupported: Int
    }

    public struct Verification: Sendable, Equatable {
        public let active: Int
        public let profiles: [String: Int]
    }

    public enum CuratorError: LocalizedError {
        case outputExists(URL)
        case missingSource(String)
        case missingCandidate(URL)
        case invalidRelativePath(String)
        case verificationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .outputExists(let url): return "Curated LUT output already exists at \(url.path)."
            case .missingSource(let id): return "No source definition for \(id)."
            case .missingCandidate(let url): return "Missing LUT candidate at \(url.path)."
            case .invalidRelativePath(let path): return "Unsafe LUT destination path: \(path)."
            case .verificationFailed(let detail): return "Curated corpus verification failed: \(detail)"
            }
        }
    }

    /// Verify the committed sidecar against the exact bytes the application
    /// will scan. This is intentionally independent from curation so CI or a
    /// future Git/LFS workflow can audit an existing corpus without rebuilding.
    public static func verify(outputRoot: URL) throws -> Verification {
        let activeRoot = outputRoot.appendingPathComponent("LUTs", isDirectory: true)
        let manifest = try CuratedLUTManifest.load(
            from: activeRoot.appendingPathComponent(CuratedLUTManifest.fileName)
        )
        let metadata = manifest.metadataByFingerprint
        var fingerprints: Set<String> = []
        var profiles: [String: Int] = [:]
        for entry in manifest.entries {
            let file = activeRoot.appendingPathComponent(entry.relativePath)
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw CuratorError.verificationFailed("missing \(entry.relativePath)")
            }
            let lut = try CubeLUT(url: file)
            guard lut.contentHash == entry.sha256.lowercased() else {
                throw CuratorError.verificationFailed("fingerprint mismatch for \(entry.relativePath)")
            }
            if let expectedFileHash = entry.fileSHA256,
               try CubeLUT.fileSHA256(at: file) != expectedFileHash.lowercased() {
                throw CuratorError.verificationFailed("file-byte mismatch for \(entry.relativePath)")
            }
            guard fingerprints.insert(entry.sha256.lowercased()).inserted else {
                throw CuratorError.verificationFailed("duplicate fingerprint \(entry.sha256)")
            }
            guard let seeded = metadata[entry.sha256.lowercased()],
                  seeded.origin != .unknown,
                  seeded.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  seeded.inputProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else {
                throw CuratorError.verificationFailed("incomplete metadata for \(entry.relativePath)")
            }
            profiles[seeded.inputProfile, default: 0] += 1
        }

        guard let enumerator = FileManager.default.enumerator(
            at: activeRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { throw CuratorError.verificationFailed("cannot enumerate LUTs") }
        var activeFiles = 0
        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension.lowercased() == "cube" { activeFiles += 1 }
        }
        guard activeFiles == manifest.entries.count else {
            throw CuratorError.verificationFailed(
                "manifest has \(manifest.entries.count) entries but disk has \(activeFiles) CUBE files"
            )
        }
        return Verification(active: activeFiles, profiles: profiles)
    }

    public static func curate(
        sources: [SourceDefinition],
        candidates: [Candidate],
        outputRoot: URL
    ) throws -> Result {
        let fm = FileManager.default
        guard fm.fileExists(atPath: outputRoot.path) == false else {
            throw CuratorError.outputExists(outputRoot)
        }
        let sourceMap = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let staging = outputRoot.deletingLastPathComponent().appendingPathComponent(
            ".\(outputRoot.lastPathComponent).curating-\(UUID().uuidString)",
            isDirectory: true
        )
        var completed = false
        defer { if completed == false { try? fm.removeItem(at: staging) } }

        let activeRoot = staging.appendingPathComponent("LUTs", isDirectory: true)
        let unsupportedRoot = staging.appendingPathComponent("Unsupported", isDirectory: true)
        try fm.createDirectory(at: activeRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: unsupportedRoot, withIntermediateDirectories: true)

        var entries: [CuratedLUTManifest.Entry] = []
        var duplicates: [CuratedLUTManifest.Duplicate] = []
        var unsupported: [CuratedLUTManifest.Unsupported] = []
        var canonicalByFingerprint: [String: String] = [:]
        var activeDestinations: Set<String> = []
        var unsupportedDestinations: Set<String> = []

        let ordered = candidates.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.sourceID != $1.sourceID { return $0.sourceID < $1.sourceID }
            return $0.sourcePath.localizedStandardCompare($1.sourcePath) == .orderedAscending
        }

        for candidate in ordered {
            guard sourceMap[candidate.sourceID] != nil else {
                throw CuratorError.missingSource(candidate.sourceID)
            }
            guard fm.fileExists(atPath: candidate.url.path) else {
                throw CuratorError.missingCandidate(candidate.url)
            }
            let requestedPath = try safeRelativePath(candidate.destinationRelativePath)

            do {
                let lut = try CubeLUT(url: candidate.url)
                if let canonical = canonicalByFingerprint[lut.contentHash] {
                    duplicates.append(.init(
                        sourcePath: candidate.sourcePath,
                        canonicalRelativePath: canonical,
                        sha256: lut.contentHash
                    ))
                    continue
                }

                let relative = uniqueRelativePath(
                    requestedPath, fingerprint: lut.contentHash,
                    used: &activeDestinations
                )
                let destination = activeRoot.appendingPathComponent(relative)
                try copy(candidate.url, to: destination)
                canonicalByFingerprint[lut.contentHash] = relative
                entries.append(.init(
                    relativePath: relative,
                    sha256: lut.contentHash,
                    fileSHA256: try CubeLUT.fileSHA256(at: candidate.url),
                    brand: candidate.brand,
                    inputProfile: candidate.inputProfile,
                    tags: Array(Set(candidate.tags.filter {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                            && $0.hasPrefix("input:") == false
                    })).sorted(),
                    sourceID: candidate.sourceID,
                    description: nil
                ))
            } catch {
                let relative = uniqueRelativePath(
                    requestedPath,
                    fingerprint: stablePathFingerprint(candidate.sourcePath),
                    used: &unsupportedDestinations
                )
                let destination = unsupportedRoot.appendingPathComponent(relative)
                try copy(candidate.url, to: destination)
                unsupported.append(.init(
                    sourcePath: candidate.sourcePath,
                    reason: String(describing: error),
                    retainedRelativePath: "Unsupported/\(relative)"
                ))
            }
        }

        let manifestSources = Dictionary(uniqueKeysWithValues: sources.map { source in
            (source.id, CuratedLUTManifest.Source(
                label: source.label,
                description: source.description,
                reference: source.reference,
                license: source.license
            ))
        })
        let manifest = CuratedLUTManifest(
            version: CuratedLUTManifest.supportedVersion,
            sources: manifestSources,
            entries: entries.sorted { $0.relativePath < $1.relativePath },
            duplicates: duplicates.sorted { $0.sourcePath < $1.sourcePath },
            unsupported: unsupported.sorted { $0.sourcePath < $1.sourcePath }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(
            to: activeRoot.appendingPathComponent(CuratedLUTManifest.fileName),
            options: .atomic
        )
        try readme().write(
            to: staging.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try audit(
            sources: sources, entries: entries,
            duplicates: duplicates, unsupported: unsupported
        ).write(
            to: staging.appendingPathComponent("SOURCE_AUDIT.md"),
            atomically: true,
            encoding: .utf8
        )

        try fm.moveItem(at: staging, to: outputRoot)
        completed = true
        return Result(
            active: entries.count,
            duplicates: duplicates.count,
            unsupported: unsupported.count
        )
    }

    private static func safeRelativePath(_ raw: String) throws -> String {
        let cleaned = raw.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = cleaned.split(separator: "/", omittingEmptySubsequences: true)
        guard cleaned.isEmpty == false,
              raw.hasPrefix("/") == false,
              components.contains(where: { $0 == ".." }) == false
        else { throw CuratorError.invalidRelativePath(raw) }
        return components.map(String.init).joined(separator: "/")
    }

    private static func uniqueRelativePath(
        _ requested: String, fingerprint: String, used: inout Set<String>
    ) -> String {
        guard used.insert(requested.lowercased()).inserted else {
            let ns = requested as NSString
            let stem = ns.deletingPathExtension
            let ext = ns.pathExtension
            let suffix = String(fingerprint.prefix(8))
            let candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            _ = used.insert(candidate.lowercased())
            return candidate
        }
        return requested
    }

    private static func copy(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func stablePathFingerprint(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func readme() -> String {
        """
        # Curated LUT Library

        `LUTs/` contains unique 3D LUTs that LUTzy can render. Files are grouped as
        `<Brand>/<Source>/…`; `.lutzy-library.json` carries Brand, Input Profile,
        Tags, Description, provenance, and content fingerprints without changing CUBE bytes.

        `Unsupported/` retains 1D or unreadable CUBE inputs outside the active scan root.
        See `SOURCE_AUDIT.md` before publishing. The initial local corpus can be large and
        may contain sources whose redistribution reference is still pending; adopt Git LFS
        and resolve every pending source before committing the binary corpus.

        Generated by `swift run lutcurate`. The curator never changes the supplied roots.
        """ + "\n"
    }

    private static func audit(
        sources: [SourceDefinition],
        entries: [CuratedLUTManifest.Entry],
        duplicates: [CuratedLUTManifest.Duplicate],
        unsupported: [CuratedLUTManifest.Unsupported]
    ) -> String {
        var lines = [
            "# LUT corpus source audit",
            "",
            "- Active renderable LUTs: \(entries.count)",
            "- Exact transform duplicates skipped: \(duplicates.count)",
            "- Unsupported inputs retained outside the active root: \(unsupported.count)",
            "",
            "## Input profiles",
            "",
        ]
        let profileCounts = Dictionary(grouping: entries, by: { entry in
            let value = entry.inputProfile?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value! : "Unknown"
        }).mapValues(\.count)
        for (profile, count) in profileCounts.sorted(by: { $0.key < $1.key }) {
            lines.append("- \(profile): \(count)")
        }
        lines += [
            "",
            "## Sources",
            "",
        ]
        for source in sources.sorted(by: { $0.id < $1.id }) {
            lines.append("### \(source.label) (`\(source.id)`)")
            lines.append("")
            lines.append(source.description)
            lines.append("")
            lines.append("- Reference: \(source.reference ?? "Pending user-supplied reference")")
            lines.append("- License/status: \(source.license)")
            lines.append("")
        }
        if duplicates.isEmpty == false {
            lines.append("## Skipped duplicate paths")
            lines.append("")
            for item in duplicates {
                lines.append("- `\(item.sourcePath)` → `LUTs/\(item.canonicalRelativePath)`")
            }
            lines.append("")
        }
        if unsupported.isEmpty == false {
            lines.append("## Unsupported inputs")
            lines.append("")
            for item in unsupported {
                lines.append("- `\(item.sourcePath)` → `\(item.retainedRelativePath ?? "not retained")`: \(item.reason)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
