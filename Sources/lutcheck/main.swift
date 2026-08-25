import AppKit
import CoreImage
import simd
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
    guard let out = VLogInputAdapter.encode(img) else { return -1 }
    var px = [Float](repeating: 0, count: 4)
    ctx.render(out, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
               format: .RGBAf, colorSpace: linear)
    return px[0]
}

// Expected values from lutcraft's own forward transform, inverted exactly.
// The adapter's input is display *linear* — a picture that has already been
// rendered — so the render is undone before the V-Gamut matrix and the V-Log
// encode. Tolerance is tight on purpose: a closed-form inverse that needed a
// loose one would not be closed-form.
let adapterCases: [(input: Float, expected: Float)] = [
    (0.0272, 0.34409),
    (0.1473, 0.43340),
    (0.2140, 0.45912),
    (1.0000, 1.00000),
]
var adapterOK = true
var adapterWorst: Float = 0
for probe in adapterCases {
    let got = adapterVLog(linearInput: probe.input)
    let error = abs(got - probe.expected)
    adapterWorst = max(adapterWorst, error)
    adapterOK = adapterOK && error < 0.0005
    print(String(format: "display linear %.4f -> V-Log %.5f  (expect %.5f, err %.5f)",
                 probe.input, got, probe.expected, error))
}
print(String(format: "adapter max error %.6f -> %@", adapterWorst, adapterOK ? "PASS" : "FAIL"))

// Which space a LUT declares it wants, by tag and by name.
let vlogTag = CubeLUT.resolveInputSpace(photoStyle: "VLOG", name: "x")
let stdTag = CubeLUT.resolveInputSpace(photoStyle: "STD", name: "x")
let byName = CubeLUT.resolveInputSpace(photoStyle: nil, name: "fuji-vlog-velvia")
let plain = CubeLUT.resolveInputSpace(photoStyle: nil, name: "teal-orange")
let tagsOK = vlogTag == .vlog && stdTag == .display && byName == .vlog && plain == .display
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
/// Write a fixture image. PNG when it has to carry colour: JPEG's 4:2:0 chroma
/// subsampling averages a per-pixel colour ramp on an 8×8 away to near-neutral,
/// which reads exactly like a pipeline that has lost colour and is not one.
@MainActor func writeJPEG(description: String?, to url: URL, colourful: Bool = false, seed: Int = 0) -> Bool {
    // Flat grey is the right fixture for a metadata test and the wrong one for
    // a "do these cells differ" test: these LUTs are built to leave mid grey
    // near mid grey, so nine film simulations land within a few code values of
    // each other on it. A saturated ramp is where they separate.
    var pixels = [UInt8](repeating: 128, count: 4 * 8 * 8)
    if colourful {
        // `seed` shifts the ramp so a set of fixtures is a set of *different*
        // pictures. Without it every one is byte-identical, and a check that
        // asks "is the right image on screen" cannot tell.
        for y in 0..<8 {
            for x in 0..<8 {
                let i = (y * 8 + x) * 4
                pixels[i]     = UInt8((x * 36 + seed * 29) % 256)
                pixels[i + 1] = UInt8((y * 36 + seed * 53) % 256)
                pixels[i + 2] = UInt8(((x + y) * 18 + seed * 71) % 256)
            }
        }
    }
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: &pixels, width: 8, height: 8, bitsPerComponent: 8,
                              bytesPerRow: 32, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
              url as CFURL,
              (colourful ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil)
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
    // display 0.42 -> linear 0.1473 -> undo the render -> scene 0.19907 ->
    // V-Log 0.43341 -> cube -> 0.42357. The old expectation here was 0.3243,
    // computed when the adapter skipped the inverse entirely; it was the bug.
    let adapted = pipelineGrey(lutPath: vlogLUT, sourceSpace: .display, input: 0.42) ?? -1
    // already V-Log 0.42 -> cube -> 0.3786, untouched on the way in
    let recovered = pipelineGrey(lutPath: vlogLUT, sourceSpace: .vlog, input: 0.42) ?? -1
    let adaptedOK = abs(adapted - 0.42357) < 0.005
    let recoveredOK = abs(recovered - 0.3786) < 0.01
    print(String(format: "display 0.42 through adapter -> %.4f (want 0.42357) -> %@",
                 adapted, adaptedOK ? "PASS" : "FAIL"))
    print(String(format: "V-Log 0.42 straight in       -> %.4f (want 0.3786) -> %@",
                 recovered, recoveredOK ? "PASS" : "FAIL"))
    pipelineOK = pipelineOK && adaptedOK && recoveredOK
}

