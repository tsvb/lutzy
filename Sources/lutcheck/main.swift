import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Foundation
@testable import LUTzyKit

// Feed the kernel a known LINEAR value and read it back in the same linear
// space, so no gamma round-trip can contaminate the measurement. The kernel's
// contract is: linear Rec.709 in → V-Log/V-Gamut out. That is what is checked.
func adapterVLog(linearInput: Float) -> Float {
    let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    var input: [Float] = [linearInput, linearInput, linearInput, 1.0]
    let img = input.withUnsafeMutableBytes { ptr in
        CIImage(bitmapData: Data(bytes: ptr.baseAddress!, count: 16),
                bytesPerRow: 16, size: CGSize(width: 1, height: 1),
                format: .RGBAf, colorSpace: linear)
    }
    let out = VLogInputAdapter.encode(img)
    var px = [Float](repeating: 0, count: 4)
    ctx.render(out, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
               format: .RGBAf, colorSpace: linear)
    return px[0]
}

// Expected: linear_to_vlog(REC709_TO_VGAMUT · [x,x,x]), from lutcraft.
let cases: [(Float, Float)] = [
    (0.0, 0.12500), (0.0272, 0.24936), (0.1473, 0.40337), (0.2140, 0.44070), (1.0, 0.59912),
]
var maxErr: Float = 0
for (lin, expect) in cases {
    let got = adapterVLog(linearInput: lin)
    let err = abs(got - expect)
    maxErr = max(maxErr, err)
    print(String(format: "linear %.4f -> V-Log %.5f  (expect %.5f, err %.5f)", lin, got, expect, err))
}

let vlogTag = CubeLUT.resolveInputSpace(photoStyle: "VLOG", name: "x")
let stdTag = CubeLUT.resolveInputSpace(photoStyle: "STD", name: "x")
let byName = CubeLUT.resolveInputSpace(photoStyle: nil, name: "fuji-vlog-velvia")
let plain = CubeLUT.resolveInputSpace(photoStyle: nil, name: "teal-orange")
let tagsOK = vlogTag == .vlog && stdTag == .display && byName == .vlog && plain == .display
let adapterOK = maxErr < 0.01
print("adapter max error \(maxErr) -> \(adapterOK ? "PASS" : "FAIL")")
print("tag detection -> \(tagsOK ? "PASS" : "FAIL")")

// --- source-space detection -------------------------------------------------
// Readings taken from real material: a V-Log frame stops at its black point,
// bunches around mid grey and is flat; a rendered photo has real black and
// colour; a grey card has no range to judge by.
typealias R = SourceSpaceDetector.Reading
let detectionCases: [(String, R, SourceSpace?)] = [
    ("V-Log frame",        R(low: 0.243, high: 0.629, median: 0.377, saturation: 0.12), .vlog),
    ("V-Log, black border", R(low: 0.128, high: 0.700, median: 0.400, saturation: 0.18), .vlog),
    ("rendered photo",     R(low: 0.046, high: 0.980, median: 0.350, saturation: 0.45), .display),
    ("deep-black photo",   R(low: 0.001, high: 0.990, median: 0.250, saturation: 0.55), .display),
    ("flat grey card",     R(low: 0.420, high: 0.420, median: 0.420, saturation: 0.00), nil),
    ("matte low-contrast", R(low: 0.250, high: 0.600, median: 0.420, saturation: 0.40), nil),
]
var detectionOK = true
for (name, reading, expect) in detectionCases {
    let got = SourceSpaceDetector.classify(reading)
    let ok = got == expect
    detectionOK = detectionOK && ok
    print("detect \(name.padding(toLength: 20, withPad: " ", startingAt: 0)) -> \(got.map(\.rawValue) ?? "unknown")  \(ok ? "ok" : "EXPECTED \(expect.map(\.rawValue) ?? "unknown")")")
}
print("source detection -> \(detectionOK ? "PASS" : "FAIL")")


// (moved below)

// Isolate the harness: a pass-through kernel must return exactly what went in.
func passthrough(_ v: Float) -> Float {
    let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    var input: [Float] = [v, v, v, 1.0]
    let img = input.withUnsafeMutableBytes { ptr in
        CIImage(bitmapData: Data(bytes: ptr.baseAddress!, count: 16),
                bytesPerRow: 16, size: CGSize(width: 1, height: 1),
                format: .RGBAf, colorSpace: linear)
    }
    let k = CIColorKernel(source: "kernel vec4 p(__sample s){return s;}")!
    let out = k.apply(extent: img.extent, arguments: [img])!
    var px = [Float](repeating: 0, count: 4)
    ctx.render(out, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
               format: .RGBAf, colorSpace: linear)
    return px[0]
}
print(String(format: "passthrough 1.0 -> %.5f, 0.5 -> %.5f, 0.2140 -> %.5f",
             passthrough(1.0), passthrough(0.5), passthrough(0.2140)))

