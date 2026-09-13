// Renders the LUTzy app icon: the RGB colour cube a `.cube` LUT indexes, viewed from its green
// corner with black at the front, on the app's near-black canvas.
//
//   swift scripts/render-icon.swift <output-dir>
//
// Writes icon_<size>x<size>[@2x].png for every macOS slot, ready for an appiconset or `iconutil`.
// Pure CoreGraphics so the face colours are exact bilinear interpolation, not an SVG gradient
// approximation, and so the build needs nothing beyond the Apple toolchain.

import AppKit
import CoreGraphics
import Foundation

struct V { var x: Double; var y: Double }

/// A parallelogram face with a colour at each corner: origin, plus the two edge vectors u and v.
struct Face {
    var o: V, u: V, v: V
    var c00: (Double, Double, Double), c10: (Double, Double, Double)
    var c01: (Double, Double, Double), c11: (Double, Double, Double)
    var shade: Double

    /// Inverse-map p into (a, b) in face space; nil when outside.
    func uv(_ p: V) -> (Double, Double)? {
        let det = u.x * v.y - u.y * v.x
        let dx = p.x - o.x, dy = p.y - o.y
        let a = (dx * v.y - dy * v.x) / det
        let b = (u.x * dy - u.y * dx) / det
        guard a >= 0, a <= 1, b >= 0, b <= 1 else { return nil }
        return (a, b)
    }

    func color(_ a: Double, _ b: Double) -> (Double, Double, Double) {
        func mix(_ p: (Double, Double, Double), _ q: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
            (p.0 + (q.0 - p.0) * t, p.1 + (q.1 - p.1) * t, p.2 + (q.2 - p.2) * t)
        }
        let top = mix(c00, c10, a)
        let bottom = mix(c01, c11, a)
        let c = mix(top, bottom, b)
        return (c.0 * shade, c.1 * shade, c.2 * shade)
    }
}

let size = 1024
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// Cube geometry in a 1024 canvas (y down). Edge 300, isometric.
let A = V(x: 512, y: 236)   // white corner, top back
let L = V(x: 252, y: 386)   // yellow
let R = V(x: 772, y: 386)   // cyan
let M = V(x: 512, y: 536)   // green, the front top corner
let BL = V(x: 252, y: 686)  // red
let BR = V(x: 772, y: 686)  // blue
let B = V(x: 512, y: 836)   // black, front bottom

func vec(_ p: V, _ q: V) -> V { V(x: q.x - p.x, y: q.y - p.y) }

// Corner colours are slightly softened from pure primaries so the faces read as a rendered object
// rather than a test pattern; the lattice is still unmistakably the RGB cube.
let white = (0.98, 0.98, 0.97), black = (0.02, 0.02, 0.025)
let red = (0.96, 0.20, 0.22), green = (0.20, 0.90, 0.40), blue = (0.20, 0.36, 0.98)
let yellow = (0.99, 0.86, 0.22), cyan = (0.22, 0.86, 0.94)

// Top face (G = 1): A white, L yellow, M green, R cyan.
let top = Face(o: A, u: vec(A, R), v: vec(A, L), c00: white, c10: cyan, c01: yellow, c11: green, shade: 1.0)
// Left face (B = 0): L yellow, M green, BL red, B black.
let left = Face(o: L, u: vec(L, M), v: vec(L, BL), c00: yellow, c10: green, c01: red, c11: black, shade: 0.86)
// Right face (R = 0): M green, R cyan, B black, BR blue.
let right = Face(o: M, u: vec(M, R), v: vec(M, B), c00: green, c10: cyan, c01: black, c11: blue, shade: 0.72)