// --- colour, not just neutrals ----------------------------------------------
// Every measurement above this line used greys, and a grey cannot tell a
// correct 3x3 matrix from one whose rows have collapsed, nor a LUT that carries
// colour from one that flattens it. This feeds a saturated triplet through and
// checks each channel separately.
@MainActor func pipelineColour(lutPath: String, sourceSpace: SourceSpace, rgb: (Float, Float, Float)) -> [Float]? {
    guard let lut = try? CubeLUT(url: URL(fileURLWithPath: lutPath)) else { return nil }
    let ctx = CIContext()
    var pixel: [Float] = [rgb.0, rgb.1, rgb.2, 1.0]
    let img = pixel.withUnsafeMutableBytes { p in
        CIImage(bitmapData: Data(bytes: p.baseAddress!, count: 16), bytesPerRow: 16,
                size: CGSize(width: 1, height: 1), format: .RGBAf,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
    var doc = EditDocument()
    doc.lut = LUTSettings(lutID: lut.lutID, intensity: 1.0)
    doc.sourceSpace = sourceSpace
    let out = RenderPipeline.buildImage(developed: img, document: doc, lut: lut,
                                        sourceIsVLog: sourceSpace == .vlog)
    var px = [Float](repeating: 0, count: 4)
    ctx.render(out, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
               format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    return Array(px[0..<3])
}

// Expected values are lutcraft's, computed through the same corrected chain
// (undo the render, V-Gamut, V-Log, then provia). They agree to 0.0008, which
// is Core Image sampling the cube trilinearly where lutcraft samples it
// tetrahedrally — not slack in the conversion.
var colourOK = true
if FileManager.default.fileExists(atPath: vlogLUT) {
    let colourCases: [(rgb: (Float, Float, Float), expected: [Float])] = [
        ((0.80, 0.20, 0.20), [0.9191, 0.2138, 0.1981]),
        ((0.20, 0.70, 0.30), [0.2761, 0.7067, 0.1453]),
        ((0.15, 0.30, 0.85), [0.2117, 0.3095, 0.9440]),
    ]
    for probe in colourCases {
        guard let out = pipelineColour(lutPath: vlogLUT, sourceSpace: .display, rgb: probe.rgb) else { continue }
        let error = zip(out, probe.expected).map { abs($0 - $1) }.max() ?? 1
        let ok = error < 0.002
        colourOK = colourOK && ok
        print(String(format: "colour in (%.2f %.2f %.2f) -> out (%.4f %.4f %.4f), want (%.4f %.4f %.4f), err %.4f  %@",
                     probe.rgb.0, probe.rgb.1, probe.rgb.2, out[0], out[1], out[2],
                     probe.expected[0], probe.expected[1], probe.expected[2], error, ok ? "ok" : "WRONG"))
    }
    print("colour through the V-Log path -> \(colourOK ? "PASS" : "FAIL")")
}


// --- tags agree with lutcraft ----------------------------------------------
// The whole point of measuring tags rather than typing them is that a hundred
// files get described consistently — which only holds if the app and the
// offline generator describe them the *same way*. This replays lutcraft's own
// output for every LUT it can find and compares tag for tag.
var tagsMatchOK = true
let expectedTags = "Fixtures/lutcraft-tags.tsv"
if let table = try? String(contentsOfFile: expectedTags, encoding: .utf8) {
    var checked = 0, mismatched = 0
    let roots = ["/Users/world4jason/code_ground/claude lut/out/lumix-s9-vlog/luts"]
    var byStem: [String: URL] = [:]
    for root in roots {
        let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "cube" else { continue }
            byStem[url.deletingPathExtension().lastPathComponent] = url
        }
    }
    for line in table.split(separator: "\n") {
        let fields = line.components(separatedBy: "\t")
        guard fields.count == 4, let url = byStem[fields[0]], let lut = try? CubeLUT(url: url) else { continue }
        checked += 1
        let mine = LUTProfiler.autoTags(LUTProfiler.measure(lut), inputSpace: lut.inputSpace)
        let theirs = fields[3].split(separator: ",").map(String.init).sorted()
        if mine != theirs {
            mismatched += 1
            if mismatched <= 5 {
                print("tags \(fields[0]): mine \(mine) vs lutcraft \(theirs)")
            }
        }
    }
    tagsMatchOK = checked > 0 && mismatched == 0
    print("tags vs lutcraft -> \(checked - mismatched)/\(checked) agree -> \(tagsMatchOK ? "PASS" : "FAIL")")
} else {
    print("tags vs lutcraft -> SKIP (no fixture)")
}


// --- the tag store ----------------------------------------------------------
// The one rule that matters: a rescan re-derives measured tags and must never
// touch typed ones. Measured tags are claims about the file and should be
// replaced when the file changes; a typed "日系" cannot be recovered by any
// amount of measuring, so losing it to an automated pass is unrecoverable.
var storeOK = true
if let lut = try? CubeLUT(url: URL(fileURLWithPath: vlogLUT)) {
    let storeURL = scratch.appendingPathComponent("lutcheck-tags.json")
    try? FileManager.default.removeItem(at: storeURL)
    defer { try? FileManager.default.removeItem(at: storeURL) }

    let store = LUTTagStore(fileURL: storeURL)
    store.indexNow([lut])
    let measured = store.tags(for: lut)
    let measuredOK = measured.isEmpty == false && measured == LUTProfiler.autoTags(LUTProfiler.measure(lut), inputSpace: lut.inputSpace)
    print("store measured on index -> \(measured) -> \(measuredOK ? "PASS" : "FAIL")")

    store.addTag("日系", to: lut)
    store.addTag("日系", to: lut)          // adding twice must not duplicate
    let afterTyping = store.tags(for: lut)
    let typedOK = store.typedTags(for: lut) == ["日系"] && afterTyping.contains("日系")
    print("store typed tag added once -> \(store.typedTags(for: lut)) -> \(typedOK ? "PASS" : "FAIL")")

    // A rescan that actually re-measures — the tagger rules moved on — must
    // put the measured tags back and leave the typed one alone. Re-indexing
    // without forcing that would be a no-op and would prove nothing.
    store.forceRemeasure()
    store.indexNow([lut])
    let survivedOK = store.typedTags(for: lut) == ["日系"]
        && store.tags(for: lut) == afterTyping
        && store.tags(for: lut).contains(measured[0])
    print("store re-measures and keeps the typed tag -> \(survivedOK ? "PASS" : "FAIL")")

    // Filtering is an AND across the required set, and an empty filter matches.
    let anyMeasured = measured.first ?? ""
    let filterOK = store.matches(lut, required: [])
        && store.matches(lut, required: [anyMeasured, "日系"])
        && store.matches(lut, required: ["沒有這個標籤"]) == false
    print("store filter is an AND, empty matches all -> \(filterOK ? "PASS" : "FAIL")")

    // Persistence: what was typed has to still be there next launch.
    store.flush()
    let reloaded = LUTTagStore(fileURL: storeURL)
    let persistOK = reloaded.typedTags(for: lut) == ["日系"] && reloaded.tags(for: lut) == afterTyping
    print("store survives a reload -> \(persistOK ? "PASS" : "FAIL")")

    store.removeTag("日系", from: lut)
    let removedOK = store.typedTags(for: lut).isEmpty && store.tags(for: lut) == measured
    print("store typed tag removable -> \(removedOK ? "PASS" : "FAIL")")

    storeOK = measuredOK && typedOK && survivedOK && filterOK && persistOK && removedOK
    print("tag store -> \(storeOK ? "PASS" : "FAIL")")
} else {
    print("tag store -> SKIP (no V-Log LUT on this machine)")
}


// --- the difference image ---------------------------------------------------
// Black means "these two agree". That is the whole claim the layout makes, so
// it is the one to check: identical input must come out black, and a known
// difference must come out at the amplified size rather than at the raw one.
var diffOK = true
@MainActor func solidImage(_ value: Int) -> NSImage {
    var pixels = [UInt8](repeating: UInt8(value), count: 4 * 16 * 16)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: &pixels, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let image = ctx.makeImage()!
    return NSImage(cgImage: image, size: NSSize(width: 16, height: 16))
}
@MainActor func centreValue(_ image: NSImage?) -> Int? {
    guard let image, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let colour = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
    else { return nil }
    return Int((colour.redComponent * 255).rounded())
}

let same = DifferenceComposer.compose(base: solidImage(128), graded: solidImage(128))
let sameValue = centreValue(same) ?? -1
let sameOK = sameValue == 0
print("difference of identical frames -> \(sameValue) -> \(sameOK ? "PASS" : "FAIL")")

// 138 - 128 = 10 code values; at the default gain of 8 that is 80.
let apart = DifferenceComposer.compose(base: solidImage(128), graded: solidImage(138))
let apartValue = centreValue(apart) ?? -1
let apartOK = abs(apartValue - 80) <= 2
print("difference of 10 code values at x8 -> \(apartValue) (want 80) -> \(apartOK ? "PASS" : "FAIL")")

// Unamplified, the same pair must come back at its true size — proof the gain
// is a display choice and not baked into the measurement.
let unamplified = DifferenceComposer.compose(base: solidImage(128), graded: solidImage(138), gain: 1)
let rawValue = centreValue(unamplified) ?? -1
let unamplifiedOK = abs(rawValue - 10) <= 2
print("difference at x1 -> \(rawValue) (want 10) -> \(unamplifiedOK ? "PASS" : "FAIL")")

// Mismatched sizes cannot be subtracted, and must say so rather than guess.
let mismatch = DifferenceComposer.compose(base: solidImage(128), graded: nil)
let mismatchOK = mismatch == nil
print("difference with a missing side -> \(mismatchOK ? "PASS" : "FAIL")")

diffOK = sameOK && apartOK && unamplifiedOK && mismatchOK
print("difference -> \(diffOK ? "PASS" : "FAIL")")


// --- importing into the app's own library -----------------------------------
// The complaint this answers is having to re-point at a folder every launch, so
// the rules that matter are the ones that make a library survive being added to
// repeatedly: importing the same thing twice is a no-op, two different LUTs that
// happen to share a name both survive, and a folder keeps its name as the
// category.
var importOK = true
do {
    let root = scratch.appendingPathComponent("lutcheck-import-\(UUID().uuidString)")
    let source = root.appendingPathComponent("source/fuji")
    let library = root.appendingPathComponent("library")
    try? FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    func writeCube(_ url: URL, white: Double) {
        var text = "LUT_3D_SIZE 2\n"
        for index in 0..<8 {
            let v = index == 7 ? white : Double(index) / 8.0
            text += "\(v) \(v) \(v)\n"
        }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
    writeCube(source.appendingPathComponent("a.cube"), white: 1.0)
    writeCube(source.appendingPathComponent("b.cube"), white: 0.9)

    // A folder import: both files land under the folder's own name.
    let first = LUTLibrary.copyIn([source], to: library)
    let landed = library.appendingPathComponent("fuji")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: landed.path))?.sorted() ?? []
    let folderOK = first == LUTLibrary.ImportResult(imported: 2, duplicates: 0, failed: 0)
        && names == ["a.cube", "b.cube"]
    print("import a folder -> \(first) into \(landed.lastPathComponent)/\(names) -> \(folderOK ? "PASS" : "FAIL")")

    // The same folder again is a no-op, not a second copy of everything.
    let again = LUTLibrary.copyIn([source], to: library)
    let repeatOK = again == LUTLibrary.ImportResult(imported: 0, duplicates: 2, failed: 0)
    print("import the same folder twice -> \(again) -> \(repeatOK ? "PASS" : "FAIL")")

    // A nested folder keeps its shape. Flattening it loses the filing the
    // user did, and a second import of the same tree would then land
    // differently from the first.
    let nested = root.appendingPathComponent("vendor/Fuji/Film")
    let nestedBW = root.appendingPathComponent("vendor/Fuji/BW")
    try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: nestedBW, withIntermediateDirectories: true)
    writeCube(nested.appendingPathComponent("provia.cube"), white: 0.81)
    writeCube(nestedBW.appendingPathComponent("acros.cube"), white: 0.82)

    let deepLibrary = root.appendingPathComponent("deep")
    try? FileManager.default.createDirectory(at: deepLibrary, withIntermediateDirectories: true)
    let deep = LUTLibrary.copyIn([root.appendingPathComponent("vendor/Fuji")], to: deepLibrary)
    let landedDeep = FileManager.default.fileExists(atPath: deepLibrary.appendingPathComponent("Fuji/Film/provia.cube").path)
        && FileManager.default.fileExists(atPath: deepLibrary.appendingPathComponent("Fuji/BW/acros.cube").path)
    let deepOK = deep.imported == 2 && landedDeep
    print("import keeps a nested folder's shape -> \(deep) -> \(deepOK ? "PASS" : "FAIL")")

    // And a second import of the same tree is a no-op, not a reshuffle.
    let deepAgain = LUTLibrary.copyIn([root.appendingPathComponent("vendor/Fuji")], to: deepLibrary)
    let deepRepeatOK = deepAgain.imported == 0 && deepAgain.duplicates == 2
    print("import the same nested tree twice -> \(deepAgain) -> \(deepRepeatOK ? "PASS" : "FAIL")")

    // A *different* LUT that shares a name is kept, under a numbered name.
    let clash = root.appendingPathComponent("clash")
    try? FileManager.default.createDirectory(at: clash, withIntermediateDirectories: true)
    writeCube(clash.appendingPathComponent("a.cube"), white: 0.5)
    let clashed = LUTLibrary.copyIn([clash.appendingPathComponent("a.cube")], to: library)
    let atRoot = (try? FileManager.default.contentsOfDirectory(atPath: library.path))?.sorted() ?? []
    let clashOK = clashed.imported == 1 && atRoot.contains("a.cube")
    print("import a name clash -> \(atRoot) -> \(clashOK ? "PASS" : "FAIL")")

    // Anything that is not a cube is reported rather than silently dropped.
    let junk = root.appendingPathComponent("notes.txt")
    try? "hello".write(to: junk, atomically: true, encoding: .utf8)
    let junked = LUTLibrary.copyIn([junk], to: library)
    let junkOK = junked == LUTLibrary.ImportResult(imported: 0, duplicates: 0, failed: 1)
    print("import a non-LUT -> \(junked) -> \(junkOK ? "PASS" : "FAIL")")

    // And the summary says so, including the case where nothing happened.
    let summaryOK = AppViewModel.importSummary(first).contains("Imported 2")
        && AppViewModel.importSummary(again).contains("already in the library")
        && AppViewModel.importSummary(LUTLibrary.ImportResult(imported: 0, duplicates: 0, failed: 0)) == "Nothing to import"
    print("import summary -> \(summaryOK ? "PASS" : "FAIL")")

    importOK = folderOK && repeatOK && clashOK && junkOK && summaryOK && deepOK && deepRepeatOK
}
print("import -> \(importOK ? "PASS" : "FAIL")")

