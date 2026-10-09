import SwiftUI

/// Colour roles used across charts, rings and tiles.
enum Palette {
    static let cpu = Color.blue
    static let cpuSystem = Color.pink
    static let memory = Color.mint
    static let gpu = Color.purple
    static let down = Color.cyan
    static let up = Color.orange
    static let read = Color.green
    static let write = Color.pink
    static let storage = Color.indigo
}

extension View {
    /// Liquid Glass surface used for cards, tiles and panels (plain material in Reduced mode).
    func glassCard(tint: Color? = nil, radius: CGFloat = 24, padding: CGFloat = 16, interactive: Bool = false) -> some View {
        modifier(GlassCardModifier(tint: tint, radius: radius, padding: padding, interactive: interactive))
    }

    /// Staggered entrance: fades, scales and un-blurs into place.
    func entrance(_ index: Int) -> some View { modifier(Entrance(index: index)) }
}

private struct Entrance: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.94)
            .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.22).delay(Double(index) * 0.06)) { shown = true } }
    }
}

/// Circular progress ring with a gradient stroke and a smoothly animated sweep.
struct RingGauge: View {
    let value: Double          // 0...1
    let color: Color
    var lineWidth: CGFloat = 7
    var body: some View {
        let v = min(max(value, 0), 1)
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.004, v))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.smooth(duration: 0.3), value: v)
    }
}

/// Soft mesh of colour behind the glass. It warms toward orange/red as the machine gets busier,
/// so system load is felt peripherally before a number is read.
struct AmbientBackground: View {
    var heat: Double   // 0...1
    @Environment(\.colorScheme) private var scheme
    @Environment(\.reducedEffects) private var reduced

    var body: some View {
        if reduced { Color(nsColor: .windowBackgroundColor).ignoresSafeArea() } else { mesh }
    }

    @ViewBuilder private var mesh: some View {
        let h = (min(max(heat, 0), 1) * 5).rounded() / 5   // 6 discrete levels -> animates rarely
        let calmA = Color.blue, calmB = Color.teal, calmC = Color.indigo
        let hot = Color.orange
        let a = calmA.mix(with: hot, by: h * 0.9), b = calmB.mix(with: .red, by: h * 0.7), c = calmC.mix(with: hot, by: h * 0.6)
        let o = scheme == .dark ? 0.42 : 0.26
        MeshGradient(width: 3, height: 3,
                     points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.55, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                     colors: [a.opacity(o), c.opacity(o * 0.7), b.opacity(o),
                              c.opacity(o * 0.5), a.opacity(o * 0.35), c.opacity(o * 0.5),
                              b.opacity(o * 0.8), a.opacity(o * 0.6), c.opacity(o)])
            .background(Color(nsColor: .windowBackgroundColor))
            .animation(.easeInOut(duration: 1.6), value: h)
            .ignoresSafeArea()
    }
}

struct LegendDot: View {
    let color: Color; let name: String
    var body: some View {
        HStack(spacing: 5) { Circle().fill(color.gradient).frame(width: 8, height: 8); Text(name).font(.caption).foregroundStyle(.secondary) }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = .primary
    var help: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7).contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18, padding: 12)
        .help(help ?? "")
    }
}

struct UnavailableLabel: View {
    var text = "Unavailable"
    var body: some View { Text(text).foregroundStyle(.tertiary) }
}

/// Reports whether the hosting window is actually visible (not minimised / occluded), so the
/// model can stop process sampling while nobody can see the results.
struct WindowVisibilityReader: NSViewRepresentable {
    var onChange: (Bool) -> Void
    var onFirstAppear: ((NSWindow) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var tokens: [NSObjectProtocol] = []
        var didFirst = false
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { attach(v, context.coordinator) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.tokens.isEmpty { DispatchQueue.main.async { attach(nsView, context.coordinator) } }
    }

    private func attach(_ view: NSView, _ c: Coordinator) {
        guard let w = view.window, c.tokens.isEmpty else { return }
        let nc = NotificationCenter.default
        let report: (Notification) -> Void = { _ in
            onChange(w.occlusionState.contains(.visible) && !w.isMiniaturized && w.isVisible)
        }
        for n in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                  NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
            c.tokens.append(nc.addObserver(forName: n, object: w, queue: .main, using: report))
        }
        if !c.didFirst { c.didFirst = true; onFirstAppear?(w) }
        onChange(w.occlusionState.contains(.visible) && !w.isMiniaturized)
    }
}

struct GlassCardModifier: ViewModifier {
    let tint: Color?
    let radius: CGFloat
    let padding: CGFloat
    let interactive: Bool
    @Environment(\.reducedEffects) private var reduced

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduced {
            content.padding(padding).background {
                shape.fill(.regularMaterial)
                if let tint { shape.fill(tint.opacity(0.10)) }
                shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
            }
        } else {
            let glass: Glass = tint.map { Glass.regular.tint($0.opacity(0.16)) } ?? Glass.regular
            // The glass plate is its own layer behind the content.
            content.padding(padding).background {
                Color.clear.glassEffect(interactive ? glass.interactive() : glass, in: .rect(cornerRadius: radius))
            }
        }
    }
}
