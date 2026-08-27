import Foundation
import CoreImage
import CryptoKit

/// What a LUT expects to be fed.
///
/// LUTzy has always assumed a LUT maps a finished picture to a finished
/// picture (`.display`). A camera-look LUT built for a LUMIX S9 instead expects
/// **V-Log / V-Gamut** — scene-referred log — and applying it to an ordinary
/// sRGB image is the single most common way to get a washed-out, wrong result.
/// Recording which one a LUT wants lets the pipeline convert the source into
/// that space first, rather than feeding it the wrong thing.
enum LUTInputSpace: String, Codable, Sendable, Equatable, CaseIterable {
    case display   // Rec.709 / sRGB finished picture — LUTzy's original assumption
    case vlog      // Panasonic V-Log / V-Gamut, e.g. a LUMIX Real Time LUT

    /// The `#LUMIXPHOTOSTYLE` tag the LUMIX S9 reads, mapped to a space.
    /// The camera's own rule: absent or unrecognised means V-Log.
    static func fromPhotoStyleTag(_ tag: String) -> LUTInputSpace {
        tag.uppercased() == "VLOG" ? .vlog : .display
    }
}

/// Parses a .cube 3D LUT file and creates a CIFilter for GPU-accelerated color grading.
struct CubeLUT: Identifiable, Hashable, Sendable {
    let id: String          // full file path (or a synthetic id for in-memory LUTs)
    let name: String        // display name (cleaned)
    let category: String    // folder name or "General"
    let url: URL
    let size: Int
    let inputSpace: LUTInputSpace   // what this LUT expects to be fed
    let photoStyleTag: String?      // the raw #LUMIXPHOTOSTYLE tag, if any
    /// Assigned by `LUTCatalog` after a scan. Nil for raw parser results and
    /// in-memory derived LUTs.
    let recordID: LUTRecordID?
    /// File-backed LUTs keep only their parsed header and stable content hash.
    /// The large RGBA float table is reconstructed on demand, then owned by
    /// Core Image's bounded filter cache instead of every library row.
    private let embeddedTableData: Data?
    private let storedContentHash: String

    // MARK: - Hashable

    static func == (lhs: CubeLUT, rhs: CubeLUT) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - In-memory init (used by RecipeExtractor before the user saves)

    /// Build a CubeLUT directly from cube values, without touching disk.
    /// `cube` must be `size * size * size` SIMD3<Float> entries with R varying
    /// fastest, then G, then B (same ordering as the .cube file format).
    init(
        cube: [SIMD3<Float>],
        size: Int,
        name: String,
        category: String = "Derived",
        sourceURL: URL? = nil,
        inputSpace: LUTInputSpace = .display
    ) {
        precondition(cube.count == size * size * size, "cube count must equal size^3")
        self.size = size
        self.name = name
        self.category = category
        // An edited V-Log look is still a V-Log look: baking adjustments into
        // it changes what it produces, never what it expects. Defaulting to
        // display and letting the editor pass `.vlog` keeps the recipe
        // extractor's behaviour unchanged.
        self.inputSpace = inputSpace
        self.photoStyleTag = inputSpace == .vlog ? "VLOG" : nil
        self.recordID = nil
        self.url = sourceURL ?? URL(fileURLWithPath: "/dev/null")

        var floats = [Float]()
        floats.reserveCapacity(cube.count * 4)
        for v in cube {
            floats.append(v.x)
            floats.append(v.y)
            floats.append(v.z)
            floats.append(1.0)
        }
        let table = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        self.embeddedTableData = table
        self.storedContentHash = Self.digest(table)
        // The table has to be built before the ID, because the ID is made from it.
        self.id = sourceURL?.path ?? Self.derivedID(name: name, table: table)
    }

    /// The identity of a LUT that exists only in memory: `derived://<name>/<hash of the table>`.
    ///
    /// **Content-derived, not random.** `docs/PHASE2_SPEC.md` §4.3 rules out a `UUID` because it
    /// mints fresh identity on construction, and that argument does not stop at the library scan it
    /// is written about — a `UUID()` here did the same thing one level down. Hashing the table means
    /// the same cube is always the same LUT, which is also the honest answer: two cubes with the same
    /// contents render identically and are interchangeable in `LUTFilterCache`.
    ///
    /// **`CryptoKit`, not `Hasher`.** Swift's `Hasher` is seeded per process, so an ID built from it
    /// would be stable within a launch and silently different across launches — the failure mode
    /// §4.3 exists to prevent, and one no single-process test can see.
    /// `LUTIDTests.testTheDerivedIDIsStableAcrossProcesses` pins a literal for that reason.
    ///
    /// The name is included because it identifies the source pair a derive came from, and two
    /// unrelated derives should not share a registry slot on the strength of a coincidence.
    ///
    /// 64 bits of the digest. This distinguishes the handful of derives in one session, not the
    /// world's LUTs.
    private static func derivedID(name: String, table: Data) -> String {
        let digest = SHA256.hash(data: table)
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "derived://\(name)/\(hex)"
    }

