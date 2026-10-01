// Draws Humm's app icon and writes an .iconset folder for `iconutil`.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Humm.iconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = size / 1024

    // macOS icon grid: an 824 pt rounded square centred in 1024, leaving room for the shadow.
    let tile = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let radius = 185 * scale
    let shape = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    shadow.shadowBlurRadius = 24 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.set()
    NSColor(white: 0.04, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    // Monochrome, like the pill: near-black tile, white bars.
    NSGradient(starting: NSColor(white: 0.16, alpha: 1), ending: NSColor(white: 0.03, alpha: 1))?
        .draw(in: tile, angle: -90)
    // Soft glow behind the bars.
    NSGradient(colors: [NSColor(white: 1, alpha: 0.10), NSColor(white: 1, alpha: 0)])?
        .draw(in: NSBezierPath(ovalIn: tile.insetBy(dx: 120 * scale, dy: 120 * scale)), relativeCenterPosition: .zero)
    NSGraphicsContext.restoreGraphicsState()

    NSColor(white: 1, alpha: 0.08).setStroke()
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 2 * scale, dy: 2 * scale), xRadius: radius, yRadius: radius)
    rim.lineWidth = 4 * scale
    rim.stroke()

    // Waveform: five rounded bars, the middle one brightest.
    let heights: [CGFloat] = [0.26, 0.5, 0.74, 0.5, 0.26]
    let barWidth = 70 * scale
    let gap = 46 * scale
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = tile.midX - total / 2
    for (index, fraction) in heights.enumerated() {
        let height = tile.height * 0.62 * fraction
        let bar = NSRect(x: x, y: tile.midY - height / 2, width: barWidth, height: height)
        NSColor(white: 1, alpha: index == 2 ? 1 : 0.82).setFill()
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        x += barWidth + gap
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let rep = drawIcon(size: CGFloat(points * factor))
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
print("wrote \(output.path)")
