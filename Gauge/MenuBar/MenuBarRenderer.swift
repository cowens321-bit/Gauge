import SwiftUI
import AppKit

/// One metric slot in the menu bar strip.
struct MenuBarItem: Identifiable {
    let id: String
    let caption: String
    let line1: String
    var line2: String? = nil
    var graph: [Double] = []
    var graphMax: Double = 100
}

@MainActor
enum MenuBarRenderer {
    static func items(snapshot s: SystemSnapshot?, history: TimeSeries<SystemPoint>, defaults d: UserDefaults = .standard) -> [MenuBarItem] {
        let pts = Array(history.visible.suffix(24))
        var out: [MenuBarItem] = []
        if d.bool(forKey: Pref.menuBarCPU) {
            out.append(.init(id: "cpu", caption: "CPU", line1: s?.cpu.map { "\(Int($0.total.rounded()))%" } ?? "—",
                             graph: pts.map { $0.cpuUser + $0.cpuSystem }))
        }
        if d.bool(forKey: Pref.menuBarMemory) {
            out.append(.init(id: "mem", caption: "MEM", line1: s?.memory.map { "\(Int(($0.usedFraction * 100).rounded()))%" } ?? "—",
                             graph: pts.map(\.memUsedPct)))
        }
        if d.bool(forKey: Pref.menuBarGPU) {
            out.append(.init(id: "gpu", caption: "GPU", line1: s?.gpuUtilization.map { "\(Int($0.rounded()))%" } ?? "n/a",
                             graph: pts.map { $0.gpu ?? 0 }))
        }
        if d.bool(forKey: Pref.menuBarNetwork) {
            let m = max(100_000, pts.map { max($0.netIn ?? 0, $0.netOut ?? 0) }.max() ?? 0)
            out.append(.init(id: "net", caption: "NET", line1: "↓" + (s?.network.map { Fmt.compactRate($0.inBps) } ?? "—"),
                             line2: "↑" + (s?.network.map { Fmt.compactRate($0.outBps) } ?? "—"),
                             graph: pts.map { ($0.netIn ?? 0) + ($0.netOut ?? 0) }, graphMax: m * 1.6))
        }
        if d.bool(forKey: Pref.menuBarDisk) {
            let m = max(1_000_000, pts.map { max($0.diskRead ?? 0, $0.diskWrite ?? 0) }.max() ?? 0)
            out.append(.init(id: "disk", caption: "DISK", line1: "R" + (s?.disk.map { Fmt.compactRate($0.inBps) } ?? "—"),
                             line2: "W" + (s?.disk.map { Fmt.compactRate($0.outBps) } ?? "—"),
                             graph: pts.map { ($0.diskRead ?? 0) + ($0.diskWrite ?? 0) }, graphMax: m * 1.6))
        }
        if d.bool(forKey: Pref.menuBarStorage) {
            out.append(.init(id: "storage", caption: "FREE", line1: s?.storage.map { Fmt.bytes($0.availableBytes, .decimal).replacingOccurrences(of: " ", with: "") } ?? "—"))
        }
        return out
    }

    // MARK: Drawing (pure AppKit / CoreGraphics – no SwiftUI layout involved)
    private static func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
        return base
    }

    /// Renders the strip into a template image so it adopts the menu bar's light/dark tint.
    static func render(snapshot: SystemSnapshot?, history: TimeSeries<SystemPoint>) -> NSImage {
        let style = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: Pref.menuBarStyle) ?? "") ?? .both
        let items = items(snapshot: snapshot, history: history)
        let height: CGFloat = 22, iconW: CGFloat = 16, gap: CGFloat = 9, graphW: CGFloat = 26
        let valueAttrs: (CGFloat) -> [NSAttributedString.Key: Any] = { [.font: font($0, .semibold), .foregroundColor: NSColor.black] }
        let capAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 7.5, weight: .semibold), .foregroundColor: NSColor.black.withAlphaComponent(0.7)]

        struct Slot { let item: MenuBarItem; let textW: CGFloat; let width: CGFloat; let showText: Bool; let showGraph: Bool }
        let slots: [Slot] = items.map { item in
            let showText = style != .graph
            let showGraph = style != .value && item.graph.count > 1
            let size: CGFloat = item.line2 == nil ? 12 : 9.5
            var tw = (item.line1 as NSString).size(withAttributes: valueAttrs(size)).width
            if let l2 = item.line2 { tw = max(tw, (l2 as NSString).size(withAttributes: valueAttrs(size)).width) }
            if item.line2 == nil { tw = max(tw, (item.caption as NSString).size(withAttributes: capAttrs).width) }
            let w = (showText ? tw.rounded(.up) : 0) + (showText && showGraph ? 5 : 0) + (showGraph ? graphW : 0)
            return Slot(item: item, textW: tw.rounded(.up), width: w, showText: showText, showGraph: showGraph)
        }
        let total = iconW + slots.reduce(0) { $0 + $1.width + gap }

        let img = NSImage(size: NSSize(width: max(total, iconW), height: height), flipped: false) { _ in
            if let sym = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold)) {
                let r = NSRect(x: 0, y: (height - sym.size.height) / 2, width: sym.size.width, height: sym.size.height)
                sym.draw(in: r)
            }
            var x = iconW + gap
            for slot in slots {
                let item = slot.item
                var cx = x
                if slot.showText {
                    if let l2 = item.line2 {
                        (item.line1 as NSString).draw(at: NSPoint(x: cx, y: 11), withAttributes: valueAttrs(9.5))
                        (l2 as NSString).draw(at: NSPoint(x: cx, y: 0.5), withAttributes: valueAttrs(9.5))
                    } else {
                        (item.caption as NSString).draw(at: NSPoint(x: cx, y: 12), withAttributes: capAttrs)
                        (item.line1 as NSString).draw(at: NSPoint(x: cx, y: 0.5), withAttributes: valueAttrs(12))
                    }
                    cx += slot.textW + 5
                }
                if slot.showGraph {
                    let gh: CGFloat = style == .graph ? 11 : 14
                    let gy: CGFloat = style == .graph ? 2 : (height - gh) / 2
                    if style == .graph { (item.caption as NSString).draw(at: NSPoint(x: cx, y: 13), withAttributes: capAttrs) }
                    let vals = item.graph
                    let step = graphW / CGFloat(vals.count - 1)
                    func y(_ v: Double) -> CGFloat { gy + 1 + (gh - 1) * CGFloat(min(max(v / item.graphMax, 0), 1)) }
                    let line = NSBezierPath()
                    for (i, v) in vals.enumerated() {
                        let p = NSPoint(x: cx + CGFloat(i) * step, y: y(v))
                        i == 0 ? line.move(to: p) : line.line(to: p)
                    }
                    let fill = line.copy() as! NSBezierPath
                    fill.line(to: NSPoint(x: cx + graphW, y: gy)); fill.line(to: NSPoint(x: cx, y: gy)); fill.close()
                    NSColor.black.withAlphaComponent(0.28).setFill(); fill.fill()
                    line.lineWidth = 1.1; line.lineJoinStyle = .round; NSColor.black.setStroke(); line.stroke()
                }
                x += slot.width + gap
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
