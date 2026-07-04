// icongen — renders the 1024×1024 App Store icon with CoreGraphics.
// Usage: swift tools/icongen/main.swift <repoRoot>
// GOAL Phase 8: player core erupting through a horde ring, high contrast at
// small sizes, OPAQUE output (alpha = App Store validation rejection).
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size = 1024
let s = CGFloat(size)

guard let ctx = CGContext(data: nil, width: size, height: size,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("context")
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let bgTop = color(0.075, 0.055, 0.17)
let bgBottom = color(0.039, 0.039, 0.071)
let cyan = color(0.22, 0.941, 1.0)
let magenta = color(1.0, 0.239, 0.682)
let orange = color(1.0, 0.478, 0.102)

// Background: vertical gradient, fully opaque.
let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                      colors: [bgTop, bgBottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: s / 2, y: s),
                       end: CGPoint(x: s / 2, y: 0), options: [])

// Subtle grid.
ctx.setStrokeColor(color(0.22, 0.941, 1.0, 0.05))
ctx.setLineWidth(3)
var offset: CGFloat = 0
while offset <= s {
    ctx.stroke(CGRect(x: offset, y: -2, width: 0.1, height: s + 4))
    ctx.stroke(CGRect(x: -2, y: offset, width: s + 4, height: 0.1))
    offset += 128
}

func polygonPath(sides: Int, radius: CGFloat, center: CGPoint, rotation: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<sides {
        let a = CGFloat(i) / CGFloat(sides) * 2 * .pi + rotation
        let pt = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

// Horde ring: magenta→orange shards circling the core, glow via layered fills.
let center = CGPoint(x: s / 2, y: s / 2)
let shardKinds: [(sides: Int, size: CGFloat)] = [(3, 74), (4, 66), (5, 70), (3, 60), (6, 68), (4, 72), (3, 64), (5, 76), (3, 58), (4, 62), (6, 66), (3, 70)]
for (i, shard) in shardKinds.enumerated() {
    let a = CGFloat(i) / CGFloat(shardKinds.count) * 2 * .pi + 0.35
    let dist: CGFloat = 350 + (i % 3 == 0 ? 36 : 0)
    let pos = CGPoint(x: center.x + cos(a) * dist, y: center.y + sin(a) * dist)
    let t = CGFloat(i) / CGFloat(shardKinds.count - 1)
    let cRGB = (r: 1.0, g: 0.239 + (0.478 - 0.239) * t, b: 0.682 + (0.102 - 0.682) * t)
    // Glow layers then core.
    for (scale, alpha) in [(CGFloat(1.9), CGFloat(0.10)), (1.45, 0.25), (1.0, 1.0)] {
        ctx.setFillColor(color(cRGB.r, cRGB.g, cRGB.b, alpha))
        ctx.addPath(polygonPath(sides: shard.sides, radius: shard.size * scale,
                                center: pos, rotation: a + CGFloat(i)))
        ctx.fillPath()
    }
}

// Player core: big cyan circle, radial glow, pointing "eruption" wedge.
for (radius, alpha) in [(CGFloat(340), CGFloat(0.10)), (270, 0.18), (210, 0.30), (160, 1.0)] {
    ctx.setFillColor(color(0.22, 0.941, 1.0, alpha))
    ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                               width: radius * 2, height: radius * 2))
}
// Inner white-hot center.
ctx.setFillColor(color(0.92, 1.0, 1.0))
ctx.fillEllipse(in: CGRect(x: center.x - 92, y: center.y - 92, width: 184, height: 184))

guard let image = ctx.makeImage() else { fatalError("image") }
let iconDir = "\(root)/App/Resources/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: iconDir, withIntermediateDirectories: true)
let outURL = URL(fileURLWithPath: "\(iconDir)/icon1024.png")
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("dest")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)

// Asset catalog manifests (single-size icon, iOS 16+).
let contents = """
{
  "images" : [
    {
      "filename" : "icon1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try! contents.write(toFile: "\(iconDir)/Contents.json", atomically: true, encoding: .utf8)
let catalogContents = """
{
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try! catalogContents.write(toFile: "\(root)/App/Resources/Assets.xcassets/Contents.json",
                           atomically: true, encoding: .utf8)

// GATE: opacity check via sips (GOAL Phase 8 acceptance).
let sips = Process()
sips.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
sips.arguments = ["-g", "hasAlpha", outURL.path]
let pipe = Pipe()
sips.standardOutput = pipe
try! sips.run()
sips.waitUntilExit()
let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
let opaque = out.contains("hasAlpha: no")
print("GATE icon1024 opaque=\(opaque) \(opaque ? "PASS" : "FAIL")")
exit(opaque ? 0 : 1)