// Removing must never reach outside the app's own folder: everywhere else the
// files belong to the user, and "remove from my library" is not "delete that".
var removeOK = true
if let outside = try? CubeLUT(url: URL(fileURLWithPath: vlogLUT)) {
    let library = LUTLibrary()
    removeOK = library.removeFromLibrary(outside) == false
        && FileManager.default.fileExists(atPath: vlogLUT)
    print("remove refuses a LUT outside the library -> \(removeOK ? "PASS" : "FAIL")")
}


// --- stars and folders ------------------------------------------------------
// A star is a flag, not a tag: it must not turn up in the tag filter row
// alongside 高對比, and it has to survive a reload like everything else keyed by
// content. Moving between folders is a file move, so it is refused outside the
// app's own library for the same reason removing is.
var starOK = true
if let lut = try? CubeLUT(url: URL(fileURLWithPath: vlogLUT)) {
    let storeURL = scratch.appendingPathComponent("lutcheck-stars.json")
    try? FileManager.default.removeItem(at: storeURL)
    defer { try? FileManager.default.removeItem(at: storeURL) }

    let store = LUTTagStore(fileURL: storeURL)
    store.indexNow([lut])
    let tagsBefore = store.tags(for: lut)

    store.toggleFavourite(lut)
    let setOK = store.isFavourite(lut) && store.favouriteCount == 1
    // The star must not leak into the vocabulary.
    let separateOK = store.tags(for: lut) == tagsBefore
        && store.counts.contains { $0.tag.contains("star") || $0.tag == "★" } == false
    print("star set, and kept out of the tag list -> \(setOK && separateOK ? "PASS" : "FAIL")")

    store.flush()
    let reloaded = LUTTagStore(fileURL: storeURL)
    let persistOK = reloaded.isFavourite(lut) && reloaded.favouriteCount == 1
    print("star survives a reload -> \(persistOK ? "PASS" : "FAIL")")

    store.toggleFavourite(lut)
    let clearOK = store.isFavourite(lut) == false && store.favouriteCount == 0
    print("star toggles off -> \(clearOK ? "PASS" : "FAIL")")

    // Re-measuring must not disturb it either.
    store.toggleFavourite(lut)
    store.forceRemeasure()
    store.indexNow([lut])
    let survivesOK = store.isFavourite(lut)
    print("star survives a re-measure -> \(survivesOK ? "PASS" : "FAIL")")

    let library = LUTLibrary()
    let refusedOK = library.move(lut, toCategory: "Anywhere") == false
        && FileManager.default.fileExists(atPath: vlogLUT)
    print("move refuses a LUT outside the library -> \(refusedOK ? "PASS" : "FAIL")")

    starOK = setOK && separateOK && persistOK && clearOK && survivesOK && refusedOK
    print("stars and folders -> \(starOK ? "PASS" : "FAIL")")
}