// Squircle mask: Apple's continuous-corner rounded square, 824 pt on a 1024 canvas.
let inset = 100.0, side = 824.0, exponent = 5.0
func insideSquircle(_ p: V) -> Double {
    let cx = 512.0, cy = 512.0, h = side / 2
    let nx = abs(p.x - cx) / h, ny = abs(p.y - cy) / h
    let r = pow(pow(nx, exponent) + pow(ny, exponent), 1 / exponent)
    // Soft edge, ~1.5 px of anti-aliasing.
    return max(0, min(1, (1 - r) * h / 1.5 + 0.5))
}

/// Brightness added near the segment p→q, fading over ~4 px, strongest at the black corner.
func rimLight(_ p: V, _ a: V, _ b: V) -> Double {
    let ab = vec(a, b), ap = vec(a, p)
    let len2 = ab.x * ab.x + ab.y * ab.y
    let t = max(0, min(1, (ap.x * ab.x + ap.y * ab.y) / len2))
    let cx = a.x + ab.x * t, cy = a.y + ab.y * t
    let dist = hypot(p.x - cx, p.y - cy)
    // Strongest at B (t == 1 for BL→B, t == 0 for B→BR); the caller passes segments so B is the
    // corner nearer the cube's bottom vertex.
    let nearBlack = a.y > b.y ? (1 - t) : t
    return max(0, 1 - dist / 4.0) * (0.10 + 0.14 * nearBlack)
}

var pixels = [UInt8](repeating: 0, count: size * size * 4)
let faces = [top, left, right]
let ss = 3 // supersampling per axis

for py in 0..<size {
    for px in 0..<size {
        var acc = (0.0, 0.0, 0.0, 0.0)
        for sy in 0..<ss {
            for sx in 0..<ss {
                let p = V(x: Double(px) + (Double(sx) + 0.5) / Double(ss),
                          y: Double(py) + (Double(sy) + 0.5) / Double(ss))
                let mask = insideSquircle(p)
                guard mask > 0 else { continue }

                // Background: the app's canvas, lifted slightly behind the cube.
                let d = hypot(p.x - 512, p.y - 560) / 520
                let lift = max(0, 1 - d) * 0.06
                var c = (0.07 + lift, 0.07 + lift, 0.08 + lift * 1.1)

                // Contact shadow under the cube.
                let sdx = (p.x - 512) / 330, sdy = (p.y - 760) / 120
                let sh = exp(-(sdx * sdx + sdy * sdy) * 2.2) * 0.55
                c = (c.0 * (1 - sh), c.1 * (1 - sh), c.2 * (1 - sh))

                for f in faces {
                    if let (a, b) = f.uv(p) {
                        c = f.color(a, b)
                        break
                    }
                }

                // Rim light on the two bottom edges, so the black corner does not dissolve into
                // the ground: the cube's silhouette should survive on any desktop.
                let rim = max(rimLight(p, BL, B), rimLight(p, B, BR))
                c = (c.0 + rim, c.1 + rim, c.2 + rim * 1.1)
                acc.0 += c.0 * mask; acc.1 += c.1 * mask; acc.2 += c.2 * mask; acc.3 += mask
            }
        }
        let n = Double(ss * ss)
        let i = (py * size + px) * 4
        let alpha = acc.3 / n
        // Premultiplied.
        pixels[i] = UInt8(max(0, min(255, (acc.0 / n) * 255 + 0.5)))
        pixels[i + 1] = UInt8(max(0, min(255, (acc.1 / n) * 255 + 0.5)))
        pixels[i + 2] = UInt8(max(0, min(255, (acc.2 / n) * 255 + 0.5)))
        pixels[i + 3] = UInt8(max(0, min(255, alpha * 255 + 0.5)))
    }
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let data = Data(pixels)
let provider = CGDataProvider(data: data as CFData)!
let master = CGImage(
    width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
    space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
)!

func write(_ image: CGImage, px: Int, name: String) {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    let scaled = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: scaled)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: out.appendingPathComponent(name))
}

let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (pt, scale) in slots {
    write(master, px: pt * scale, name: "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png")
}
print("wrote \(slots.count) icon sizes to \(out.path)")
