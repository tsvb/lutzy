import Foundation
import CoreImage
import CoreGraphics

/// What the app needs from a renderer, so a test can hand it something that is not the GPU.
///
/// The point of the protocol is not abstraction for its own sake — it is that once the view model
/// renders through this (Step 5), a test can drive the whole preview/export flow against a fake and
/// assert on *what was asked for* rather than on pixels. Pixel assertions belong to the engine's own
/// tests; everything above it should be testable without a Metal device.
///
/// `Sendable` because every conformer is crossed from the main actor. `actor RenderEngine` gets that
/// for free; a fake has to earn it.
protocol RenderEngining: Sendable {

    /// Rasterize `document` over `source` for display.
    ///
    /// Returns `sending` rather than a plain `CGImage?` because **`CGImage` is not `Sendable`**
    /// (verified against the SDK — there is no `@unchecked` conformance to lean on). Region-based
    /// isolation lets the freshly-created image leave the actor safely: the engine provably holds no
    /// other reference to it. The alternative — returning raw bytes and rebuilding a `CGImage` on the
    /// far side — would cost a copy of every preview frame to say the same thing.
    func makeCGImage(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace
    ) async -> sending CGImage?

    /// Encode `document` over `source` to a file format's bytes.
    ///
    /// Returns `Data` for the caller to write, rather than taking a URL. File I/O is not the GPU's
    /// business, and keeping it out means the actor never touches the sandbox, the security-scoped
    /// bookmark, or a partially-written file.
    func encode(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        format: ExportFormat,
        quality: CGFloat,
        space: WorkingSpace
    ) async throws -> Data

    /// Tally `document` over `source` into a 256-bin per-channel histogram.
    ///
    /// On the protocol rather than left to the caller because tallying needs a rasterizer, and the
    /// rasterizer is this actor. The alternative — handing the caller a `CIImage` to tally itself —
    /// is the old `ImageProcessor` shape, and it is what let the histogram describe a *different*
    /// image from the one on screen: it graded a full-resolution neutral decode with only the LUT,
    /// while the preview showed develop and adjustments too.
    ///
    /// `scale` should be the **display** scale, not a histogram-sized one, so the call reuses the
    /// engine's developed-source memo instead of evicting it; the tally buffer is capped separately
    /// by `maxDimension`.
    func histogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace,
        maxDimension: Int
    ) async -> HistogramData?

    /// Drop every cached cube filter, because the bytes behind a `LUTID` may have changed.
    ///
    /// **On the protocol as of Step 9, so that the app calling it is assertable.** The engine has had
    /// this method since Step 4 and it was correct the whole time; the only caller was a test, and
    /// nothing above the actor could see whether it fired. Its absence became reachable in Step 9:
    /// saving a second derive over the same `.cube` path yields the same `LUTID`, so without this the
    /// cache keeps serving the first cube and the second save silently does nothing on screen.
    func invalidateLUTCache() async

    /// What this source's RAW decoder can do, and where its own defaults sit. `nil` for a non-RAW.
    ///
    /// On the protocol because the develop inspector needs it and cannot reach a `CIRAWFilter`:
    /// the flags live on a non-`Sendable` type confined to the actor (§4.5). Returning a value is
    /// the only way the panel can be gated on what the decoder actually supports.
    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities?
}

