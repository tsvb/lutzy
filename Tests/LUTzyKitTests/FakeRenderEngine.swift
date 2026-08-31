import Foundation
import CoreImage
import CoreGraphics
@testable import LUTzyKit

extension RAWCapabilities {

    /// Every gate open, and **every seed a different value that is not the field default**.
    ///
    /// `.everyGateOpen` cannot serve as the stub for seed tests: it leaves all twelve seeds at
    /// 0/false, which is exactly what a getter falling back to a hardcoded constant returns, so
    /// "the seed was read" and "a constant was guessed" are literally the same number. Every value
    /// here is distinct from every other, so a getter wired to the *wrong* seed field also fails
    /// rather than coincidentally matching its neighbour.
    ///
    /// `lensCorrectionEnabled` is deliberately `false` while every other flag is on: the getter it
    /// replaced returned a hardcoded `true`, so `false` is the only value that can catch a
    /// regression to it. Likewise the numbers below avoid 0 and 1.
    static let distinctivelySeeded = RAWCapabilities(
        isSharpnessSupported: true,
        isContrastSupported: true,
        isDetailSupported: true,
        isMoireReductionSupported: true,
        isLocalToneMapSupported: true,
        isLuminanceNoiseReductionSupported: true,
        isColorNoiseReductionSupported: true,
        isLensCorrectionSupported: true,
        isHighlightRecoverySupported: true,
        asShotTemperature: 5842.2,
        asShotTint: 14.04,
        baselineExposure: 0.37,
        shadowBias: -0.21,
        sharpnessAmount: 0.11,
        contrastAmount: 0.22,
        detailAmount: 1.33,
        moireReductionAmount: 0.44,
        localToneMapAmount: 0.55,
        luminanceNoiseReductionAmount: 0.66,
        colorNoiseReductionAmount: 0.77,
        lensCorrectionEnabled: false
    )
}

