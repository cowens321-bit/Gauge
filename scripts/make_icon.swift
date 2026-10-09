import AppKit
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S), flipped: false) { r in
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = r.insetBy(dx: 100, dy: 100)
    let bg = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
    ctx.saveGState(); bg.addClip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(red: 0.10, green: 0.13, blue: 0.22, alpha: 1).cgColor, NSColor(red: 0.20, green: 0.26, blue: 0.48, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 100), end: CGPoint(x: S, y: S - 100), options: [])
    ctx.restoreGState()
    let c = CGPoint(x: S / 2, y: S / 2 - 40)
    func arc(_ from: CGFloat, _ to: CGFloat, _ color: NSColor, _ w: CGFloat) {
        let p = NSBezierPath(); p.appendArc(withCenter: c, radius: 270, startAngle: from, endAngle: to, clockwise: true)
        p.lineWidth = w; p.lineCapStyle = .round; color.setStroke(); p.stroke()
    }
    arc(210, -30, NSColor.white.withAlphaComponent(0.18), 64)
    arc(210, 20, NSColor(red: 0.30, green: 0.85, blue: 0.75, alpha: 1), 64)
    let needle = NSBezierPath(); needle.move(to: c)
    let a = CGFloat(35) * .pi / 180
    needle.line(to: CGPoint(x: c.x + 230 * cos(a), y: c.y + 230 * sin(a)))
    needle.lineWidth = 34; needle.lineCapStyle = .round; NSColor.white.setStroke(); needle.stroke()
    NSColor.white.setFill(); NSBezierPath(ovalIn: CGRect(x: c.x - 40, y: c.y - 40, width: 80, height: 80)).fill()
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