// --- bulk actions -----------------------------------------------------------
// Starring a mixed selection is the one with a wrong answer that looks right:
// toggling each LUT in turn leaves the already-starred ones unstarred, which is
// never what "star these" meant.
var bulkOK = true
if let lut = try? CubeLUT(url: URL(fileURLWithPath: vlogLUT)) {
    let storeURL = scratch.appendingPathComponent("lutcheck-bulk.json")
    try? FileManager.default.removeItem(at: storeURL)
    defer { try? FileManager.default.removeItem(at: storeURL) }

    // A second LUT, so the selection can be genuinely mixed.
    let others = (try? FileManager.default.contentsOfDirectory(
        at: URL(fileURLWithPath: vlogLUT).deletingLastPathComponent(),
        includingPropertiesForKeys: nil))?
        .filter { $0.pathExtension == "cube" && $0.path != vlogLUT }
        .sorted { $0.path < $1.path } ?? []
    if let second = others.first.flatMap({ try? CubeLUT(url: $0) }) {
        let store = LUTTagStore(fileURL: storeURL)
        store.indexNow([lut, second])
        store.toggleFavourite(lut)          // one starred, one not

        // "Star these" on a mixed selection must end with all of them starred.
        let shouldStar = [lut, second].contains { store.isFavourite($0) == false }
        for candidate in [lut, second] where store.isFavourite(candidate) != shouldStar {
            store.toggleFavourite(candidate)
        }
        let mixedOK = store.isFavourite(lut) && store.isFavourite(second) && store.favouriteCount == 2
        print("bulk star on a mixed selection stars all -> \(mixedOK ? "PASS" : "FAIL")")

        // And again, now that they agree, must clear both.
        let shouldStarAgain = [lut, second].contains { store.isFavourite($0) == false }
        for candidate in [lut, second] where store.isFavourite(candidate) != shouldStarAgain {
            store.toggleFavourite(candidate)
        }
        let clearOK = store.favouriteCount == 0
        print("bulk star again clears all -> \(clearOK ? "PASS" : "FAIL")")

        store.addTag("日系", to: lut)
        store.addTag("日系", to: second)
        let taggedOK = store.typedTags(for: lut) == ["日系"] && store.typedTags(for: second) == ["日系"]
        print("bulk tag applies to every one -> \(taggedOK ? "PASS" : "FAIL")")

        bulkOK = mixedOK && clearOK && taggedOK
        print("bulk actions -> \(bulkOK ? "PASS" : "FAIL")")
    }
}


