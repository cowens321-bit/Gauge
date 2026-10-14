import SwiftUI

/// Row of live metric cards: ring + big number + glowing sparkline, all on Liquid Glass.
struct OverviewHeader: View {
    @Environment(MonitorModel.self) private var model
    @Environment(\.byteUnits) private var units

    var body: some View {
        // Cards share the available width (min 224 pt each) and scroll horizontally when they cannot fit.
        GlassEffectContainer(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) { cards.containerRelativeFrame(.horizontal) { w, _ in max(204, (w - 4 * 14) / 5) } }
                    .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder private var cards: some View {
        let sys = model.snapshot?.system
        let recent = recentPoints()
        let gap = max(model.interval * 3.5, 5)
        let win = model.chartWindow(recent, cap: 120)
        let netMax = max(100_000, recent.compactMap { max($0.netIn ?? 0, $0.netOut ?? 0) }.max() ?? 0) * 1.25
        let diskMax = max(1_000_000, recent.compactMap { max($0.diskRead ?? 0, $0.diskWrite ?? 0) }.max() ?? 0) * 1.25

        MetricCard(title: "CPU", symbol: "cpu", tint: Palette.cpu,
                   value: sys?.cpu.map { Fmt.percent($0.total, decimals: 0) } ?? "—",
                   subtitle: sys?.cpu.map { "User \(Int($0.user.rounded()))% · System \(Int($0.system.rounded()))%" } ?? "Sampling…",
                   ring: sys?.cpu.map { $0.total / 100 },
                   help: "Whole-machine CPU utilisation across \(model.coreCount) cores; 100% means every core is fully busy.") {
            MiniChart(series: [.make("User", color: Palette.cpu, kind: .stackedArea, gap: gap, recent.map { ($0.t, $0.cpuUser) }),
                               .make("System", color: Palette.cpuSystem, kind: .stackedArea, gap: gap, recent.map { ($0.t, $0.cpuSystem) })],
                      window: win, yDomain: 0...100)
        }.entrance(0)

        let mem = sys?.memory
        MetricCard(title: "Memory", symbol: "memorychip", tint: mem.map { pressureColor($0.pressure) } ?? Palette.memory,
                   value: mem.map { Fmt.bytes($0.usedBytes, units) } ?? "—",
                   subtitle: mem.map { "of \(Fmt.bytes($0.totalBytes, units)) · \($0.pressure.label) pressure" } ?? "Sampling…",
                   ring: mem?.usedFraction,
                   help: "Used = App + Wired + Compressed, the same breakdown Activity Monitor uses.") {
            MiniChart(series: [.make("Used", color: mem.map { pressureColor($0.pressure) } ?? Palette.memory, kind: .area, gap: gap, recent.map { ($0.t, $0.memUsedPct) })],
                      window: win, yDomain: 0...100)
        }.entrance(1)

        MetricCard(title: "GPU", symbol: "square.stack.3d.up.fill", tint: Palette.gpu,
                   value: sys?.gpuUtilization.map { Fmt.percent($0, decimals: 0) } ?? "n/a",
                   subtitle: sys?.gpuUtilization == nil ? "No utilisation counter" : "Device utilisation",
                   ring: nil,
                   help: "System-wide GPU utilisation. macOS has no supported per-app GPU metric.") {
            MiniChart(series: [.make("GPU", color: Palette.gpu, kind: .area, gap: gap, recent.map { ($0.t, $0.gpu) })], window: win, yDomain: 0...100)
        }.entrance(2)

        MetricCard(title: "Network", symbol: "arrow.up.arrow.down", tint: Palette.down,
                   value: sys?.network.map { "↓ " + Fmt.rate($0.inBps, units) } ?? "—",
                   subtitle: sys?.network.map { "↑ " + Fmt.rate($0.outBps, units) } ?? "Sampling…", ring: nil,
                   help: "Throughput on physical network interfaces (Wi-Fi / Ethernet / cellular).") {
            MiniChart(series: [.make("Down", color: Palette.down, kind: .area, gap: gap, recent.map { ($0.t, $0.netIn) }),
                               .make("Up", color: Palette.up, kind: .line, gap: gap, recent.map { ($0.t, $0.netOut) })],
                      window: win, yDomain: 0...netMax)
        }.entrance(3)

        MetricCard(title: "Disk", symbol: "internaldrive", tint: Palette.read,
                   value: sys?.disk.map { "R " + Fmt.rate($0.inBps, units) } ?? "—",
                   subtitle: [sys?.disk.map { "W " + Fmt.rate($0.outBps, units) },
                              sys?.storage.map { Fmt.bytes($0.availableBytes, units) + " free" }].compactMap { $0 }.joined(separator: " · "),
                   ring: nil,
                   help: "Read/write throughput across all block devices. Ring shows how full the startup volume is.") {
            MiniChart(series: [.make("Read", color: Palette.read, kind: .area, gap: gap, recent.map { ($0.t, $0.diskRead) }),
                               .make("Write", color: Palette.write, kind: .line, gap: gap, recent.map { ($0.t, $0.diskWrite) })],
                      window: win, yDomain: 0...diskMax)
        }.entrance(4)
    }

    private func recentPoints() -> [SystemPoint] {
        let all = model.systemHistory.stable(maxPoints: 240)
        guard let last = all.last else { return [] }
        let cutoff = last.t.addingTimeInterval(-min(model.historyWindow, 120))
        return all.filter { $0.t >= cutoff }
    }
}

func pressureColor(_ p: MemoryPressure) -> Color {
    switch p { case .normal: .mint; case .warning: .yellow; case .critical: .red }
}

struct MetricCard<Chart: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    let subtitle: String
    let ring: Double?
    var help: String = ""
    @ViewBuilder var chart: Chart

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(title, systemImage: symbol)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(tint).symbolRenderingMode(.hierarchical)
                    Text(value).font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.55).contentTransition(.numericText())
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 6)
                if let ring { RingGauge(value: ring, color: tint, lineWidth: 6).frame(width: 44, height: 44) }
            }
            chart.frame(height: 46)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint, radius: 28, padding: 15)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value). \(subtitle)")
    }
}

