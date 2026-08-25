import Foundation

/// Writes a `.cube` the LUMIX S9 will accept.
///
/// Three constraints come from the camera rather than from the format:
/// 33 points maximum, a `#LUMIXPHOTOSTYLE` line declaring the base Photo Style
/// (absent or unrecognised means V-Log), and — for a card — an eight-character
/// name. The first two are enforced here; the third is the user's business
/// when they copy files across.
enum CubeWriter {

    static let maximumSize = 33

    enum WriteError: LocalizedError {
        case tooLarge(Int)
        case wrongCount(expected: Int, got: Int)

        var errorDescription: String? {
            switch self {
            case .tooLarge(let size):
                return "A \(size)-point LUT is larger than the DC-S9's 33-point limit."
            case .wrongCount(let expected, let got):
                return "Expected \(expected) entries, got \(got)."
            }
        }
    }

    /// Serialise a cube. `entries` is R-fastest, matching the format.
    static func text(entries: [SIMD3<Float>], size: Int, title: String, photoStyle: String? = "VLOG") throws -> String {
        guard size <= maximumSize else { throw WriteError.tooLarge(size) }
        let expected = size * size * size
        guard entries.count == expected else { throw WriteError.wrongCount(expected: expected, got: entries.count) }

        var out = ""
        out.reserveCapacity(expected * 26 + 128)
        out += "TITLE \"\(title)\"\n"
        if let photoStyle {
            out += "#LUMIXPHOTOSTYLE \(photoStyle)\n"
        }
        out += "LUT_3D_SIZE \(size)\n"
        out += "DOMAIN_MIN 0.0 0.0 0.0\n"
        out += "DOMAIN_MAX 1.0 1.0 1.0\n"
        for entry in entries {
            out += String(format: "%.6f %.6f %.6f\n",
                          min(max(entry.x, 0), 1), min(max(entry.y, 0), 1), min(max(entry.z, 0), 1))
        }
        return out
    }

    static func write(entries: [SIMD3<Float>], size: Int, title: String,
                      photoStyle: String? = "VLOG", to url: URL) throws {
        let body = try text(entries: entries, size: size, title: title, photoStyle: photoStyle)
        try body.write(to: url, atomically: true, encoding: .utf8)
    }
}