// Isolate linear_to_vlog: feed vg directly, identity matrix path in the kernel.
func rawVLog(_ v: Float) -> Float {
    let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    var input: [Float] = [v, v, v, 1.0]
    let img = input.withUnsafeMutableBytes { p in
        CIImage(bitmapData: Data(bytes: p.baseAddress!, count: 16), bytesPerRow: 16,
                size: CGSize(width: 1, height: 1), format: .RGBAf, colorSpace: linear)
    }
    let src = """
    kernel vec4 f(__sample s){
        vec3 x = max(s.rgb, 0.0);
        vec3 lo = 5.6 * x + 0.125;
        vec3 hi = 0.241514 * log(max(x + 0.00873, 1e-6)) / log(10.0) + 0.598206;
        return vec4(mix(lo, hi, step(vec3(0.01), x)), s.a);
    }
    """
    let k = CIColorKernel(source: src)!
    let out = k.apply(extent: img.extent, arguments: [img])!
    var px = [Float](repeating: 0, count: 4)
    ctx.render(out, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
               format: .RGBAf, colorSpace: linear)
    return px[0]
}
print(String(format: "rawVLog(1.0)=%.5f expect 0.59912 | rawVLog(0.18)=%.5f expect 0.42331",
             rawVLog(1.0), rawVLog(0.18)))

