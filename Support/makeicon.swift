// Renders AppIcon.icns: dark slate squircle with green Wi-Fi arcs and a
// small chart bar motif (signal + usage — the two halves of the app).
// Run: swift Support/makeicon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let ctx = NSGraphicsContext.current!.cgContext

// Background squircle (macOS icon grid: content inset ~10%)
let inset: CGFloat = size * 0.1
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = rect.width * 0.225
let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
NSColor(calibratedRed: 0.078, green: 0.086, blue: 0.11, alpha: 1).setFill()
bg.fill()

// Subtle vertical sheen
let gradient = NSGradient(colors: [
    NSColor(calibratedWhite: 1, alpha: 0.07),
    NSColor(calibratedWhite: 1, alpha: 0.0),
])!
gradient.draw(in: bg, angle: -90)

// Wi-Fi arcs, drawn as stroked arcs radiating from a base point
let center = CGPoint(x: size / 2, y: size * 0.34)
let green = NSColor(calibratedRed: 0.196, green: 0.843, blue: 0.294, alpha: 1)
let arcRadii: [CGFloat] = [0.13, 0.225, 0.32].map { $0 * size }
let lineW = size * 0.052

for (i, r) in arcRadii.enumerated() {
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: r, startAngle: 45, endAngle: 135, clockwise: false)
    path.lineWidth = lineW
    path.lineCapStyle = .round
    green.withAlphaComponent(1.0 - CGFloat(i) * 0.22).setStroke()
    path.stroke()
}

// Base dot
let dotR = size * 0.045
let dot = NSBezierPath(ovalIn: CGRect(x: center.x - dotR, y: center.y - dotR + size * 0.01,
                                      width: dotR * 2, height: dotR * 2))
green.setFill()
dot.fill()

image.unlockFocus()

// Write iconset at all required sizes
let iconsetURL = URL(fileURLWithPath: "Support/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try! FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(Int, Int, String)] = [
    (16, 1, "icon_16x16.png"), (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"), (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"), (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"), (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"), (512, 2, "icon_512x512@2x.png"),
]

for (pts, scale, name) in sizes {
    let px = pts * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pts, height: pts)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pts, height: pts))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: iconsetURL.appendingPathComponent(name))
}

print("iconset written")
