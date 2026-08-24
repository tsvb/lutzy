import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Turns an `EditDocument` into one lazy `CIImage`. A pure function — no `CIContext`, no rasterizing,
/// no state.
///
/// This is the middle layer of Phase 2: the document describes the look, this folds it into a filter
/// graph, and `actor RenderEngine` (Step 4) evaluates that graph at one of two scales. **Preview and
/// export call this same function and differ only in `scale`**, which is what makes their agreement
/// structural rather than a coincidence that two code paths currently maintain. See
/// `docs/PHASE2_SPEC.md` §1 and §3.
///
/// Nothing here is rasterized. Every stage hands the next a lazy `CIImage`, so the whole chain costs
/// one GPU pass when the engine finally renders it.
enum RenderPipeline {

    /// Build the graph for `document` over `source`.
    ///
    /// - Parameters:
    ///   - source: how to reproduce the source. A RAW is re-developed here, from the bytes, because
    ///     `CIRAWFilter` must be configured before it yields an image (§4.2).
    ///   - document: the look.
    ///   - lut: the LUT `document.lut.lutID` resolves to, or `nil`.
    ///   - scale: preview or full. Applied **early** — see `developedSource`.
    ///   - space: the LUT interpolation space. Output *encoding* is the engine's half of the seam;
    ///     both read one `WorkingSpace` so they cannot drift (§4.4).
    ///   - lutCache: reusable cube filters. `nil` builds one per call, which is correct but wasteful.
    ///
    /// - Returns: the graph, or `nil` if the source could not be decoded.
    ///
    /// **An unresolved LUT renders without the LUT rather than failing.** If `document.lut.lutID` is
    /// set but `lut` is `nil` — the file was deleted, the library has not finished scanning — this
    /// returns the ungraded image. Resolution is the caller's job and the caller is the layer that can
    /// report it; blanking the preview on every render would turn a missing file into a broken app,
    /// and reporting it per render would mean reporting it sixty times a second. Validate at load and
    /// report there (§7).
    static func buildImage(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace = .current,
        sourceIsVLog: Bool = false,
        lutCache: LUTFilterCache? = nil
    ) -> CIImage? {
        guard let developed = developedSource(source, rawDevelop: document.rawDevelop, scale: scale) else {
            return nil
        }
        return buildImage(
            developed: developed, document: document, lut: lut, space: space,
            sourceIsVLog: sourceIsVLog, lutCache: lutCache
        )
    }

    /// The graph from an **already-developed** source onwards — adjustments, then the LUT.
    ///
    /// Split out so a caller that already holds the developed image can skip the source stage.
    /// `RenderEngine` does exactly that, and it is not a micro-optimization: Core Image caches decoded
    /// intermediates **per `CIImage` instance**, so rebuilding the source image on every render throws
    /// that cache away and re-decodes the file. Measured on a 6000×4000 source, rebuilding it per
    /// render cost 156 ms against 0.6 ms for reusing one — a 272× regression on every intensity tick.
    ///
    /// This stays pure; the memo lives on the actor, where mutable state belongs.
    static func buildImage(
        developed: CIImage,
        document: EditDocument,
        lut: CubeLUT?,
        space: WorkingSpace = .current,
        sourceIsVLog: Bool = false,
        lutCache: LUTFilterCache? = nil
    ) -> CIImage {
        let adjusted = applyAdjustments(document.adjustments, to: developed)
        return applyLUT(
            document.lut, lut: lut, to: adjusted, space: space,
            sourceIsVLog: sourceIsVLog, cache: lutCache
        )
    }

    // MARK: - Source

    /// Decode the source at the requested scale.
    ///
    /// **Downscaling happens here, before anything else touches the pixels.** For RAW that means
    /// `CIRAWFilter.scaleFactor`, set before `outputImage`, so the decoder itself demosaics small; for
    /// a standard image it is a Lanczos step immediately after load. Either way the adjustment and LUT
    /// stages then operate on a preview-sized image rather than a 60-megapixel one.
    ///
    /// That is the whole reason every `AdjustmentNode` must use normalized units (§5): the graph a
    /// preview runs is the graph an export runs, at a different number of pixels.
    ///
    /// The scale is computed from the **decoder's** idea of the source size — `CIRAWFilter.nativeSize`
    /// or the decoded extent — not from `ImageSource.nativeExtent`. Both should agree, but only one of
    /// them is authoritative, and a caller that measured wrong should not be able to produce a
    /// mis-scaled render.
    static func developedSource(
        _ source: ImageSource,
        rawDevelop: RAWDevelopSettings,
        scale: RenderScale
    ) -> CIImage? {
        switch source.kind {
        case .raw:
            guard let filter = rawFilter(for: source.backing) else { return nil }
            rawDevelop.apply(to: filter)

            let factor = scale.factor(for: filter.nativeSize)
            if factor < 1 {
                filter.scaleFactor = Float(factor)
            }
            return filter.outputImage

        case .standard:
            guard let image = standardImage(for: source.backing) else { return nil }
            let factor = scale.factor(for: image.extent.size)
            guard factor < 1 else { return image }
            return lanczosScaled(image, by: factor)
        }
    }

    /// Internal rather than private since Step 10a: `RenderEngine.rawCapabilities` builds a filter
    /// purely to read its `is*Supported` flags, and duplicating the two-case construction would be
    /// two places for the `identifierHint` decision to drift.
    static func rawFilter(for backing: ImageSource.Backing) -> CIRAWFilter? {
        switch backing {
        case .url(let url):
            return CIRAWFilter(imageURL: url)
        case .data(let data):
            // No filename to hint with — the decoder identifies the format from the bytes, which is
            // the same thing `ImageSource.kind(forData:)` already did to classify it as RAW.
            return CIRAWFilter(imageData: data, identifierHint: nil)
        }
    }

