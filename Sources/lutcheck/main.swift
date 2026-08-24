import CoreImage
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
exit(adapterOK && tagsOK ? 0 : 1)
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