// --- projects ---------------------------------------------------------------
// A project is a place: its images are inside it, and reopening it puts back
// what was on screen. Both halves are checked here, plus the rule that makes
// projects safe to keep adding to — importing the same pictures twice is a
// no-op, decided by content rather than by name.
var projectOK = true
do {
    let root = scratch.appendingPathComponent("lutcheck-projects-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root)

    let first = store.create(named: "Reference frames")
    let second = store.create(named: "Wedding")
    let createdOK = store.projects.count == 2 && store.current?.id == second.id
    print("project create -> \(store.projects.map(\.name)) current \(store.current?.name ?? "none") -> \(createdOK ? "PASS" : "FAIL")")

    // Images live inside the project, not next to it.
    let images = store.imagesFolder(for: first)
    let insideOK = images.path.hasPrefix(store.folder(for: first).path + "/")
    print("project images live inside it -> \(insideOK ? "PASS" : "FAIL")")

    // Import: a folder of two, then the same folder again.
    let source = root.appendingPathComponent("shoot")
    try? FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    _ = writeJPEG(description: nil, to: source.appendingPathComponent("a.jpg"))
    _ = writeJPEG(description: nil, to: source.appendingPathComponent("b.png"), colourful: true)
    let imported = AppViewModel.copyImages([source], to: images)
    let again = AppViewModel.copyImages([source], to: images)
    let importOnceOK = imported.imported == 2 && again.imported == 0 && again.duplicates == 2
    print("project image import -> \(imported), again \(again) -> \(importOnceOK ? "PASS" : "FAIL")")

    // A non-image is reported rather than copied in.
    let junk = root.appendingPathComponent("notes.txt")
    try? "hello".write(to: junk, atomically: true, encoding: .utf8)
    let junked = AppViewModel.copyImages([junk], to: images)
    let junkOK = junked.imported == 0 && junked.failed == 1
    print("project rejects a non-image -> \(junked) -> \(junkOK ? "PASS" : "FAIL")")

    // The workspace survives a round trip through disk.
    var session = Project.Session()
    session.section = .manager
    session.layout = .grid3x3
    session.selectedLUT = "/some/lut.cube"
    session.cellLUTs = ["/a.cube", nil, "/b.cube"]
    session.imageName = "a.jpg"
    session.tagFilter = ["高對比", "暖調"]
    session.browsedCategory = "fuji"
    session.showingFavouritesOnly = true
    session.sourceSpace = .vlog
    store.updateSession(session)

    let reopened = ProjectStore(root: root)
    let restored = reopened.current?.session
    let sessionOK = restored == session && reopened.current?.id == second.id
    print("project session survives a relaunch -> \(sessionOK ? "PASS" : "FAIL")")

    // A project file from before these fields existed must still open.
    let bare = #"{"id":"\#(UUID().uuidString)","name":"Old","createdAt":"2026-01-01T00:00:00Z","lastOpenedAt":"2026-01-01T00:00:00Z","session":{}}"#
    let oldFolder = root.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
    try? bare.write(to: oldFolder.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let legacyOK = (try? decoder.decode(Project.self, from: Data(bare.utf8)))?.session == Project.Session()
    print("project file without the newer fields still opens -> \(legacyOK ? "PASS" : "FAIL")")

    // Deleting the open one moves to another rather than leaving nothing open.
    store.delete(second)
    let deleteOK = store.projects.count == 1 && store.current?.id == first.id
    print("delete the open project -> falls back to \(store.current?.name ?? "none") -> \(deleteOK ? "PASS" : "FAIL")")

    projectOK = createdOK && insideOK && importOnceOK && junkOK && sessionOK && legacyOK && deleteOK
}
print("projects -> \(projectOK ? "PASS" : "FAIL")")


// --- the editor -------------------------------------------------------------
// Baking has to be exact where it claims to change nothing, and the .cube it
// writes has to be one the camera will take. Both are checked against the real
// LUT rather than a fixture, since the grid and the header are what the DC-S9
// actually reads.
var editorOK = true
if let base = try? CubeLUT(url: URL(fileURLWithPath: vlogLUT)) {
    // A neutral edit must be the identity, to within the float round trip
    // through sRGB decode and encode. Anything larger means the editor moves
    // the picture while claiming not to.
    let untouched = LookBaker.bake(base: base, edit: .neutral)
    let sampled = base.sample((0..<untouched.count).flatMap { index -> [Float] in
        let n = LookBaker.size, m = Float(n - 1)
        let r = index % n, g = (index / n) % n, b = index / (n * n)
        return [Float(r) / m, Float(g) / m, Float(b) / m]
    })
    var worst: Float = 0
    for (index, colour) in untouched.enumerated() {
        worst = max(worst, abs(colour.x - sampled[index * 3]))
        worst = max(worst, abs(colour.y - sampled[index * 3 + 1]))
        worst = max(worst, abs(colour.z - sampled[index * 3 + 2]))
    }
    let identityOK = worst < 0.002
    print(String(format: "editor a neutral edit changes nothing -> worst %.5f -> %@", worst, identityOK ? "PASS" : "FAIL"))

    // Each control has to move the thing it names, in the direction it names.
    func measure(_ edit: LookEdit) -> (lightness: Float, chroma: Float, black: Float) {
        let baked = LookBaker.bake(base: base, edit: edit)
        let n = LookBaker.size, m = n - 1
        func at(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> { baked[(b * n + g) * n + r] }
        let mid = at(m / 2, m / 2, m / 2)
        let lab = OKLab.fromLinear(SIMD3<Float>(
            OKLab.srgbToLinear(mid.x), OKLab.srgbToLinear(mid.y), OKLab.srgbToLinear(mid.z)))
        // A saturated grid corner, for chroma.
        let red = at(m, m / 4, m / 4)
        let redLab = OKLab.fromLinear(SIMD3<Float>(
            OKLab.srgbToLinear(red.x), OKLab.srgbToLinear(red.y), OKLab.srgbToLinear(red.z)))
        let black = at(4, 4, 4)
        return (lab.x, sqrt(redLab.y * redLab.y + redLab.z * redLab.z), (black.x + black.y + black.z) / 3)
    }

    let plain = measure(.neutral)
    var brighter = LookEdit.neutral; brighter.exposure = 1
    var punchier = LookEdit.neutral; punchier.saturation = 1.6
    var duller = LookEdit.neutral; duller.saturation = 0.3
    var lifted = LookEdit.neutral; lifted.blackLift = 0.1

    let exposureOK = measure(brighter).lightness > plain.lightness + 0.05
    let upOK = measure(punchier).chroma > plain.chroma * 1.2
    let downOK = measure(duller).chroma < plain.chroma * 0.6
    let liftOK = measure(lifted).black > plain.black + 0.05
    print("editor exposure raises lightness -> \(exposureOK ? "PASS" : "FAIL")")
    print("editor saturation moves chroma both ways -> \(upOK && downOK ? "PASS" : "FAIL")")
    print("editor black lift raises the shadows -> \(liftOK ? "PASS" : "FAIL")")

    // Stacking a V-Log LUT after a V-Log LUT is the mistake the type check
    // exists to prevent: the second would read a finished picture as scene
    // light. It must be refused rather than applied.
    let stackedWithVLog = LookBaker.bake(base: base, edit: .neutral, stacked: base, stackAmount: 1)
    let refusedOK = zip(stackedWithVLog, untouched).allSatisfy { $0 == $1 }
    print("editor refuses to stack a V-Log LUT after one -> \(refusedOK ? "PASS" : "FAIL")")

    // What it writes has to be a cube the camera reads: 33 points and the tag.
    let text = try? CubeWriter.text(entries: untouched, size: LookBaker.size, title: "Test look")
    let headerOK = (text?.contains("#LUMIXPHOTOSTYLE VLOG") ?? false)
        && (text?.contains("LUT_3D_SIZE 33") ?? false)
    // And it must refuse a grid the camera cannot take.
    var tooBig = false
    do {
        _ = try CubeWriter.text(entries: Array(repeating: SIMD3<Float>(0, 0, 0), count: 65 * 65 * 65),
                                size: 65, title: "Too big")
    } catch { tooBig = true }
    print("editor writes a camera-legal cube -> header \(headerOK), refuses 65 points \(tooBig) -> \(headerOK && tooBig ? "PASS" : "FAIL")")

    // Round trip: what was written must parse back to what was baked.
    let roundTripURL = scratch.appendingPathComponent("lutcheck-edited.cube")
    try? CubeWriter.write(entries: untouched, size: LookBaker.size, title: "Round trip", to: roundTripURL)
    defer { try? FileManager.default.removeItem(at: roundTripURL) }
    var roundTripOK = false
    if let reread = try? CubeLUT(url: roundTripURL) {
        let probe: [Float] = [0.2, 0.5, 0.8, 0.42, 0.42, 0.42, 0.9, 0.1, 0.3]
        let a = base.sample(probe), b = reread.sample(probe)
        let diff = zip(a, b).map { abs($0 - $1) }.max() ?? 1
        roundTripOK = reread.inputSpace == .vlog && diff < 0.002
        print(String(format: "editor round trip through a file -> inputSpace %@, worst %.5f -> %@",
                     String(describing: reread.inputSpace), diff, roundTripOK ? "PASS" : "FAIL"))
    } else {
        print("editor round trip through a file -> FAIL (could not reread)")
    }

    editorOK = identityOK && exposureOK && upOK && downOK && liftOK && refusedOK && headerOK && tooBig && roundTripOK
    print("editor -> \(editorOK ? "PASS" : "FAIL")")
}


// --- exporting a chosen subset ----------------------------------------------
// The manager's reason to exist. Export All could only ever say "all of them";
// this checks that naming a few picks exactly those, that a name which is not
// in the collection is ignored rather than exporting something else, and that
// an empty pick exports nothing at all rather than everything.
var subsetOK = true
if let lut = try? CubeLUT(url: URL(fileURLWithPath: vlogLUT)) {
    let root = scratch.appendingPathComponent("lutcheck-subset-\(UUID().uuidString)")
    let images = root.appendingPathComponent("Images")
    let out = root.appendingPathComponent("out")
    try? FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    for name in ["one", "two", "three"] {
        _ = writeJPEG(description: nil, to: images.appendingPathComponent("\(name).png"), colourful: true)
    }

    let vmProjects = ProjectStore(root: root.appendingPathComponent("Projects"))
    let vmTags = LUTTagStore(fileURL: root.appendingPathComponent("tags.json"))
    let vm = AppViewModel(projects: vmProjects, tags: vmTags)
    vm.collection.loadFromFolder(images)
    await vm.collection.scanCompletion()

    let loadedOK = vm.collection.items.count == 3
    // Two of the three, by name.
    let wanted = Set(vm.collection.items.prefix(2).map(\.displayName))
    let items = vm.collection.items
        .filter { wanted.contains($0.displayName) }
        .map { ExportCoordinator.BatchItem(url: $0.url, data: $0.imageData, name: $0.displayName) }
    let picked = Set(items.map(\.name))
    let pickOK = items.count == 2 && picked == wanted

    let outcome = await vm.export.performBatchExport(items, document: EditDocument(), lut: lut, to: out)
    let written = Set(((try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? [])
        .map { ($0 as NSString).deletingPathExtension })
    // Exported names carry the LUT's name, so compare on the stem.
    let wroteOnlyTheseOK = written.count == 2 && wanted.allSatisfy { name in
        written.contains { $0.hasPrefix((name as NSString).deletingPathExtension) }
    }
    print("subset export -> loaded \(vm.collection.items.count), picked \(items.count), wrote \(written.count) (\(outcome.exported) reported) -> \(loadedOK && pickOK && wroteOnlyTheseOK ? "PASS" : "FAIL")")

    // A name that is not there must select nothing rather than fall back to all.
    let ghost = vm.collection.items.filter { Set(["not-a-file"]).contains($0.displayName) }
    let ghostOK = ghost.isEmpty
    print("subset export ignores an unknown name -> \(ghostOK ? "PASS" : "FAIL")")

    subsetOK = loadedOK && pickOK && wroteOnlyTheseOK && ghostOK
    print("subset export -> \(subsetOK ? "PASS" : "FAIL")")
}


// --- switching images quickly -----------------------------------------------
// Reported symptom: flicking through a set to compare a LUT often "fails to
// switch". Two things could cause that and they need telling apart — the wrong
// image ending up open (a race), or the right one arriving far too late (work
// piling up behind cancelled decodes). This measures both.
var switchOK = true
do {
    let root = scratch.appendingPathComponent("lutcheck-switch-\(UUID().uuidString)")
    let images = root.appendingPathComponent("Images")
    try? FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0..<8 {
        _ = writeJPEG(description: nil, to: images.appendingPathComponent("img\(index).png"),
                      colourful: true, seed: index + 1)
    }

    let vm = AppViewModel(
        projects: ProjectStore(root: root.appendingPathComponent("Projects")),
        tags: LUTTagStore(fileURL: root.appendingPathComponent("tags.json"))
    )
    vm.collection.loadFromFolder(images)
    await vm.collection.scanCompletion()

    func waitFor(_ what: String, _ done: @MainActor () -> Bool, limit: Int = 600) async -> Bool {
        for _ in 0..<limit {
            if done() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        print("switch \(what) -> FAIL (timed out)")
        return false
    }

    let ready = await waitFor("initial scan", { vm.collection.items.count == 8 })
    // `sourceName` is the file name; `displayName` has no extension. Compare
    // like with like, or the check reports a failure that is its own.
    let names = vm.collection.items.map { $0.url?.lastPathComponent ?? $0.displayName }

    // Flick through every image with no pause, the way a person does when
    // comparing a look across a set.
    let started = Date()
    for index in vm.collection.items.indices {
        vm.selectCollectionImage(at: index)
    }
    let wanted = names[names.count - 1]
    let landed = await waitFor("settling on the last image", { vm.sourceName == wanted })
    let elapsed = Date().timeIntervalSince(started)

    // The right one has to be open, and the selection has to agree with it.
    let agreesOK = vm.sourceName == wanted && vm.collection.selectedIndex == names.count - 1
    print(String(format: "switch 8 images with no pause -> landed on %@ after %.2fs -> %@",
                 vm.sourceName, elapsed, landed && agreesOK ? "PASS" : "FAIL"))

    // Then the same again, to catch state that only breaks on a second pass.
    for index in vm.collection.items.indices.reversed() {
        vm.selectCollectionImage(at: index)
    }
    let backOK = await waitFor("settling on the first image", { vm.sourceName == names[0] })
    let backAgreesOK = vm.collection.selectedIndex == 0 && vm.sourceName == names[0]
    print("switch back the other way -> \(vm.sourceName) -> \(backOK && backAgreesOK ? "PASS" : "FAIL")")

    // A render has to arrive, and it has to be of the image that ended up
    // open. "The switch failed" would look identical if the state moved on but
    // a stale render stayed on screen, so compare pixels rather than trust that
    // a picture exists.
    let renderedOK = await waitFor("a preview for the open image", { vm.previewNSImage != nil })

    // Every fixture is a different colour ramp, so the middle pixel identifies
    // which one is being shown.
    func middlePixel(_ image: NSImage?) -> String? {
        guard let image, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let colour = bitmap.colorAt(x: bitmap.pixelsWide / 3, y: bitmap.pixelsHigh / 3)
        else { return nil }
        return String(format: "%02X%02X%02X",
                      Int(colour.redComponent * 255),
                      Int(colour.greenComponent * 255),
                      Int(colour.blueComponent * 255))
    }
    let onScreen = middlePixel(vm.previewNSImage)
    // Render the same image again from scratch and compare.
    vm.selectCollectionImage(at: 0)
    _ = await waitFor("first image", { vm.sourceName == names[0] })
    let firstPixel = middlePixel(vm.previewNSImage)
    vm.selectCollectionImage(at: names.count - 1)
    _ = await waitFor("last image again", { vm.sourceName == names[names.count - 1] })
    try? await Task.sleep(for: .milliseconds(400))
    let lastPixel = middlePixel(vm.previewNSImage)
    // Different fixtures must look different, and what was on screen at the end
    // of the reverse pass — which finished on the first image — must be the
    // first image, not a leftover of whatever was open before it.
    let freshOK = onScreen != nil && firstPixel != nil && lastPixel != nil
        && firstPixel != lastPixel && onScreen == firstPixel
    print("switch shows the image that is open -> first \(firstPixel ?? "?"), last \(lastPixel ?? "?"), after the reverse pass \(onScreen ?? "?") -> \(freshOK ? "PASS" : "FAIL")")
    print("switch leaves a rendered preview -> \(renderedOK ? "PASS" : "FAIL")")

    switchOK = ready && landed && agreesOK && backOK && backAgreesOK && renderedOK && freshOK

    // The reported case has a RAW in the set. RAW decoding is expensive and,
    // unlike a PNG, long enough that cancelled work piling up is visible as
    // "the switch failed". Measure a single decode, then a flick through a set
    // containing several, and see whether the cancelled ones were skipped.
    let rawSource = "/Users/world4jason/Library/Application Support/LUTStudio/Projects/134B3126-AAD9-4E7E-9521-19658D2B9464/Images/Panasonic - DC-S9 - 3_2.RW2"
    if FileManager.default.fileExists(atPath: rawSource) {
        let rawFolder = root.appendingPathComponent("Raws")
        try? FileManager.default.createDirectory(at: rawFolder, withIntermediateDirectories: true)
        for index in 0..<5 {
            try? FileManager.default.copyItem(
                at: URL(fileURLWithPath: rawSource),
                to: rawFolder.appendingPathComponent("raw\(index).RW2"))
        }
        let rawVM = AppViewModel(
            projects: ProjectStore(root: root.appendingPathComponent("RawProjects")),
            tags: LUTTagStore(fileURL: root.appendingPathComponent("rawtags.json"))
        )
        rawVM.collection.loadFromFolder(rawFolder)
        await rawVM.collection.scanCompletion()
        let rawNames = rawVM.collection.items.map { $0.url?.lastPathComponent ?? $0.displayName }

        // One image, from cold: the cost of a single switch.
        var single = Date()
        rawVM.selectCollectionImage(at: 0)
        _ = await waitFor("one RAW", { rawVM.sourceName == rawNames[0] }, limit: 1500)
        let one = Date().timeIntervalSince(single)

        // Now flick through all of them with no pause. If cancelled decodes are
        // skipped this costs about one decode; if they all run it costs five.
        single = Date()
        for index in rawVM.collection.items.indices {
            rawVM.selectCollectionImage(at: index)
        }
        let settled = await waitFor("flicking through RAWs",
                                    { rawVM.sourceName == rawNames[rawNames.count - 1] }, limit: 1500)
        let many = Date().timeIntervalSince(single)
        let ratio = one > 0 ? many / one : 0
        // Skipping superseded work should land near one decode, not five.
        let skipOK = settled && ratio < 2.0
        print(String(format: "switch %d RAWs: one takes %.2fs, all %d take %.2fs (%.1fx) -> %@",
                     rawNames.count, one, rawNames.count, many, ratio,
                     skipOK ? "PASS" : "FAIL — cancelled decodes are not being skipped"))
        switchOK = switchOK && skipOK
    } else {
        print("switch RAW pile-up -> SKIP (no RAW on this machine)")
    }
}
print("switching -> \(switchOK ? "PASS" : "FAIL")")


// --- undoing the render -----------------------------------------------------
// The display-to-V-Log conversion, against golden vectors computed from
// lutcraft's own forward transform. This is the path that made ordinary photos
// look horrible, so the bar is tight: the whole point of a closed-form inverse
// is that it does not need a loose tolerance.
var inverseOK = true
if let table = try? String(contentsOfFile: "Fixtures/inverse-vectors.tsv", encoding: .utf8) {
    // Rec.709 -> V-Gamut at full precision, straight from the Python.
    let matrix: [Float] = [
        0.58519614652135366, 0.32264162246936384, 0.092162231009282308,
        0.078588567446848251, 0.81962711468982441, 0.10178431786332748,
        0.022794237910300354, 0.11421702369120433, 0.8629887383984951,
    ]
    func toVLog(_ srgb: SIMD3<Float>) -> SIMD3<Float> {
        let linear = SIMD3<Float>(OKLab.srgbToLinear(srgb.x),
                                  OKLab.srgbToLinear(srgb.y),
                                  OKLab.srgbToLinear(srgb.z))
        let scene = NeutralRender.sceneLinear(linear)
        let vg = SIMD3<Float>(
            matrix[0] * scene.x + matrix[1] * scene.y + matrix[2] * scene.z,
            matrix[3] * scene.x + matrix[4] * scene.y + matrix[5] * scene.z,
            matrix[6] * scene.x + matrix[7] * scene.y + matrix[8] * scene.z)
        func encode(_ x: Float) -> Float {
            let v = max(x, 0)
            return v < 0.01 ? 5.6 * v + 0.125
                            : 0.241514 * log10(max(v + 0.00873, 1e-30)) / 1.0 + 0.598206
        }
        return simd_clamp(SIMD3<Float>(encode(vg.x), encode(vg.y), encode(vg.z)), .zero, .one)
    }

    var worst: Float = 0
    var worstAt = ""
    var checked = 0
    for line in table.split(separator: "\n") where line.hasPrefix("#") == false {
        let f = line.split(separator: "\t").compactMap { Float($0) }
        guard f.count == 6 else { continue }
        checked += 1
        let got = toVLog(SIMD3<Float>(f[0], f[1], f[2]))
        let want = SIMD3<Float>(f[3], f[4], f[5])
        let error = max(abs(got.x - want.x), max(abs(got.y - want.y), abs(got.z - want.z)))
        if error > worst {
            worst = error
            worstAt = String(format: "sRGB(%.3f %.3f %.3f)", f[0], f[1], f[2])
        }
    }
    inverseOK = checked > 100 && worst < 0.001
    print(String(format: "inverse %d golden vectors -> worst %.6f at %@ -> %@",
                 checked, worst, worstAt, inverseOK ? "PASS" : "FAIL"))

    // Round trip: undoing the render and redoing it has to come back.
    var roundTrip: Float = 0
    for step in 0...64 {
        let v = Float(step) / 64 * NeutralRender.displayCeiling
        let scene = NeutralRender.sceneLinear(SIMD3<Float>(repeating: v))
        roundTrip = max(roundTrip, abs(NeutralRender.curveLinear(scene.x) - v))
    }
    let roundTripOK = roundTrip < 1e-5
    print(String(format: "inverse neutral round trip -> worst %.2e -> %@", roundTrip, roundTripOK ? "PASS" : "FAIL"))

    // The cases that produce NaN if unhandled. A NaN reaches the cube as an
    // index and takes the pixel with it.
    let awkward: [SIMD3<Float>] = [
        .zero,
        SIMD3(repeating: 1),                                  // past the ceiling
        SIMD3(repeating: NeutralRender.displayCeiling),        // exactly at it
        SIMD3(1, 1, 0),                                        // a tie at the top
        SIMD3(.nan, 0.5, 0.5),
        SIMD3(.infinity, 0.5, 0.5),
        SIMD3(-0.5, 0.5, 2.0),                                 // over- and under-range
    ]
    var finiteOK = true
    for input in awkward {
        let scene = NeutralRender.sceneLinear(input)
        let ok = scene.x.isFinite && scene.y.isFinite && scene.z.isFinite
            && scene.min() >= 0 && scene.max() <= NeutralRender.sceneCeiling + 1e-3
        if ok == false { finiteOK = false; print("inverse awkward input \(input) -> \(scene)") }
    }
    // Ties must come out equal, not merely close: two channels that were the
    // same colour going in cannot come out a different colour.
    let tie = NeutralRender.sceneLinear(SIMD3(0.6, 0.6, 0.2))
    finiteOK = finiteOK && tie.x == tie.y
    print("inverse handles black, ceiling, ties, NaN and overrange -> \(finiteOK ? "PASS" : "FAIL")")

    inverseOK = inverseOK && roundTripOK && finiteOK
    print("inverse -> \(inverseOK ? "PASS" : "FAIL")")
} else {
    print("inverse -> SKIP (no golden vectors)")
}


// --- comparison layouts -----------------------------------------------------
// The grid renders one cell per slot and reads them back by row-major index, so
// a layout whose rows × columns disagreed with its cell count would silently
// drop or duplicate a picture.
var layoutOK = true
for (layout, expected) in [
    (ComparisonLayout.single, 1), (.split, 2), (.compare, 2), (.wipe, 1), (.diff, 1),
    (.grid1x2, 2), (.grid2x2, 4), (.grid3x2, 6), (.grid3x3, 9)
] as [(ComparisonLayout, Int)] {
    let ok = layout.cellCount == expected && layout.rows * layout.columns == expected
    layoutOK = layoutOK && ok
    print("layout \(layout.label.padding(toLength: 8, withPad: " ", startingAt: 0)) \(layout.columns)x\(layout.rows) = \(layout.cellCount) cells  \(ok ? "ok" : "WRONG, wanted \(expected)")")
}
// Only the grids are contact sheets; the A/B pair decide their own two sides.
let gridSet = ComparisonLayout.allCases.filter(\.isGrid)
let familyOK = gridSet == [.grid1x2, .grid2x2, .grid3x2, .grid3x3]
layoutOK = layoutOK && familyOK
print("layout grid family -> \(familyOK ? "PASS" : "FAIL")")
// Only the layouts that judge against a *chosen* base keep one in cell 0.
let baseSet = ComparisonLayout.allCases.filter(\.hasChosenBase)
let baseOK = baseSet == [.compare, .wipe, .diff]
layoutOK = layoutOK && baseOK
print("layout chosen-base family -> \(baseOK ? "PASS" : "FAIL")")
print("layouts -> \(layoutOK ? "PASS" : "FAIL")")


// --- the grid actually fills and renders ------------------------------------
// The layout maths above says how many cells there should be; this says the
// view model puts a different LUT in each of them and gets a picture back for
// every one. Without it a grid could pass every check and still show nine
// copies of the same frame, or nine spinners.
var gridOK = true
let lutFolder = "/Users/world4jason/code_ground/claude lut/out/lumix-s9-vlog/luts/fuji"
if FileManager.default.fileExists(atPath: lutFolder), writeJPEG(description: nil, to: scratch.appendingPathComponent("lutcheck-grid.png"), colourful: true) {
    let imageURL = scratch.appendingPathComponent("lutcheck-grid.png")
    defer { try? FileManager.default.removeItem(at: imageURL) }

    // Scratch stores: a check must not read the user's projects, and must
    // certainly not write to them.
    let vmProjects = ProjectStore(root: scratch.appendingPathComponent("lutcheck-vm-projects-\(UUID().uuidString)"))
    let vmTags = LUTTagStore(fileURL: scratch.appendingPathComponent("lutcheck-vm-tags-\(UUID().uuidString).json"))
    defer {
        try? FileManager.default.removeItem(at: scratch.appendingPathComponent("lutcheck-vm-projects"))
    }
    let vm = AppViewModel(projects: vmProjects, tags: vmTags)
    vm.library.scan(URL(fileURLWithPath: lutFolder))
    vm.openImage(url: imageURL)

    // Both the scan and the open are asynchronous; wait for them rather than
    // guessing at a sleep.
    // Awaits rather than pumping a run loop. Blocking the thread inside an
    // async main starves the very main-actor work being waited for — the
    // scan's continuation never runs, and every wait times out.
    func settle(_ what: String, _ done: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if done() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        print("grid \(what) -> FAIL (timed out)")
        return false
    }

    if await settle("library scan", { vm.library.allLUTs.count >= 9 }),
       await settle("image open", { vm.imageSource != nil }) {
        vm.setLayout(.grid3x3)
        let filled = vm.cellLUTIDs.count == 9
        let distinct = Set(vm.cellLUTIDs.compactMap { $0 }).count
        let rendered = await settle("cell renders", { vm.cellImages.allSatisfy { $0 != nil } })
        gridOK = filled && distinct == 9 && rendered
        print("grid 3x3 -> \(vm.cellLUTIDs.count) cells, \(distinct) distinct LUTs, \(vm.cellImages.compactMap { $0 }.count) rendered -> \(gridOK ? "PASS" : "FAIL")")

        // The cells must differ in *pixels*, not merely be labelled with
        // different LUTs: a grid that ignored its per-cell LUT would pass every
        // check above while showing nine copies of the same frame.
        // Several pixels, not one: a single sample can collide between two
        // genuinely different looks, and then the test reports a bug that is
        // not there.
        func signature(_ image: NSImage?) -> String? {
            guard let image,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff)
            else { return nil }
            var parts: [String] = []
            // Off the diagonal: the fixture's R and G ramp along x and y, so
            // x == y is neutral by construction and would compare grey to grey.
            for (fx, fy) in [(0.2, 0.8), (0.4, 0.1), (0.7, 0.3), (0.9, 0.6)] {
                let x = Int(Double(bitmap.pixelsWide - 1) * fx)
                let y = Int(Double(bitmap.pixelsHigh - 1) * fy)
                guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
                parts.append(String(format: "%02X%02X%02X",
                                    Int(colour.redComponent * 255),
                                    Int(colour.greenComponent * 255),
                                    Int(colour.blueComponent * 255)))
            }
            return parts.joined(separator: "-")
        }
        let swatches = vm.cellImages.compactMap(signature)
        let distinctSwatches = Set(swatches).count
        // Some cells must also still be *coloured*. This folder is alphabetical
        // and starts with four ACROS emulations, which are black-and-white by
        // design — so neutral early cells are the right answer, and a check that
        // demanded colour from all nine would fail on correct output.
        func isNeutral(_ signature: String) -> Bool {
            signature.split(separator: "-").allSatisfy { swatch in
                let s = Array(swatch)
                guard s.count == 6 else { return false }
                return s[0...1] == s[2...3] && s[2...3] == s[4...5]
            }
        }
        let coloured = swatches.filter { isNeutral($0) == false }.count
        let pixelsOK = swatches.count == 9 && distinctSwatches == 9 && coloured >= 3
        gridOK = gridOK && pixelsOK
        print("grid cells differ -> \(distinctSwatches)/\(swatches.count) distinct, \(coloured) carry colour (4 ACROS are mono by design) -> \(pixelsOK ? "PASS" : "FAIL")")

        // Shrinking is a crop, not a reshuffle: the first four survive.
        let before = Array(vm.cellLUTIDs.prefix(4))
        vm.setLayout(.grid2x2)
        let cropOK = vm.cellLUTIDs == before
        gridOK = gridOK && cropOK
        print("grid 3x3 -> 2x2 keeps the first four -> \(cropOK ? "PASS" : "FAIL")")

        // Re-picking one cell must not disturb its neighbours.
        let others = Array(vm.cellLUTIDs.dropFirst())
        vm.setCell(0, to: nil)
        let isolatedOK = vm.cellLUTIDs.first == .some(nil) && Array(vm.cellLUTIDs.dropFirst()) == others
        gridOK = gridOK && isolatedOK
        print("grid re-picking one cell leaves the rest -> \(isolatedOK ? "PASS" : "FAIL")")
    } else {
        gridOK = false
    }
} else {
    print("grid -> SKIP (no LUT folder on this machine)")
}
print("grid -> \(gridOK ? "PASS" : "FAIL")")


exit(inverseOK && switchOK && subsetOK && editorOK && projectOK && bulkOK && starOK && importOK && removeOK && diffOK && storeOK && tagsMatchOK && colourOK && gridOK && layoutOK && adapterOK && tagsOK && detectionOK && pipelineOK && metadataOK ? 0 : 1)
