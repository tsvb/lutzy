import CoreImage
import AppKit

/// What one LUT changes, relative to another.
///
/// The last resort of the comparison layouts. Side by side keeps both pictures
/// whole but makes the eye travel; a wipe puts them in one place but never
/// shows either whole. When two film simulations are close enough that neither
/// settles it, this shows only what moved.
///
/// The difference is taken on **code values** — what is on screen — rather than
/// in the linear working space, because "these two pictures differ here" is a
/// statement about what the eye sees, and a linear difference buries everything
/// below midtone. Core Image hands a kernel linear samples and encodes on the
/// way out, so both samples are encoded first and the result decoded, exactly
/// as the V-Log path does and for the same reason.
@MainActor
enum DifferenceComposer {

    /// Amplification. A difference between two film looks is a few percent, and
    /// unamplified it reads as a black frame.
    static let defaultGain: Float = 8

    private static let context = CIContext()

    private static let kernelSource = """
        vec3 encode(vec3 c) {
            vec3 v = clamp(c, 0.0, 1.0);
            vec3 lo = v * 12.92;
            vec3 hi = 1.055 * pow(v, vec3(1.0 / 2.4)) - 0.055;
            return mix(lo, hi, step(vec3(0.0031308), v));
        }
        vec3 decode(vec3 c) {
            vec3 v = clamp(c, 0.0, 1.0);
            vec3 lo = v / 12.92;
            vec3 hi = pow((v + 0.055) / 1.055, vec3(2.4));
            return mix(lo, hi, step(vec3(0.04045), v));
        }
        kernel vec4 difference(__sample a, __sample b, float gain) {
            vec3 d = abs(encode(a.rgb) - encode(b.rgb)) * gain;
            return vec4(decode(min(d, 1.0)), 1.0);
        }
        """

    /// The amplified difference between two rendered previews, or `nil` if
    /// either side is missing or the sizes disagree.
    static func compose(base: NSImage?, graded: NSImage?, gain: Float = defaultGain) -> NSImage? {
        guard let base, let graded,
              let baseCG = cgImage(base), let gradedCG = cgImage(graded),
              baseCG.width == gradedCG.width, baseCG.height == gradedCG.height,
              let kernel = CIColorKernel(source: kernelSource)
        else { return nil }

        let output = kernel.apply(
            extent: CGRect(x: 0, y: 0, width: baseCG.width, height: baseCG.height),
            arguments: [CIImage(cgImage: baseCG), CIImage(cgImage: gradedCG), gain]
        )
        guard let output,
              let rendered = context.createCGImage(output, from: output.extent)
        else { return nil }
        return NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
    }

    private static func cgImage(_ image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
