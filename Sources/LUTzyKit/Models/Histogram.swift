import Foundation
import CoreGraphics

/// Per-channel tonal distribution of an image, in 256 bins (one per 8-bit
/// level). Computed from a downscaled RGBA8 render — see
/// `RenderEngine.histogram(source:document:lut:scale:space:maxDimension:)`.
///
/// `Sendable` because the tally happens inside `actor RenderEngine`, where the `CIContext` lives,
/// and the result crosses back to the main actor to be published.
struct HistogramData: Equatable, Sendable {

    /// Channels a histogram view can draw.
    // `CaseIterable` was on this and `Channel.allCases` was never called (docs/CODE_REVIEW.md
    // §2, "Unused API"). The picker iterates `HistogramChart.Mode`, a different type with an
    // `rgb` case this one has no equivalent for.
    enum Channel {
        case red, green, blue, luma
    }

    let red: [Int]
    let green: [Int]
    let blue: [Int]
    /// Rec. 709 luminance (0.2126R + 0.7152G + 0.0722B).
    let luma: [Int]

    var binCount: Int { red.count }

    init(red: [Int], green: [Int], blue: [Int], luma: [Int]) {
        self.red = red
        self.green = green
        self.blue = blue
        self.luma = luma
    }

    /// Tally an already-rasterized RGBA8 buffer.
    ///
    /// Pure — no `CIContext`, no `CGImage`, no framework at all. Rasterizing is the caller's job
    /// (`RenderEngine`, which owns the one context); counting bytes is not, and keeping the two apart
    /// is what lets the arithmetic below be tested against a hand-built buffer rather than against
    /// whatever a decoder happened to produce.
    ///
    /// Returns `nil` for a buffer that cannot hold `height` rows of `bytesPerRow`.
    init?(rgba8 bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int? = nil) {
        let stride = bytesPerRow ?? width * 4
        guard width > 0, height > 0, stride >= width * 4, bytes.count >= height * stride else {
            return nil
        }

        var red = [Int](repeating: 0, count: 256)
        var green = [Int](repeating: 0, count: 256)
        var blue = [Int](repeating: 0, count: 256)
        var luma = [Int](repeating: 0, count: 256)

        bytes.withUnsafeBufferPointer { buf in
            for y in 0..<height {
                let row = y * stride
                for x in 0..<width {
                    let off = row + x * 4
                    let r = Int(buf[off])
                    let g = Int(buf[off + 1])
                    let b = Int(buf[off + 2])
                    red[r] += 1
                    green[g] += 1
                    blue[b] += 1
                    // Rec.709 luma, rounded to nearest bin.
                    let l = (2126 * r + 7152 * g + 722 * b + 5000) / 10000
                    luma[min(255, l)] += 1
                }
            }
        }

        self.init(red: red, green: green, blue: blue, luma: luma)
    }

    func bins(for channel: Channel) -> [Int] {
        switch channel {
        case .red:   return red
        case .green: return green
        case .blue:  return blue
        case .luma:  return luma
        }
    }

    /// Display ceiling used to scale bar heights. The pure-black (0) and
    /// pure-white (255) bins are excluded so a single clipping spike doesn't
    /// flatten the rest of the curve into the floor. Falls back to the absolute
    /// max if the interior is empty.
    private static func displayMax(_ channels: [[Int]]) -> Int {
        var interior = 0
        var absolute = 0
        for bins in channels {
            guard bins.count > 2 else { continue }
            for (i, v) in bins.enumerated() {
                absolute = max(absolute, v)
                if i > 0 && i < bins.count - 1 { interior = max(interior, v) }
            }
        }
        return interior > 0 ? interior : absolute
    }

    /// Bars normalized to 0...1 for drawing, scaled by the appropriate ceiling.
    func normalized(_ channel: Channel) -> [CGFloat] {
        let ceiling = channel == .luma ? HistogramData.displayMax([luma])
                                        : HistogramData.displayMax([red, green, blue])
        guard ceiling > 0 else { return Array(repeating: 0, count: binCount) }
        let denom = CGFloat(ceiling)
        return bins(for: channel).map { min(1, CGFloat($0) / denom) }
    }
}
