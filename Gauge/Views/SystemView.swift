import SwiftUI

struct SystemView: View {
    @Environment(MonitorModel.self) private var model
    @Environment(\.byteUnits) private var units

    var body: some View {
        let pts = model.systemHistory.stable(maxPoints: 240)
        let gap = max(model.interval * 3.5, 5)
        let win = model.chartWindow(pts)
        let sys = model.snapshot?.system

        ScrollView {
            GlassEffectContainer(spacing: 2) {
                VStack(alignment: .leading, spacing: 16) {
                    hero(sys).entrance(0)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 400), spacing: 16)], spacing: 16) {
                        chartCard("CPU", subtitle: "Whole machine · user vs system", tint: Palette.cpu, index: 1) {
                            TimeChart(series: [.make("User", color: Palette.cpu, kind: .stackedArea, gap: gap, pts.map { ($0.t, $0.cpuUser) }),
                                               .make("System", color: Palette.cpuSystem, kind: .stackedArea, gap: gap, pts.map { ($0.t, $0.cpuSystem) })],
                                      window: win, yDomain: 0...100, format: { String(format: "%.0f%%", $0) }, height: 170)
                        }
                        chartCard("Memory", subtitle: memorySubtitle(sys?.memory), tint: Palette.memory, index: 2) {
                            TimeChart(series: [.make("App", color: .blue, kind: .stackedArea, gap: gap, pts.map { ($0.t, $0.memApp) }),
                                               .make("Wired", color: .orange, kind: .stackedArea, gap: gap, pts.map { ($0.t, $0.memWired) }),
                                               .make("Compressed", color: .purple, kind: .stackedArea, gap: gap, pts.map { ($0.t, $0.memCompressed) })],
                                      window: win, yDomain: 0...(Double(model.totalMemory) / 1_073_741_824), format: { String(format: "%.1f GB", $0) }, height: 170)
                        }
                        chartCard("Network", subtitle: "Physical interfaces", tint: Palette.down, index: 3) {
                            TimeChart(series: [.make("Download", color: Palette.down, kind: .area, gap: gap, pts.map { ($0.t, $0.netIn.map { $0 / 1024 }) }),
                                               .make("Upload", color: Palette.up, kind: .area, gap: gap, pts.map { ($0.t, $0.netOut.map { $0 / 1024 }) })],
                                      window: win, format: rate, height: 170)
                        }
                        chartCard("Disk", subtitle: "All block devices", tint: Palette.read, index: 4) {
                            TimeChart(series: [.make("Read", color: Palette.read, kind: .area, gap: gap, pts.map { ($0.t, $0.diskRead.map { $0 / 1024 }) }),
                                               .make("Write", color: Palette.write, kind: .area, gap: gap, pts.map { ($0.t, $0.diskWrite.map { $0 / 1024 }) })],
                                      window: win, format: rate, height: 170)
                        }
                        if sys?.gpuUtilization != nil {
                            chartCard("GPU", subtitle: "Device utilisation", tint: Palette.gpu, index: 5) {
                                TimeChart(series: [.make("GPU", color: Palette.gpu, kind: .area, gap: gap, pts.map { ($0.t, $0.gpu) })],
                                          window: win, yDomain: 0...100, format: { String(format: "%.0f%%", $0) }, height: 170)
                            }
                        }
                        sensors(sys).entrance(6)
                    }
                }
            }
            .padding(20)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("System")
    }

    // MARK: Hero
    private func hero(_ sys: SystemSnapshot?) -> some View {
        HStack(spacing: 28) {
            bigRing("CPU", value: (sys?.cpu?.total ?? 0) / 100, text: sys?.cpu.map { "\(Int($0.total.rounded()))%" } ?? "—", color: Palette.cpu)
            bigRing("Memory", value: sys?.memory?.usedFraction ?? 0, text: sys?.memory.map { "\(Int(($0.usedFraction * 100).rounded()))%" } ?? "—",
                    color: sys?.memory.map { pressureColor($0.pressure) } ?? Palette.memory)
            if let g = sys?.gpuUtilization { bigRing("GPU", value: g / 100, text: "\(Int(g.rounded()))%", color: Palette.gpu) }
            if let st = sys?.storage { bigRing("Storage", value: st.usedFraction, text: "\(Int((st.usedFraction * 100).rounded()))%", color: Palette.storage) }
            Spacer(minLength: 0)
            if let m = sys?.memory { MemoryComposition(memory: m).frame(maxWidth: 380) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 32, padding: 22)
    }

    private func bigRing(_ title: String, value: Double, text: String, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RingGauge(value: value, color: color, lineWidth: 11).frame(width: 96, height: 96)
                Text(text).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
            }
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private func chartCard<C: View>(_ title: String, subtitle: String, tint: Color, index: Int, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            c()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint, radius: 28, padding: 18)
        .entrance(index)
    }

    private func sensors(_ sys: SystemSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sensors").font(.headline)
            LabeledContent("Thermal state", value: thermal(sys?.thermalState))
            LabeledContent("Temperature") { UnavailableLabel(text: "Not exposed by public APIs") }
            Text("macOS offers no supported API for CPU temperature or fan speed, so Gauge reports the system thermal state instead of inventing a number.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 28, padding: 18)
    }

    private var rate: (Double) -> String { { $0 > 1024 ? String(format: "%.1f MB/s", $0 / 1024) : String(format: "%.0f KB/s", $0) } }

    private func memorySubtitle(_ m: MemoryUsage?) -> String {
        guard let m else { return "" }
        return "\(Fmt.bytes(m.usedBytes, units)) of \(Fmt.bytes(m.totalBytes, units))"
    }
    private func thermal(_ s: ProcessInfo.ThermalState?) -> String {
        switch s { case .nominal: "Nominal"; case .fair: "Fair"; case .serious: "Serious"; case .critical: "Critical"; default: "—" }
    }
}

/// Segmented bar showing how physical memory is divided, matching Activity Monitor's categories.
struct MemoryComposition: View {
    let memory: MemoryUsage
    @Environment(\.byteUnits) private var units

    var body: some View {
        let total = Double(max(memory.totalBytes, 1))
        let segs: [(String, UInt64, Color)] = [("App", memory.appBytes, .blue), ("Wired", memory.wiredBytes, .orange),
                                               ("Compressed", memory.compressedBytes, .purple), ("Cached", memory.cachedBytes, .gray.opacity(0.55))]
        VStack(alignment: .leading, spacing: 10) {
            Text("Memory composition").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(segs, id: \.0) { s in
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(s.2.gradient)
                            .frame(width: max(2, geo.size.width * CGFloat(Double(s.1) / total)))
                    }
                    Spacer(minLength: 0)
                }
                .animation(.smooth(duration: 0.8), value: memory.usedBytes)
            }
            .frame(height: 16)
            .clipShape(.capsule)
            .background(Capsule().fill(.quaternary.opacity(0.5)))
            HStack(spacing: 12) {
                ForEach(segs, id: \.0) { s in
                    VStack(alignment: .leading, spacing: 0) {
                        LegendDot(color: s.2, name: s.0)
                        Text(Fmt.bytes(s.1, units)).font(.caption.monospacedDigit().weight(.medium)).contentTransition(.numericText())
                    }
                }
            }
        }
    }
}
