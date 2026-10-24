// Renders Faro's 1024×1024 app icon: a lighthouse on a night sky, a warm beam,
// and the concentric waves of the offline mesh.
// Usage: swift scripts/make_icon.swift BarrioMesh/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

let size = 1024.0
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
let night = color(0.05, 0.09, 0.17), dusk = color(0.13, 0.21, 0.36)
let beam = color(1.0, 0.71, 0.16), ember = color(0.93, 0.32, 0.22), white = color(1, 1, 1)

// Sky.
ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: [dusk, night] as CFArray, locations: [0, 1])!,
                       start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

let lamp = CGPoint(x: size * 0.5, y: size * 0.62)

// Mesh waves radiating from the lamp.
for (i, r) in [170.0, 290.0, 410.0].enumerated() {
    ctx.setStrokeColor(color(1.0, 0.71, 0.16, 0.30 - Double(i) * 0.08))
    ctx.setLineWidth(14)
    ctx.addArc(center: lamp, radius: r, startAngle: .pi * 0.08, endAngle: .pi * 0.92, clockwise: false)
    ctx.strokePath()
}

// Beams.
for direction in [-1.0, 1.0] {
    ctx.saveGState()
    let path = CGMutablePath()
    path.move(to: lamp)
    path.addLine(to: CGPoint(x: lamp.x + direction * size * 0.62, y: lamp.y + size * 0.20))
    path.addLine(to: CGPoint(x: lamp.x + direction * size * 0.62, y: lamp.y - size * 0.04))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: [color(1, 0.78, 0.3, 0.85), color(1, 0.71, 0.16, 0)] as CFArray, locations: [0, 1])!,
                           start: lamp, end: CGPoint(x: lamp.x + direction * size * 0.62, y: lamp.y), options: [])
    ctx.restoreGState()
}

// Tower: tapered body with red and white bands.
let base = size * 0.12, towerTop = size * 0.56
let tower = CGMutablePath()
tower.move(to: CGPoint(x: size * 0.40, y: base))
tower.addLine(to: CGPoint(x: size * 0.60, y: base))
tower.addLine(to: CGPoint(x: size * 0.555, y: towerTop))
tower.addLine(to: CGPoint(x: size * 0.445, y: towerTop))
tower.closeSubpath()
ctx.saveGState()
ctx.addPath(tower)
ctx.clip()
ctx.setFillColor(white)
ctx.fill(CGRect(x: 0, y: base, width: size, height: towerTop - base))
ctx.setFillColor(ember)
for band in 0..<3 {
    let y = base + Double(band) * 0.16 * size + 0.04 * size
    ctx.fill(CGRect(x: 0, y: y, width: size, height: size * 0.07))
}
ctx.restoreGState()

// Gallery and lamp room.
ctx.setFillColor(night)
ctx.fill(CGRect(x: size * 0.415, y: towerTop - 6, width: size * 0.17, height: 22))
ctx.setFillColor(beam)
ctx.fillEllipse(in: CGRect(x: lamp.x - 46, y: lamp.y - 46, width: 92, height: 92))
ctx.setFillColor(color(1, 0.95, 0.8))
ctx.fillEllipse(in: CGRect(x: lamp.x - 22, y: lamp.y - 22, width: 44, height: 44))
// Roof.
let roof = CGMutablePath()
roof.move(to: CGPoint(x: lamp.x - 62, y: lamp.y + 40))
roof.addLine(to: CGPoint(x: lamp.x + 62, y: lamp.y + 40))
roof.addLine(to: CGPoint(x: lamp.x, y: lamp.y + 112))
roof.closeSubpath()
ctx.addPath(roof)
ctx.setFillColor(ember)
ctx.fillPath()

// Ground.
ctx.setFillColor(color(0.03, 0.06, 0.12))
ctx.fillEllipse(in: CGRect(x: -size * 0.2, y: -size * 0.32, width: size * 1.4, height: size * 0.5))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