// --- end to end: a real V-Log LUT through the real pipeline ------------------
// Proves the wiring, not just the pieces: a display-referred grey must come out
// of the pipeline having gone through the adapter *and* the LUT, and a
// display-input LUT must not touch the adapter at all.
func pipelineGrey(lutPath: String, sourceSpace: SourceSpace, input: Float) -> Float? {
    guard let lut = try? CubeLUT(url: URL(fileURLWithPath: lutPath)) else { return nil }
    // The same context the app builds — colour management ON. A context with
    // `workingColorSpace: NSNull()` measures a different pipeline than the one
    // that ships, and hid the very conversion this is about.
    let ctx = CIContext()
    let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    var pixel: [Float] = [input, input, input, 1.0]
    let img = pixel.withUnsafeMutableBytes { p in
        CIImage(bitmapData: Data(bytes: p.baseAddress!, count: 16), bytesPerRow: 16,
                size: CGSize(width: 1, height: 1), format: .RGBAf,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
    var doc = EditDocument()
    doc.lut = LUTSettings(lutID: lut.lutID, intensity: 1.0)
    doc.sourceSpace = sourceSpace
    let out = RenderPipeline.buildImage(
        developed: img, document: doc, lut: lut,
        sourceIsVLog: sourceSpace == .vlog
    )
    var px = [Float](repeating: 0, count: 4)
    // Read back as sRGB code values: a LUT emits a finished picture's codes,
    // and lutcraft's expected numbers are in exactly those terms.
    ctx.render(out, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
               format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    return px[0]
}

let vlogLUT = "/Users/world4jason/code_ground/claude lut/out/lumix-s9-vlog/luts/fuji/fuji-vlog-provia.cube"
var pipelineOK = true
if FileManager.default.fileExists(atPath: vlogLUT) {
    let lut = try! CubeLUT(url: URL(fileURLWithPath: vlogLUT))
    print("loaded \(lut.name): size \(lut.size), inputSpace \(lut.inputSpace), tag \(lut.photoStyleTag ?? "none")")
    pipelineOK = lut.inputSpace == .vlog
    // The two source settings must actually route differently: a display grey
    // becomes V-Log 0.4034 while a V-Log grey stays 0.42, so the same input
    // lands on two different entries of the same cube. Which one is brighter is
    // a property of this LUT, not of the wiring — the exact values are checked
    // against lutcraft below.
    let viaAdapter = pipelineGrey(lutPath: vlogLUT, sourceSpace: .display, input: 0.42) ?? -1
    let direct = pipelineGrey(lutPath: vlogLUT, sourceSpace: .vlog, input: 0.42) ?? -1
    print(String(format: "mid grey via adapter -> %.4f | claimed already V-Log -> %.4f", viaAdapter, direct))
    pipelineOK = pipelineOK && abs(viaAdapter - direct) > 0.02 && viaAdapter > 0.02
    print("pipeline routing -> \(pipelineOK ? "PASS" : "FAIL")")
} else {
    print("pipeline routing -> SKIP (no V-Log LUT on this machine)")
}


// --- the file's own account of its space ------------------------------------
// Metadata is evidence where the pixel detector only has inference, so `.auto`
// reads it first. These cover what it must and must not conclude — notably that
// a plain sRGB-tagged JPEG says *nothing*, because a DC-S9 shooting V-Log forces
// sRGB and reading that tag as display-referred would misfire on the exact case
// this feature exists for.
var metadataOK = true
@MainActor func writeJPEG(description: String?, to url: URL) -> Bool {
    var pixels = [UInt8](repeating: 128, count: 4 * 8 * 8)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: &pixels, width: 8, height: 8, bitsPerComponent: 8,
                              bytesPerRow: 32, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { return false }
    var properties: [String: Any] = [:]
    if let description {
        properties[kCGImagePropertyTIFFDictionary as String] =
            [kCGImagePropertyTIFFImageDescription as String: description]
    }
    CGImageDestinationAddImage(dest, image, properties as CFDictionary)
    return CGImageDestinationFinalize(dest)
}

let scratch = FileManager.default.temporaryDirectory
@MainActor func metadataCase(_ label: String, description: String?, expect: SourceSpace?) {
    let url = scratch.appendingPathComponent("lutcheck-\(abs(label.hashValue)).jpg")
    guard writeJPEG(description: description, to: url) else {
        print("metadata \(label) -> FAIL (could not write fixture)"); metadataOK = false; return
    }
    defer { try? FileManager.default.removeItem(at: url) }
    let found = SourceSpaceMetadata.read(ImageSource(url: url, nativeExtent: CGSize(width: 8, height: 8)))
    let ok = found?.space == expect
    metadataOK = metadataOK && ok
    print("metadata \(label.padding(toLength: 30, withPad: " ", startingAt: 0)) -> \(found.map { "\($0.space) (\($0.evidence))" } ?? "nothing")  \(ok ? "ok" : "WRONG, wanted \(expect.map(String.init(describing:)) ?? "nothing")")")
}

metadataCase("says V-Log", description: "Recorded in V-Log", expect: .vlog)
metadataCase("says V-Gamut", description: "V-Gamut / V-Log", expect: .vlog)
metadataCase("says S-Log3", description: "Sony S-Log3 clip", expect: .auto)
metadataCase("plain sRGB JPEG", description: nil, expect: nil)
metadataCase("unrelated caption", description: "A log cabin in the snow", expect: nil)

// A RAW is developed into a rendered picture whatever the sensor recorded, so
// the decode path settles it without reading the file at all.
let rawFinding = SourceSpaceMetadata.read(
    ImageSource(url: URL(fileURLWithPath: "/nonexistent/frame.rw2"), nativeExtent: CGSize(width: 8, height: 8)))
let rawOK = rawFinding?.space == .display
metadataOK = metadataOK && rawOK
print("metadata RAW file                       -> \(rawFinding?.space.label ?? "nothing")  \(rawOK ? "ok" : "WRONG")")
print("metadata reading -> \(metadataOK ? "PASS" : "FAIL")")


// --- does the cube get indexed with the right number? -----------------------
// The V-Log path owns its encoding end to end: the adapter (or the code-value
// recovery, for an already-V-Log source) writes V-Log codes, `CIColorCube`
// indexes them raw, and the output codes are decoded back to linear. These
// numbers come from lutcraft sampling the same cube trilinearly, which is what
// Core Image does — sampling it tetrahedrally instead moves them by ~0.01 and
// says nothing about whether the wiring is right.
if FileManager.default.fileExists(atPath: vlogLUT) {
    // display 0.42 -> linear 0.1473 -> V-Log 0.4034 -> cube -> 0.3243
    let adapted = pipelineGrey(lutPath: vlogLUT, sourceSpace: .display, input: 0.42) ?? -1
    // already V-Log 0.42 -> cube -> 0.3786, untouched on the way in
    let recovered = pipelineGrey(lutPath: vlogLUT, sourceSpace: .vlog, input: 0.42) ?? -1
    let adaptedOK = abs(adapted - 0.3243) < 0.01
    let recoveredOK = abs(recovered - 0.3786) < 0.01
    print(String(format: "display 0.42 through adapter -> %.4f (want 0.3243) -> %@",
                 adapted, adaptedOK ? "PASS" : "FAIL"))
    print(String(format: "V-Log 0.42 straight in       -> %.4f (want 0.3786) -> %@",
                 recovered, recoveredOK ? "PASS" : "FAIL"))
    pipelineOK = pipelineOK && adaptedOK && recoveredOK
}

exit(adapterOK && tagsOK && detectionOK && pipelineOK && metadataOK ? 0 : 1)
