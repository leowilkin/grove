// Renders Grove's app icon into an .iconset folder: a git graph that grows like a tree.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(in ctx: CGContext, size: CGFloat) {
    let s = size / 1024
    ctx.scaleBy(x: s, y: s)

    // Squircle body on the macOS icon grid (824pt inside a 1024 canvas).
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(red: 0.10, green: 0.45, blue: 0.27, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    let background = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.42, green: 0.85, blue: 0.47, alpha: 1),
        CGColor(red: 0.16, green: 0.62, blue: 0.38, alpha: 1),
        CGColor(red: 0.05, green: 0.38, blue: 0.27, alpha: 1),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Soft top sheen.
    let sheen = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 980), endRadius: 620, options: [])

    // The tree: a tapered trunk with branches curling off it, each ending in a commit.
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: CGColor(red: 0, green: 0.2, blue: 0.1, alpha: 0.35))
    // One transparency layer so the glyph casts a single shadow, with no seams where shapes overlap.
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))

    let trunk = CGMutablePath()
    trunk.move(to: CGPoint(x: 470, y: 196))
    trunk.addCurve(to: CGPoint(x: 494, y: 700), control1: CGPoint(x: 490, y: 360), control2: CGPoint(x: 494, y: 560))
    trunk.addLine(to: CGPoint(x: 530, y: 700))
    trunk.addCurve(to: CGPoint(x: 554, y: 196), control1: CGPoint(x: 530, y: 560), control2: CGPoint(x: 534, y: 360))
    trunk.closeSubpath()
    ctx.addPath(trunk)
    ctx.fillPath()

    ctx.setLineWidth(40)
    ctx.setLineCap(.round)
    let branches = CGMutablePath()
    branches.move(to: CGPoint(x: 508, y: 360))
    branches.addCurve(to: CGPoint(x: 318, y: 548), control1: CGPoint(x: 500, y: 450), control2: CGPoint(x: 330, y: 440))
    branches.move(to: CGPoint(x: 514, y: 470))
    branches.addCurve(to: CGPoint(x: 712, y: 640), control1: CGPoint(x: 516, y: 560), control2: CGPoint(x: 708, y: 530))
    ctx.addPath(branches)
    ctx.strokePath()

    let nodes: [(CGPoint, CGFloat)] = [
        (CGPoint(x: 512, y: 740), 78),
        (CGPoint(x: 318, y: 574), 58),
        (CGPoint(x: 712, y: 668), 62),
    ]
    for (center, radius) in nodes {
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    // Ground line the tree grows from.
    ctx.setLineWidth(26)
    ctx.move(to: CGPoint(x: 400, y: 196))
    ctx.addLine(to: CGPoint(x: 624, y: 196))
    ctx.strokePath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Hairline edge so the icon holds up on light backgrounds.
    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.12))
    ctx.setLineWidth(2)
    ctx.strokePath()
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, px) in sizes {
    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    ctx.interpolationQuality = .high
    drawIcon(in: ctx, size: CGFloat(px))
    guard let image = ctx.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])
    try? data?.write(to: output.appending(path: "\(name).png"))
}
print("wrote \(output.path)")
