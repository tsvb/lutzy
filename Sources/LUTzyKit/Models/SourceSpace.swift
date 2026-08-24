import CoreImage
import Foundation

/// What space the *source image* is in, as far as a V-Log LUT is concerned.
///
/// This is the other half of `LUTInputSpace`. A V-Log LUT needs V-Log in; the
/// question is whether this particular file already is V-Log (a frame shot on
/// an S9 in V-Log) or an ordinary rendered picture that has to be converted
/// first. Getting it backwards is the difference between a preview and
/// nonsense, and it cannot be answered from the LUT — only from the image.
///
/// `.auto` is the default because the answer is usually inferable, and being
/// asked on every open would be worse than being right nine times in ten and
/// correctable the tenth.
enum SourceSpace: String, Codable, Sendable, Equatable, CaseIterable {
    case auto
    case vlog       // already V-Log; feed a V-Log LUT directly
    case display    // an ordinary picture; convert to V-Log before a V-Log LUT

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .vlog: return "V-Log"
        case .display: return "Ordinary"
        }
    }
}

/// Decides whether an image is V-Log footage, by measurement.
///
/// V-Log leaves a signature that ordinary pictures do not have: its black sits
/// at 0.125 and nothing goes below it, the tones bunch around mid grey, the
/// highlights roll off well under 1.0, and the colour is flat because no look
/// has been applied yet. Four weak signals; together they separate the two
/// cases confidently, and where they disagree the answer is `nil` — "ask the
/// user" beats guessing, since a foggy, matte or低-contrast photograph
/// genuinely looks like log footage by any one of these measures.
///
/// The same four tests as `lutcraft`'s Python detector, so the app and the
/// offline tools agree about what a file is.
enum SourceSpaceDetector {

    /// V-Log's black point. Nothing recorded in V-Log sits below it.
    static let vlogBlack: Float = 0.125

    struct Reading: Sendable, Equatable {
        var low: Float        // 5th percentile
        var high: Float       // 95th percentile
        var median: Float
        var saturation: Float // channel spread, relative to the brightest channel
    }

    /// Classify a reading. Returns `nil` when the signals disagree.
    static func classify(_ r: Reading) -> SourceSpace? {
        // Too little range to tell: a flat grey card is neither log nor graded,
        // and every test below would fire on it.
        guard r.high - r.low >= 0.15 else { return nil }

        var score: Float = 0
        score += r.low >= vlogBlack - 0.008 ? 0.35 : -0.25
        score += (0.28...0.58).contains(r.median) ? 0.20 : 0
        score += r.high <= 0.88 ? 0.20 : -0.15
        score += r.saturation <= 0.30 ? 0.25 : -0.20

        if score >= 0.7 { return .vlog }
        if score <= 0.35 { return .display }
        return nil
    }

    /// Measure an image. Samples a small render rather than every pixel: the
    /// statistics wanted here are stable long before full resolution, and this
    /// runs on every open.
    static func read(_ image: CIImage, context: CIContext, samples: Int = 96) -> Reading? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, extent.isInfinite == false else { return nil }

        // Judge the centre: letterboxing or a burnt-in border is not the
        // picture, but it is enough to move a percentile.
        let inset = CGRect(
            x: extent.minX + extent.width * 0.08,
            y: extent.minY + extent.height * 0.08,
            width: extent.width * 0.84,
            height: extent.height * 0.84
        )
        let cropped = image.cropped(to: inset)
        let scale = min(CGFloat(samples) / cropped.extent.width, CGFloat(samples) / cropped.extent.height, 1)
        let small = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let width = max(Int(small.extent.width), 1)
        let height = max(Int(small.extent.height), 1)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let rowBytes = width * 16
        // Read back in the same space the file was decoded into, undecoded: the
        // question is about code values, so no colour management may intervene.
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        pixels.withUnsafeMutableBytes { buffer in
            context.render(
                small,
                toBitmap: buffer.baseAddress!,
                rowBytes: rowBytes,
                bounds: CGRect(x: small.extent.minX, y: small.extent.minY,
                               width: CGFloat(width), height: CGFloat(height)),
                format: .RGBAf,
                colorSpace: space
            )
        }

        var channels: [Float] = []
        channels.reserveCapacity(width * height * 3)
        var spreads: [Float] = []
        spreads.reserveCapacity(width * height)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = pixels[index], g = pixels[index + 1], b = pixels[index + 2]
            channels.append(contentsOf: [r, g, b])
            let peak = max(r, max(g, b))
            let trough = min(r, min(g, b))
            spreads.append(peak > 1e-6 ? (peak - trough) / peak : 0)
        }
        guard channels.isEmpty == false else { return nil }

        let sorted = channels.sorted()
        func percentile(_ p: Float) -> Float {
            let position = Int((Float(sorted.count - 1) * p).rounded())
            return sorted[min(max(position, 0), sorted.count - 1)]
        }
        let sortedSpreads = spreads.sorted()
        return Reading(
            low: percentile(0.05),
            high: percentile(0.95),
            median: percentile(0.5),
            saturation: sortedSpreads[sortedSpreads.count / 2]
        )
    }

    /// Measure and classify in one step.
    static func detect(_ image: CIImage, context: CIContext) -> SourceSpace? {
        guard let reading = read(image, context: context) else { return nil }
        return classify(reading)
    }
}