    /// Decide what a LUT expects, tag first, then a name hint, else display.
    ///
    /// The tag is authoritative when present. Failing that, a name that says
    /// "vlog"/"v-log" is taken at its word; anything else stays `.display`, so
    /// an ordinary creative LUT behaves exactly as it did before this existed.
    static func resolveInputSpace(photoStyle: String?, name: String) -> LUTInputSpace {
        if let tag = photoStyle {
            return LUTInputSpace.fromPhotoStyleTag(tag)
        }
        let lowered = name.lowercased()
        if lowered.contains("vlog") || lowered.contains("v-log") {
            return .vlog
        }
        return .display
    }

    // MARK: - Parsing

    init(url: URL, category: String = "General", retainTableData: Bool = false) throws {
        self.url = url
        self.id = url.path
        self.category = category

        let rawName = url.deletingPathExtension().lastPathComponent
        // Clean common suffixes
        var cleaned = rawName
        for suffix in ["_33_Rec709", "_65_Rec709", "_Rec709"] {
            cleaned = cleaned.replacingOccurrences(of: suffix, with: "")
        }
        self.name = cleaned

        let sourceData = try Data(contentsOf: url)
        guard let content = String(data: sourceData, encoding: .utf8)
                ?? String(data: sourceData, encoding: .windowsCP1252)
                ?? String(data: sourceData, encoding: .isoLatin1)
        else {
            throw LUTError.invalidFormat("Unsupported text encoding")
        }
        let lines = content.components(separatedBy: .newlines)

        var photoStyle: String? = nil
        var lutSize = 0
        var domainMin: SIMD3<Float> = .zero
        var domainMax: SIMD3<Float> = .one
        var rows: [(Float, Float, Float)] = []

        for line in lines {
            if Task.isCancelled { throw CancellationError() }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                // #LUMIXPHOTOSTYLE <TAG> declares the base Photo Style, i.e. the
                // input the LUT was authored for. Every other comment is skipped
                // exactly as before.
                let upper = trimmed.uppercased()
                if upper.hasPrefix("#LUMIXPHOTOSTYLE") {
                    photoStyle = trimmed
                        .dropFirst("#LUMIXPHOTOSTYLE".count)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                continue
            }

            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
                guard parts.count >= 2, let s = Int(parts[1]) else { continue }
                lutSize = s
            } else if trimmed.hasPrefix("DOMAIN_MIN") {
                let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).compactMap { Float($0) }
                if parts.count >= 3 { domainMin = SIMD3(parts[0], parts[1], parts[2]) }
            } else if trimmed.hasPrefix("DOMAIN_MAX") {
                let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).compactMap { Float($0) }
                if parts.count >= 3 { domainMax = SIMD3(parts[0], parts[1], parts[2]) }
            } else if !trimmed.hasPrefix("TITLE") {
                let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
                if parts.count == 3,
                   let r = Float(parts[0]),
                   let g = Float(parts[1]),
                   let b = Float(parts[2]) {
                    rows.append((r, g, b))
                }
            }
        }

        guard lutSize > 0 else {
            throw LUTError.invalidFormat("LUT_3D_SIZE not found")
        }
        // CIColorCube only accepts dimensions 2...128. Reject unsupported or
        // hostile headers before multiplying so malformed input cannot be
        // reported as renderable or trigger an integer-overflow trap.
        guard (2...128).contains(lutSize) else {
            throw LUTError.invalidFormat("Unsupported LUT_3D_SIZE \(lutSize); expected 2...128")
        }
        let expected = lutSize * lutSize * lutSize
        guard rows.count == expected else {
            throw LUTError.invalidFormat("Expected \(expected) entries, got \(rows.count)")
        }

        self.size = lutSize
        self.photoStyleTag = photoStyle
        self.inputSpace = Self.resolveInputSpace(photoStyle: photoStyle, name: cleaned)
        self.recordID = nil

        // Build Core Image color cube data: RGBA float32, R varies fastest.
        // .cube format: R fastest, G middle, B slowest — same as Core Image expects.
        // Normalize from domain to [0,1] if needed. A degenerate domain (min ==
        // max on any axis) would divide by zero and fill the table with NaN, so
        // treat that axis as the default 0…1 range instead.
        var scale = domainMax - domainMin
        for axis in 0..<3 where !(scale[axis] > 0) {
            domainMin[axis] = 0
            scale[axis] = 1
        }
        var floats = [Float]()
        floats.reserveCapacity(expected * 4)

        for row in rows {
            let r = (row.0 - domainMin.x) / scale.x
            let g = (row.1 - domainMin.y) / scale.y
            let b = (row.2 - domainMin.z) / scale.z
            floats.append(r)
            floats.append(g)
            floats.append(b)
            floats.append(1.0) // alpha
        }

        let tableData = floats.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        self.storedContentHash = Self.digest(tableData)
        self.embeddedTableData = retainTableData ? tableData : nil
    }

    /// Header-only construction for a file whose exact bytes were authenticated
    /// against a curated sidecar. This preserves the normal render contract
    /// while avoiding a full text parse during discovery.
    init(url: URL, category: String, knownContentHash: String) throws {
        self.url = url
        self.id = url.path
        self.category = category
        let rawName = url.deletingPathExtension().lastPathComponent
        var cleaned = rawName
        for suffix in ["_33_Rec709", "_65_Rec709", "_Rec709"] {
            cleaned = cleaned.replacingOccurrences(of: suffix, with: "")
        }
        self.name = cleaned

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 65_536) ?? Data()
        guard let content = String(data: prefix, encoding: .utf8)
                ?? String(data: prefix, encoding: .windowsCP1252)
                ?? String(data: prefix, encoding: .isoLatin1)
        else { throw LUTError.invalidFormat("Unsupported text encoding") }

        var photoStyle: String?
        var lutSize: Int?
        for line in content.components(separatedBy: .newlines) {
            if Task.isCancelled { throw CancellationError() }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let upper = trimmed.uppercased()
            if upper.hasPrefix("#LUMIXPHOTOSTYLE") {
                photoStyle = trimmed.dropFirst("#LUMIXPHOTOSTYLE".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
                if parts.count >= 2 { lutSize = Int(parts[1]) }
            }
            if photoStyle != nil, lutSize != nil { break }
        }
        guard let lutSize, (2...128).contains(lutSize) else {
            throw LUTError.invalidFormat("LUT_3D_SIZE not found in header")
        }
        self.size = lutSize
        self.photoStyleTag = photoStyle
        self.inputSpace = Self.resolveInputSpace(photoStyle: photoStyle, name: cleaned)
        self.recordID = nil
        self.embeddedTableData = nil
        self.storedContentHash = knownContentHash.lowercased()
    }

    /// Stream the raw file digest so authenticating a 1.5 GB corpus never
    /// requires holding that corpus (or even one large text LUT) in memory.
    static func fileSHA256(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if Task.isCancelled { throw CancellationError() }
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Copy a parsed LUT while attaching the catalog identity. The render
    /// table is immutable and shared by value through `Data`'s copy-on-write
    /// storage, so this does not parse the file twice.
    func withRecordID(_ recordID: LUTRecordID) -> CubeLUT {
        CubeLUT(
            id: id, name: name, category: category, url: url, size: size,
            inputSpace: inputSpace, photoStyleTag: photoStyleTag,
            recordID: recordID,
            embeddedTableData: embeddedTableData,
            storedContentHash: storedContentHash
        )
    }

    private init(
        id: String,
        name: String,
        category: String,
        url: URL,
        size: Int,
        inputSpace: LUTInputSpace,
        photoStyleTag: String?,
        recordID: LUTRecordID?,
        embeddedTableData: Data?,
        storedContentHash: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.url = url
        self.size = size
        self.inputSpace = inputSpace
        self.photoStyleTag = photoStyleTag
        self.recordID = recordID
        self.embeddedTableData = embeddedTableData
        self.storedContentHash = storedContentHash
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Reparse only when a caller actually needs pixels. Keeping this local to
    /// the operation means scanning 1,600 LUTs does not pin ~826 MiB of cube
    /// tables in `allLUTs`.
    private func resolvedTableData() -> Data? {
        if let embeddedTableData { return embeddedTableData }
        return try? CubeLUT(
            url: url,
            category: category,
            retainTableData: true
        ).embeddedTableData
    }

    /// Test/diagnostic seam for the library's memory contract.
    var retainsTableData: Bool { embeddedTableData != nil }

    // MARK: - Sampling

    /// Sample the cube at flat RGB triplets, tetrahedrally.
    ///
    /// For measurement, not for rendering — Core Image owns the render path and
    /// interpolates trilinearly. Tetrahedral here because `lutcraft` measures
    /// tetrahedrally, and a tag that disagreed with the offline tools by an
    /// interpolation difference would be a tag nobody could reproduce.
    func sample(_ points: [Float]) -> [Float] {
        guard size > 1, points.count >= 3 else { return points }
        guard let tableData = resolvedTableData() else { return points }
        let n = size
        let maxIndex = Float(n - 1)
        var out = [Float](repeating: 0, count: points.count - points.count % 3)

        tableData.withUnsafeBytes { raw in
            let table = raw.bindMemory(to: Float.self)
            // R varies fastest — the order the table was built in.
            func corner(_ r: Int, _ g: Int, _ b: Int, _ channel: Int) -> Float {
                table[(((b * n) + g) * n + r) * 4 + channel]
            }

            for base in stride(from: 0, to: out.count, by: 3) {
                var lower = [0, 0, 0]
                var frac = [Float](repeating: 0, count: 3)
                for axis in 0..<3 {
                    let scaled = min(max(points[base + axis], 0), 1) * maxIndex
                    let floored = min(Int(scaled), n - 2)
                    lower[axis] = floored
                    frac[axis] = scaled - Float(floored)
                }
                let dr = frac[0], dg = frac[1], db = frac[2]

                // The six tetrahedra of the unit cube, chosen by the ordering of
                // the fractional coordinates. Each is walked as three steps from
                // the near corner to the far one.
                let first: [Int]
                let second: [Int]
                if dr >= dg, dg >= db            { first = [1, 0, 0]; second = [1, 1, 0] }
                else if dr >= dg, dr >= db       { first = [1, 0, 0]; second = [1, 0, 1] }
                else if dr >= dg                 { first = [0, 0, 1]; second = [1, 0, 1] }
                else if dr >= db                 { first = [0, 1, 0]; second = [1, 1, 0] }
                else if dg >= db                 { first = [0, 1, 0]; second = [0, 1, 1] }
                else                             { first = [0, 0, 1]; second = [0, 1, 1] }

                let axis1 = first.firstIndex(of: 1)!
                let axis2 = (0..<3).first { second[$0] - first[$0] == 1 }!
                let axis3 = 3 - axis1 - axis2

                for channel in 0..<3 {
                    let c000 = corner(lower[0], lower[1], lower[2], channel)
                    let c111 = corner(lower[0] + 1, lower[1] + 1, lower[2] + 1, channel)
                    let c1 = corner(lower[0] + first[0], lower[1] + first[1], lower[2] + first[2], channel)
                    let c2 = corner(lower[0] + second[0], lower[1] + second[1], lower[2] + second[2], channel)
                    out[base + channel] = c000
                        + frac[axis1] * (c1 - c000)
                        + frac[axis2] * (c2 - c1)
                        + frac[axis3] * (c111 - c2)
                }
            }
        }
        return out
    }

    /// The largest channel spread anywhere in the table. Zero means the LUT is
    /// monochrome — it cannot produce a coloured pixel from any input.
    var monoSpread: Double {
        guard let tableData = resolvedTableData() else { return 0 }
        return tableData.withUnsafeBytes { raw in
            let table = raw.bindMemory(to: Float.self)
            var worst: Float = 0
            for entry in stride(from: 0, to: table.count, by: 4) {
                let r = table[entry], g = table[entry + 1], b = table[entry + 2]
                worst = Swift.max(worst, Swift.max(r, Swift.max(g, b)) - Swift.min(r, Swift.min(g, b)))
            }
            return Double(worst)
        }
    }

    /// A stable identity for the *contents* of a LUT, so tags survive a file
    /// being renamed or moved and follow a duplicate to its copy.
    var contentHash: String {
        storedContentHash
    }

    // MARK: - Inspection

    /// The flattened RGBA float table handed to Core Image, as floats.
    ///
    /// Exists for tests: rendering through Core Image clamps NaN to 0, so a
    /// corrupt table is invisible from the output side and has to be inspected
    /// directly.
    var tableFloats: [Float] {
        guard let tableData = resolvedTableData() else { return [] }
        return tableData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    // MARK: - Core Image Filter

    /// Creates a CIColorCube filter configured with this LUT.
    ///
    /// `space` is the **LUT interpolation space** — one half of the colour seam. It must stay in
    /// lockstep with the output encoding space; both default to `WorkingSpace.current` so they cannot
    /// drift apart. See `WorkingSpace`.
    func makeFilter(space: WorkingSpace = .current) -> CIFilter? {
        guard let tableData = resolvedTableData() else { return nil }
        // A V-Log LUT is indexed with code values the adapter produced, so it
        // uses the colour-space-free cube: `CIColorCubeWithColorSpace` would
        // convert those codes into its space first and index the wrong entry.
        // Every other LUT keeps the managed path exactly as before.
        if inputSpace == .vlog {
            guard let filter = CIFilter(name: "CIColorCube") else { return nil }
            filter.setValue(size, forKey: "inputCubeDimension")
            filter.setValue(tableData as NSData, forKey: "inputCubeData")
            return filter
        }
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
        filter.setValue(size, forKey: "inputCubeDimension")
        filter.setValue(tableData as NSData, forKey: "inputCubeData")
        filter.setValue(space.cgColorSpace, forKey: "inputColorSpace")
        return filter
    }

    /// Apply this LUT to a CIImage and return the result.
    func apply(to image: CIImage, space: WorkingSpace = .current) -> CIImage? {
        guard let filter = makeFilter(space: space) else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage
    }

    /// Apply this LUT at a given strength and return the result.
    ///
    /// `intensity` is clamped to 0...1: `1` is the full LUT, `0` is the
    /// untouched original, and values in between crossfade the graded result
    /// back toward the original via `CIDissolveTransition`. The graded image
    /// and the source share the same extent (a color cube is a per-pixel
    /// remap), so the dissolve is a clean opacity blend.
    ///
    /// Note the crossfade happens in the `CIContext`'s working space (≈ linear light), **not** in
    /// `space` — that argument governs cube interpolation only. Measured: a to-black LUT over white
    /// reads 188 at intensity 0.5, where a perceptual mix would read ~128. See `docs/PHASE2_SPEC.md`
    /// §8.1; changing it later is a visible look change for every sub-100% render.
    func apply(to image: CIImage, intensity: Double, space: WorkingSpace = .current) -> CIImage? {
        let t = max(0, min(1, intensity))
        // Build nothing when the LUT contributes nothing — a 65³ cube is ~4.4 MB to hand over.
        if t <= 0 { return image }
        return apply(to: image, intensity: t, using: makeFilter(space: space))
    }

    /// The shared body of the two `apply` overloads, taking a cube filter rather than making one.
    ///
    /// Exists so `RenderPipeline` can pass a filter from `LUTFilterCache` without a second copy of the
    /// dissolve logic. Two implementations of a crossfade would be two things to keep in step, and
    /// §8.1 of the spec is explicit that the blend's behaviour is shipping behaviour — a divergence
    /// here would be a visible look change on one path only.
    func apply(to image: CIImage, intensity: Double, using cubeFilter: CIFilter?) -> CIImage? {
        let t = max(0, min(1, intensity))
        if t <= 0 { return image }
        guard let cubeFilter else { return nil }

        cubeFilter.setValue(image, forKey: kCIInputImageKey)
        guard let graded = cubeFilter.outputImage else { return nil }
        if t >= 1 { return graded }

        guard let mix = CIFilter(name: "CIDissolveTransition") else { return graded }
        mix.setValue(image, forKey: kCIInputImageKey)
        mix.setValue(graded, forKey: kCIInputTargetImageKey)
        mix.setValue(t, forKey: kCIInputTimeKey)
        return mix.outputImage ?? graded
    }

    // MARK: - Writing

    /// Serialize a cube to .cube text format. Inverse of the parser above.
    /// Index ordering: R fastest, G middle, B slowest.
    static func cubeFileContents(
        cube: [SIMD3<Float>],
        size: Int,
        title: String
    ) -> String {
        precondition(cube.count == size * size * size, "cube count must equal size^3")
        var lines: [String] = []
        lines.reserveCapacity(cube.count + 6)
        lines.append("# Generated by LUTzy")
        lines.append("TITLE \"\(title)\"")
        lines.append("LUT_3D_SIZE \(size)")
        lines.append("DOMAIN_MIN 0.0 0.0 0.0")
        lines.append("DOMAIN_MAX 1.0 1.0 1.0")
        for v in cube {
            let r = max(0, min(1, v.x))
            let g = max(0, min(1, v.y))
            let b = max(0, min(1, v.z))
            lines.append(String(format: "%.6f %.6f %.6f", r, g, b))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Write a cube to disk in .cube format.
    static func write(
        cube: [SIMD3<Float>],
        size: Int,
        title: String,
        to url: URL
    ) throws {
        let text = cubeFileContents(cube: cube, size: size, title: title)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Errors

enum LUTError: LocalizedError, Sendable {
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): return "Invalid .cube file: \(msg)"
        }
    }
}