/// A `RenderEngining` that never touches the GPU.
///
/// This is the deliverable of Step 4 that is easy to overlook: once the view model renders through
/// the protocol (Step 5), its tests should be able to assert *what was asked for* — which document,
/// which scale, how many times — without a Metal device and without comparing pixels. That is only
/// possible if the protocol is genuinely conformable by something trivial, which is what this proves.
///
/// An `actor` for the same reason the real one is: the protocol is `Sendable`, and recording calls is
/// mutable state.
actor FakeRenderEngine: RenderEngining {

    /// Every `makeCGImage` call, in order.
    private(set) var previewRequests: [Request] = []
    /// Every `encode` call, in order.
    private(set) var encodeRequests: [Request] = []
    /// Every `histogram` call, in order.
    private(set) var histogramRequests: [Request] = []

    struct Request: Equatable {
        let document: EditDocument
        let lutID: LUTID?
        let scale: RenderScale
        let space: WorkingSpace
        let format: ExportFormat?
        /// The `ImageSource` the call named. Recorded so a test can tell *which* image was asked
        /// for — a batch export issues one request per file and they differ only here.
        var source: ImageSource?
    }

    /// Swap in a failure to exercise the caller's error path.
    var shouldFailEncode = false
    var previewResult: CGImage?

    init(previewResult: CGImage? = FakeRenderEngine.solidImage()) {
        self.previewResult = previewResult
    }

    func makeCGImage(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace
    ) -> sending CGImage? {
        previewRequests.append(Request(
            document: document, lutID: lut?.lutID, scale: scale, space: space, format: nil,
            source: source
        ))
        // Rebuilt per call rather than handing out the stored one: the result is `sending`, so it has
        // to be an image nothing else holds a reference to.
        return Self.solidImage()
    }

    func encode(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        format: ExportFormat,
        quality: CGFloat,
        space: WorkingSpace
    ) throws -> Data {
        encodeRequests.append(Request(
            document: document, lutID: lut?.lutID, scale: scale, space: space, format: format,
            source: source
        ))
        if shouldFailEncode { throw ImageError.exportFailed }
        return Data("fake-\(format.rawValue)".utf8)
    }

    func histogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace,
        maxDimension: Int
    ) -> HistogramData? {
        histogramRequests.append(Request(
            document: document, lutID: lut?.lutID, scale: scale, space: space, format: nil,
            source: source
        ))
        // A recognisable tally rather than `nil`: a caller that drops the result would otherwise be
        // indistinguishable from one that publishes it.
        var bins = [Int](repeating: 0, count: 256)
        bins[128] = 1
        return HistogramData(red: bins, green: bins, blue: bins, luma: bins)
    }

    /// How many times the app asked for the cube-filter cache to be dropped.
    ///
    /// A count rather than a flag: the interesting failures are "never" and "on every render", and a
    /// Bool cannot tell those apart from "once, when the library was rescanned".
    private(set) var invalidateCount = 0

    func invalidateLUTCache() { invalidateCount += 1 }

    /// How many times the app asked for capabilities. The probe costs ~25 ms, so "once per image
    /// open" is a requirement, not a detail — a count is the only way to see it.
    private(set) var capabilityProbeCount = 0

    /// What the fake reports. `nil` models a standard image.
    ///
    /// Distinctively seeded rather than `.everyGateOpen`: that value leaves every seed at its
    /// field default, so a getter reading a seed and a getter returning a hardcoded constant produce
    /// the same number and no test can tell them apart. See `RAWCapabilities.distinctivelySeeded`.
    var stubbedCapabilities: RAWCapabilities? = .distinctivelySeeded

    /// Whether an incoming probe should park until `releaseProbe()` is called.
    ///
    /// **The in-flight state is a real state, and a state you cannot hold still is a state you
    /// cannot assert.** `AppViewModel.developPanelState` is `.probing` between "the image opened"
    /// and "the probe answered" — 25–170 ms in the app, and effectively zero against this fake, so a
    /// test racing it would be a flake either way it landed. Gating the probe makes that window last
    /// as long as the test needs.
    private var probeIsGated = false

    /// **All** parked probes, oldest first — not one slot.
    ///
    /// It was one slot until the second opposition pass, and that silently broke the only test that
    /// needed two: a second parked probe overwrote the first's continuation, so the first was never
    /// resumed. The Swift runtime says so out loud — *"SWIFT TASK CONTINUATION MISUSE:
    /// rawCapabilities(for:) leaked its continuation without resuming it"* — but XCTest does not fail
    /// on it, so `testASuccessfulOpenStillReplacesThePreviousProbesAnswer` passed even with
    /// `refreshCapabilities()`'s cancellation deleted, which is the exact thing its failure message
    /// claims to pin. Measured, both before and after this fix.
    private var parkedProbes: [CheckedContinuation<Void, Never>] = []

    func gateProbe() { probeIsGated = true }

    /// How many probes are parked right now — lets a test wait for a second one before releasing.
    var parkedProbeCount: Int { parkedProbes.count }

    /// Let every parked probe finish, and stop parking new ones.
    ///
    /// Ordering note for callers: wait until `capabilityProbeCount` has moved before releasing. The
    /// count is incremented and the continuation stored in the same actor-synchronous run as the
    /// suspension, so an *external* read of the count that returns 1 can only have been serviced
    /// after this actor reached that suspension point — the continuation is therefore already
    /// stored, and `releaseProbe()` cannot no-op past a probe that has not parked yet.
    func releaseProbe() {
        probeIsGated = false
        let parked = parkedProbes
        parkedProbes = []
        parked.forEach { $0.resume() }
    }

    /// Resume only the most recently parked probe, leaving older ones suspended.
    ///
    /// Ordering control is what makes a superseded-probe test *falsifiable*: release the current
    /// image's probe first, let its answer land, then release the stale one and assert it did not
    /// overwrite. Releasing them together makes the outcome depend on resume order, which is a flake
    /// rather than an assertion.
    func releaseNewestProbe() {
        guard let newest = parkedProbes.popLast() else { return }
        newest.resume()
    }

    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities? {
        capabilityProbeCount += 1
        // **Snapshot the stub before suspending.** Read after the await, every parked probe returns
        // whatever the stub happens to be at release time, so two probes cannot be told apart and a
        // test cannot show that the *right* one won. This is the "wrote a value that equals the
        // default" weakness in its timing form.
        let answer = stubbedCapabilities
        if probeIsGated {
            await withCheckedContinuation { parkedProbes.append($0) }
        }
        return answer
    }

    func setStubbedCapabilities(_ value: RAWCapabilities?) { stubbedCapabilities = value }

    func setShouldFailEncode(_ value: Bool) { shouldFailEncode = value }

    /// A 2×2 opaque image — enough to be a real `CGImage`, cheap enough to make per call.
    static func solidImage() -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(red: 0.5, green: 0.25, blue: 0.75, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return ctx.makeImage()
    }
}