    private static func standardImage(for backing: ImageSource.Backing) -> CIImage? {
        // `orientedLoadOptions` is shared with `ImageDecoder` on purpose: a portrait JPEG has to
        // come out of this pipeline the same way up as it comes out of the eager decode the view
        // model does at open, and `CIImage` ignores the EXIF tag unless asked.
        switch backing {
        case .url(let url):
            return CIImage(contentsOf: url, options: ImageDecoder.orientedLoadOptions)
        case .data(let data):
            return CIImage(data: data, options: ImageDecoder.orientedLoadOptions)
        }
    }

    private static func lanczosScaled(_ image: CIImage, by factor: CGFloat) -> CIImage {
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = image
        lanczos.scale = Float(factor)
        lanczos.aspectRatio = 1
        return lanczos.outputImage ?? image
    }

    // MARK: - Adjustments

    /// Fold the ordered nodes over the image.
    ///
    /// Nodes at their identity values are skipped. That is an optimization, not a behaviour change:
    /// all five filters are bit-exact pass-throughs at the values `AdjustmentNode.isIdentity` names —
    /// measured, and pinned by `testSkippingIdentityNodesChangesNothing`.
    static func applyAdjustments(_ nodes: [AdjustmentNode], to image: CIImage) -> CIImage {
        nodes.reduce(image) { partial, node in
            node.isIdentity ? partial : (filter(for: node, input: partial) ?? partial)
        }
    }

    /// The node → `CIFilter` mapping. Built through `CIFilterBuiltins`, so the parameter names are
    /// checked by the compiler rather than spelled as strings.
    private static func filter(for node: AdjustmentNode, input: CIImage) -> CIImage? {
        switch node {
        case .exposure(let ev):
            let f = CIFilter.exposureAdjust()
            f.inputImage = input
            f.ev = Float(ev)
            return f.outputImage

        case .colorControls(let brightness, let contrast, let saturation):
            let f = CIFilter.colorControls()
            f.inputImage = input
            f.brightness = Float(brightness)
            f.contrast = Float(contrast)
            f.saturation = Float(saturation)
            return f.outputImage

        case .highlightShadow(let highlights, let shadows):
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = input
            f.highlightAmount = Float(highlights)
            f.shadowAmount = Float(shadows)
            return f.outputImage

        case .temperatureTint(let temp, let tint):
            let f = CIFilter.temperatureAndTint()
            f.inputImage = input
            // Source neutral is pinned at D65; only the target moves. This is what makes identity
            // land at (6500, 0) — and also what pins the node's own Kelvin direction backwards:
            // raising Kelvin cools the image, held by testRaisingKelvinCoolsTheImage. §8.7 is
            // closed: the Adjust panel's slider is reflected about D65 in
            // AdjustmentControl.sliderMapped(_:), so both Kelvin sliders in the inspector warm
            // rightward without touching this line. Changing *this* line instead changes stored
            // pixel behaviour for every document — a different and much larger act than flipping a
            // slider's display mapping.
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: temp, y: tint)
            return f.outputImage

        case .vibrance(let amount):
            let f = CIFilter.vibrance()
            f.inputImage = input
            f.amount = Float(amount)
            return f.outputImage
        }
    }

    /// Linear cross-fade between two images in the working space.
    private static func blend(from: CIImage, to: CIImage, amount: Double) -> CIImage {
        let dissolve = CIFilter.dissolveTransition()
        dissolve.inputImage = from
        dissolve.targetImage = to
        dissolve.time = Float(max(0, min(1, amount)))
        return dissolve.outputImage ?? to
    }

    // MARK: - LUT

    private static func applyLUT(
        _ settings: LUTSettings,
        lut: CubeLUT?,
        to image: CIImage,
        space: WorkingSpace,
        sourceIsVLog: Bool,
        cache: LUTFilterCache?
    ) -> CIImage {
        guard !settings.isIdentity, let lut else { return image }

        // A V-Log LUT expects scene-referred log, but the developed image is a
        // finished picture. Convert it into V-Log first — unless the source is
        // already V-Log (a clip shot on the S9), in which case it is fed
        // straight in. A display-input LUT is untouched, so ordinary LUTs
        // behave exactly as before.
        guard lut.inputSpace == .vlog else {
            let cubeFilter = cache?.filter(for: lut, space: space) ?? lut.makeFilter(space: space)
            return lut.apply(to: image, intensity: settings.intensity, using: cubeFilter) ?? image
        }

        // V-Log path: this project owns the encoding at both ends. The source
        // becomes V-Log code values (unless it already is V-Log), the cube is
        // indexed with those codes directly, and the LUT's own output codes are
        // decoded back into the linear working space the rest of the graph uses.
        let prepared = sourceIsVLog ? VLogInputAdapter.recoverCodeValues(image) : VLogInputAdapter.encode(image)
        let cubeFilter = cache?.filter(for: lut, space: space) ?? lut.makeFilter(space: space)
        guard let graded = lut.apply(to: prepared, intensity: 1.0, using: cubeFilter) else { return image }
        let decoded = VLogInputAdapter.decodeOutput(graded)

        // Intensity blends against the picture the user started from, in the
        // working space — not against V-Log codes, which would mix two
        // different encodings and dim the midpoint.
        guard settings.intensity < 1.0 else { return decoded }
        return blend(from: image, to: decoded, amount: settings.intensity)
    }
}