/// The one `CIContext`.
///
/// **The GPU is the isolation boundary** (`docs/PHASE2_SPEC.md` §4.5). `CIImage`, `CIFilter` and
/// `CIContext` are born and die inside this actor; only `Sendable` values cross in — `EditDocument`,
/// `ImageSource`, `CubeLUT`, `WorkingSpace`, `RenderScale` — and a `sending CGImage?` or a `Data`
/// crosses out. That is what lets Step 8 turn strict concurrency on without a single `@unchecked`.
///
/// It deliberately does **not** decide *what* to render. `RenderPipeline.buildImage` is a pure
/// function that builds the graph; this evaluates it. Preview and export call the same builder and
/// differ only in `scale`, which is what makes their agreement structural rather than maintained
/// (§1).
///
/// Added in Step 4 **alongside** the old `ImageProcessor` path, which Steps 5–7 then cut over leaf by
/// leaf — preview, export, histogram — until nothing was left of it to delete. As of Step 7 this is
/// the **only** `CIContext` in the render stack. `RecipeExtractor` keeps its own by design (§3): it
/// sits outside this stack, never imports `EditDocument`, and samples in a space pinned to sRGB
/// regardless of `WorkingSpace.current`. Two contexts in the module, one in the render path, and
/// `RenderStackTests` fails if a third appears.
actor RenderEngine: RenderEngining {

    /// The app's engine. One instance, therefore one context.
    static let shared = RenderEngine()

    private let context: CIContext

    /// Cube filters, reused across renders. Lives here rather than on `CubeLUT` because it is mutable
    /// reference state: a `CIFilter` gets its `inputImage` written on every use, so it is only safe
    /// behind this actor's serialization (§4.5).
    private let lutCache = LUTFilterCache()

    init() {
        // Matches `ImageProcessor`: Metal when there is a device, the CPU fallback when there isn't
        // (CI runners included).
        if let device = MTLCreateSystemDefaultDevice() {
            self.context = CIContext(mtlDevice: device)
        } else {
            self.context = CIContext()
        }
    }

    /// Inject a context — for tests that need to pin the backend rather than take whatever the
    /// machine offers.
    init(context: CIContext) {
        self.context = context
    }

    // MARK: - Rendering

    func makeCGImage(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace = .current
    ) -> sending CGImage? {
        // A gallery search can retire many queued thumbnail requests at once.
        // Actor serialization is still desirable for the shared CIContext,
        // but a cancelled request must not consume its turn doing GPU work.
        guard Task.isCancelled == false else { return nil }
        guard let image = buildImage(source, document, lut, scale, space) else { return nil }
        guard Task.isCancelled == false else { return nil }
        let rect = image.extent.integral
        guard rect.isRasterizable else { return nil }

        // The colour space is passed explicitly — this is the output-encoding half of the seam, and
        // omitting it is exactly the latent preview/export mismatch Step 1 closed.
        return context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: space.cgColorSpace)
    }

    func encode(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale = .full,
        format: ExportFormat,
        quality: CGFloat = 0.95,
        space: WorkingSpace = .current
    ) throws -> Data {
        guard let image = buildImage(source, document, lut, scale, space) else {
            throw ImageError.processingFailed
        }
        guard image.extent.isRasterizable else {
            throw ImageError.processingFailed
        }
        let colorSpace = space.cgColorSpace

        switch format {
        case .tiff:
            guard let data = context.tiffRepresentation(
                of: image, format: .RGBA16, colorSpace: colorSpace
            ) else { throw ImageError.exportFailed }
            return data

        case .jpeg:
            guard let data = context.jpegRepresentation(
                of: image, colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
            ) else { throw ImageError.exportFailed }
            return data

        case .png:
            guard let data = context.pngRepresentation(
                of: image, format: .RGBA8, colorSpace: colorSpace
            ) else { throw ImageError.exportFailed }
            return data
        }
    }

    // MARK: - Histogram

    /// Tally the rendered document into 256 bins per channel.
    ///
    /// The image is rendered to a downscaled RGBA8 buffer first — `maxDimension` caps the longest
    /// side so this stays a few milliseconds even for a 60 MP source, while staying representative.
    ///
    /// `scale` is the caller's *display* scale on purpose. The developed-source memo is keyed on it
    /// (§6, "the cutover's one real trap"), so asking for a histogram at some private 512 px scale
    /// would evict the preview's entry on every tally and re-develop the RAW on the next frame —
    /// turning a cheap panel into a per-frame decode. Rendering the same graph the preview renders
    /// and shrinking only the tally buffer keeps both on one memo entry.
    ///
    /// The buffer is rendered in `space` for the same reason `makeCGImage` is: the histogram should
    /// describe the pixels the user is looking at, not a differently-encoded copy of them.
    func histogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace = .current,
        maxDimension: Int = 512
    ) -> HistogramData? {
        guard maxDimension > 0, let image = buildImage(source, document, lut, scale, space) else {
            return nil
        }
        let extent = image.extent
        guard extent.isRasterizable else { return nil }

        let factor = min(
            CGFloat(maxDimension) / extent.width,
            CGFloat(maxDimension) / extent.height,
            1.0
        )
        let scaled = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        let rect = scaled.extent.integral
        guard rect.isRasterizable else { return nil }

        let width = Int(rect.width)
        let height = Int(rect.height)
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        bytes.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            context.render(
                scaled, toBitmap: base, rowBytes: bytesPerRow, bounds: rect,
                format: .RGBA8, colorSpace: space.cgColorSpace
            )
        }
        return HistogramData(rgba8: bytes, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    // MARK: - RAW capabilities

    /// Build a throwaway `CIRAWFilter` and read its flags and its own defaults.
    ///
    /// **`outputImage` is deliberately never touched.** That is the difference between ~25 ms and
    /// ~183 ms on a 30 MB DNG (measured; see the Step 10a design doc), and it is why this can run on
    /// every image open without being felt. It also leaves the developed-source memo alone — a
    /// capability question must not evict the image the user is looking at.
    ///
    /// **A gated seed is read only when its gate is open.** Every property below the `is*Supported`
    /// line is a knob this particular decoder may not offer, and what an unoffered property returns is
    /// not a default the panel should show — it is nothing at all. Where the gate is shut the seed
    /// stays at `RAWCapabilities`' own default, which no control can reach anyway: `supports(_:)`
    /// withdraws the control on the same flag.
    func rawCapabilities(for source: ImageSource) -> RAWCapabilities? {
        guard case .raw = source.kind else { return nil }
        guard let filter = RenderPipeline.rawFilter(for: source.backing) else { return nil }

        var highlightRecovery = false
        #if compiler(>=6.2)
            if #available(macOS 26, *) {
                highlightRecovery = filter.isHighlightRecoverySupported
            }
        #endif

        return RAWCapabilities(
            isSharpnessSupported: filter.isSharpnessSupported,
            isContrastSupported: filter.isContrastSupported,
            isDetailSupported: filter.isDetailSupported,
            isMoireReductionSupported: filter.isMoireReductionSupported,
            isLocalToneMapSupported: filter.isLocalToneMapSupported,
            isLuminanceNoiseReductionSupported: filter.isLuminanceNoiseReductionSupported,
            isColorNoiseReductionSupported: filter.isColorNoiseReductionSupported,
            isLensCorrectionSupported: filter.isLensCorrectionSupported,
            isHighlightRecoverySupported: highlightRecovery,
            asShotTemperature: Double(filter.neutralTemperature),
            asShotTint: Double(filter.neutralTint),
            baselineExposure: Double(filter.baselineExposure),
            shadowBias: Double(filter.shadowBias),
            sharpnessAmount: filter.isSharpnessSupported ? Double(filter.sharpnessAmount) : 0,
            contrastAmount: filter.isContrastSupported ? Double(filter.contrastAmount) : 0,
            detailAmount: filter.isDetailSupported ? Double(filter.detailAmount) : 0,
            moireReductionAmount:
                filter.isMoireReductionSupported ? Double(filter.moireReductionAmount) : 0,
            localToneMapAmount:
                filter.isLocalToneMapSupported ? Double(filter.localToneMapAmount) : 0,
            luminanceNoiseReductionAmount: filter.isLuminanceNoiseReductionSupported
                ? Double(filter.luminanceNoiseReductionAmount) : 0,
            colorNoiseReductionAmount: filter.isColorNoiseReductionSupported
                ? Double(filter.colorNoiseReductionAmount) : 0,
            lensCorrectionEnabled:
                filter.isLensCorrectionSupported ? filter.isLensCorrectionEnabled : false
        )
    }

    // MARK: - Cache

    /// Drop every cached cube filter. For a library rescan: a `LUTID` is a file path, so a `.cube`
    /// edited in place keeps its ID and would otherwise keep serving the old cube.
    func invalidateLUTCache() {
        lutCache.removeAll()
    }

    /// How many cube filters are held. Internal for the tests that prove the cache is actually being
    /// used across renders rather than rebuilt each time — there is no other way to observe it from
    /// outside, and a silently-bypassed cache is invisible in the output.
    var cachedFilterCount: Int { lutCache.count }

    // MARK: - Private

    /// One funnel, so preview and export cannot diverge in how they build the graph — only in the
    /// scale they ask for.
    private func buildImage(
        _ source: ImageSource,
        _ document: EditDocument,
        _ lut: CubeLUT?,
        _ scale: RenderScale,
        _ space: WorkingSpace
    ) -> CIImage? {
        guard let developed = developedSource(source, document.rawDevelop, scale) else { return nil }
        return RenderPipeline.buildImage(
            developed: developed, document: document, lut: lut, space: space,
            sourceIsVLog: resolveSourceIsVLog(source, document: document, developed: developed, lut: lut),
            lutCache: lutCache
        )
    }

    /// Whether the developed image should be fed to a V-Log LUT as-is.
    ///
    /// Only asked when it matters — a display-input LUT never reaches the
    /// adapter, so an ordinary LUT costs nothing here.
    ///
    /// `.auto` asks the file first and measures its pixels only if the file did
    /// not say, because metadata is evidence and statistics are inference. When
    /// neither settles it the answer is "ordinary": it is both the commoner
    /// case and the milder failure — converting a picture that was already
    /// V-Log flattens it visibly, while the reverse just looks like the LUT did
    /// very little. Either way the user's own choice sits above both.
    private func resolveSourceIsVLog(_ source: ImageSource, document: EditDocument,
                                     developed: CIImage, lut: CubeLUT?) -> Bool {
        guard lut?.inputSpace == .vlog else { return false }
        switch document.sourceSpace {
        case .vlog: return true
        case .display: return false
        case .auto: return autoSourceSpace(source, developed: developed) == .vlog
        }
    }

    /// What `.auto` resolves to, and what the UI reports it resolved to.
    func autoSourceSpace(_ source: ImageSource, developed: CIImage) -> SourceSpace? {
        if let finding = SourceSpaceMetadata.read(source), finding.space != .auto {
            return finding.space
        }
        return detectedSourceSpace(for: developed)
    }

    /// Detection is memoised alongside the developed-source memo: it renders a
    /// small crop, and the preview path would otherwise ask on every intensity
    /// tick. Keyed by the same `developedKey`, because that is precisely what
    /// identifies the image being measured.
    private func detectedSourceSpace(for developed: CIImage) -> SourceSpace? {
        if let key = developedKey, key == detectionKey { return detectionResult }
        let found = SourceSpaceDetector.detect(developed, context: context)
        detectionKey = developedKey
        detectionResult = found
        return found
    }

    // MARK: - The developed-source memo

    private struct DevelopedKey: Equatable {
        let source: ImageSource
        let rawDevelop: RAWDevelopSettings
        let scale: RenderScale
    }

    private var developedKey: DevelopedKey?
    private var developedImage: CIImage?
    /// Memo for source-space detection, keyed by the developed source it measured.
    private var detectionKey: DevelopedKey?
    private var detectionResult: SourceSpace?

    /// The source stage, memoized for **preview** renders.
    ///
    /// This exists for one measured reason. Core Image caches decoded intermediates against the
    /// `CIImage` instance, so handing it a freshly-built source every render means re-decoding the
    /// file every render. Measured per preview render, rebuilding versus reusing:
    ///
    /// | source | rebuild | reuse |
    /// |---|---|---|
    /// | 30 MB DNG | 63 ms | 0.7 ms |
    /// | 6000×4000 | 156 ms | 0.6 ms |
    ///
    /// An intensity drag is many renders, so without this the cutover would be a plainly visible
    /// regression — the one thing Step 5 must not ship.
    ///
    /// **Only preview scales are memoized.** Export runs once per user action, so it has nothing to
    /// gain, and holding a full-resolution developed image between exports would pin Core Image's
    /// full-resolution intermediates for as long as the engine lives.
    ///
    /// A single entry, because the user is looking at one image at a time: changing image, develop
    /// settings, or preview size replaces it. Nothing is retained once the next image is opened.
    private func developedSource(
        _ source: ImageSource,
        _ rawDevelop: RAWDevelopSettings,
        _ scale: RenderScale
    ) -> CIImage? {
        guard case .preview = scale else {
            return RenderPipeline.developedSource(source, rawDevelop: rawDevelop, scale: scale)
        }
        let key = DevelopedKey(source: source, rawDevelop: rawDevelop, scale: scale)
        if key == developedKey, let developedImage { return developedImage }

        guard let image = RenderPipeline.developedSource(
            source, rawDevelop: rawDevelop, scale: scale
        ) else { return nil }

        developedKey = key
        developedImage = image
        return image
    }

    /// Drop the developed-source memo. Not needed for correctness — the key covers every input — but
    /// it lets a caller release the intermediates when no image is on screen.
    func invalidateSourceCache() {
        developedKey = nil
        developedImage = nil
    }
}
