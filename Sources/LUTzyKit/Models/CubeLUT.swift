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
    private let tableData: Data  // flattened RGBARGBA... float32 for Core Image

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
        sourceURL: URL? = nil
    ) {
        precondition(cube.count == size * size * size, "cube count must equal size^3")
        self.size = size
        self.name = name
        self.category = category
        self.inputSpace = .display
        self.photoStyleTag = nil
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
        self.tableData = table
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

    init(url: URL, category: String = "General") throws {
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

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var photoStyle: String? = nil
        var lutSize = 0
        var domainMin: SIMD3<Float> = .zero
        var domainMax: SIMD3<Float> = .one
        var rows: [(Float, Float, Float)] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                // #LUMIXPHOTOSTYLE <TAG> declares the base Photo Style, i.e. the
                // input the LUT was authored for. Every other comment is skipped
                // exactly as before.
                let upper = trimmed.uppercased()
                if upper.hasPrefix("#LUMIXPHOTOSTYLE") {
                    photoStyle = trimmed
                        .dropFirst("#LUMIXPHOTOSTYLE".count)
                        .trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(separator: " ")
                guard parts.count >= 2, let s = Int(parts[1]) else { continue }
                lutSize = s
            } else if trimmed.hasPrefix("DOMAIN_MIN") {
                let parts = trimmed.split(separator: " ").compactMap { Float($0) }
                if parts.count >= 3 { domainMin = SIMD3(parts[0], parts[1], parts[2]) }
            } else if trimmed.hasPrefix("DOMAIN_MAX") {
                let parts = trimmed.split(separator: " ").compactMap { Float($0) }
                if parts.count >= 3 { domainMax = SIMD3(parts[0], parts[1], parts[2]) }
            } else if !trimmed.hasPrefix("TITLE") {
                let parts = trimmed.split(separator: " ")
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
        let expected = lutSize * lutSize * lutSize
        guard rows.count == expected else {
            throw LUTError.invalidFormat("Expected \(expected) entries, got \(rows.count)")
        }

        self.size = lutSize
        self.photoStyleTag = photoStyle
        self.inputSpace = Self.resolveInputSpace(photoStyle: photoStyle, name: cleaned)

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

        self.tableData = floats.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    // MARK: - Inspection

    /// The flattened RGBA float table handed to Core Image, as floats.
    ///
    /// Exists for tests: rendering through Core Image clamps NaN to 0, so a
    /// corrupt table is invisible from the output side and has to be inspected
    /// directly.
    var tableFloats: [Float] {
        tableData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    // MARK: - Core Image Filter

    /// Creates a CIColorCube filter configured with this LUT.
    ///
    /// `space` is the **LUT interpolation space** — one half of the colour seam. It must stay in
    /// lockstep with the output encoding space; both default to `WorkingSpace.current` so they cannot
    /// drift apart. See `WorkingSpace`.
    func makeFilter(space: WorkingSpace = .current) -> CIFilter? {
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
