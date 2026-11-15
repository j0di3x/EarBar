// Draws the EarBar app icon (two stylised earbuds on a graphite tile) into
// EarBar/Assets.xcassets/AppIcon.appiconset. Original artwork, no product images.
// Run: swift Tools/make-icon.swift
import AppKit

func render(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // tile
    let tile = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(white: 0.24, alpha: 1), NSColor(white: 0.07, alpha: 1)])!.draw(in: tile, angle: -90)
    NSColor(white: 1, alpha: 0.08).setStroke()
    tile.lineWidth = 4 * s; tile.stroke()

    // one earbud: a round head with a stem going down, tilted outwards
    func bud(centerX: CGFloat, tilt: CGFloat, dotSide: CGFloat) {
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        ctx.translateBy(x: centerX * s, y: 590 * s)
        ctx.rotate(by: tilt * .pi / 180)
        // stem
        let stem = NSBezierPath(roundedRect: NSRect(x: -42 * s, y: -330 * s, width: 84 * s, height: 330 * s), xRadius: 42 * s, yRadius: 42 * s)
        NSGradient(colors: [NSColor(white: 0.98, alpha: 1), NSColor(white: 0.80, alpha: 1)])!.draw(in: stem, angle: 0)
        // head
        let r: CGFloat = 118 * s
        let head = NSBezierPath(ovalIn: NSRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
        NSGradient(colors: [NSColor(white: 1, alpha: 1), NSColor(white: 0.84, alpha: 1)])!.draw(in: head, angle: -60)
        // ear tip
        let tip = NSBezierPath(ovalIn: NSRect(x: dotSide * 70 * s - 46 * s, y: 30 * s, width: 92 * s, height: 92 * s))
        NSColor(white: 0.62, alpha: 1).setFill(); tip.fill()
        // small red accent at the bottom of the stem
        let dot = NSBezierPath(ovalIn: NSRect(x: -15 * s, y: -300 * s, width: 30 * s, height: 30 * s))
        NSColor(red: 0.90, green: 0.12, blue: 0.16, alpha: 1).setFill(); dot.fill()
        ctx.restoreGState()
    }
    bud(centerX: 372, tilt: 9, dotSide: -1)
    bud(centerX: 652, tilt: -9, dotSide: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = URL(fileURLWithPath: "EarBar/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
var images: [String] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try! render(CGFloat(base * scale)).representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
        images.append("""
            { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(base)x\(base)" }
        """)
    }
}
let json = "{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try! json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(dir.path)")
