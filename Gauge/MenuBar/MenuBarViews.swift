import SwiftUI
import AppKit

/// The menu bar item itself: an icon plus whichever live metrics the user ticked, drawn as one
/// template image so it matches the system menu bar in light, dark and tinted modes.
struct MenuBarLabel: View {
    @Environment(MonitorModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Group {
            if model.menuBarImage.size.width > 1 {
                Image(nsImage: model.menuBarImage)
            } else {
                Image(systemName: "gauge.with.needle")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gaugeOpenMainWindow)) { _ in
            openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct MenuBarPopover: View {
    @Environment(MonitorModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.byteUnits) private var units
    @Environment(\.cpuNormalization) private var norm
    @AppStorage(Pref.menuBarCPU) private var mbCPU = true
    @AppStorage(Pref.menuBarMemory) private var mbMem = true
    @AppStorage(Pref.menuBarGPU) private var mbGPU = false
    @AppStorage(Pref.menuBarNetwork) private var mbNet = false
    @AppStorage(Pref.menuBarDisk) private var mbDisk = false
    @AppStorage(Pref.menuBarStorage) private var mbStorage = false
    @State private var mode = 0
    @State private var showItems = false

    var body: some View {
        let s = model.snapshot?.system
        let groups = (model.snapshot?.groups ?? []).filter { $0.kind == .application }
        let top = Array((mode == 0 ? groups.sorted { $0.cpuSort > $1.cpuSort } : groups.sorted { $0.memorySort > $1.memorySort }).prefix(6))
        let recent = Array(model.systemHistory.stable(maxPoints: 60))
        let gap = max(model.interval * 3.5, 5)

        GlassEffectContainer(spacing: 2) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    ring("CPU", (s?.cpu?.total ?? 0) / 100, s?.cpu.map { "\(Int($0.total.rounded()))%" } ?? "—", Palette.cpu)
                    ring("MEM", s?.memory?.usedFraction ?? 0, s?.memory.map { "\(Int(($0.usedFraction * 100).rounded()))%" } ?? "—",
                         s?.memory.map { pressureColor($0.pressure) } ?? Palette.memory)
                    VStack(alignment: .leading, spacing: 3) {
                        stat("arrow.down", s?.network.map { Fmt.rate($0.inBps, units) } ?? "—", Palette.down)
                        stat("arrow.up", s?.network.map { Fmt.rate($0.outBps, units) } ?? "—", Palette.up)
                        if let st = s?.storage { stat("internaldrive", Fmt.bytes(st.availableBytes, units) + " free", Palette.storage) }
                    }
                    Spacer(minLength: 0)
                }
                MiniChart(series: [.make("User", color: Palette.cpu, kind: .stackedArea, gap: gap, recent.map { ($0.t, $0.cpuUser) }),
                                   .make("System", color: Palette.cpuSystem, kind: .stackedArea, gap: gap, recent.map { ($0.t, $0.cpuSystem) })],
                          window: model.chartWindow(recent, cap: 120), yDomain: 0...100).frame(height: 48)
            }
            .glassCard(tint: Palette.cpu, radius: 26, padding: 14)

            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $mode.animation(.smooth)) { Text("Top CPU").tag(0); Text("Top Memory").tag(1) }
                    .pickerStyle(.segmented).labelsHidden()
                VStack(spacing: 7) {
                    ForEach(top) { g in
                        HStack(spacing: 9) {
                            AppNameIcon(group: g).frame(width: 22, height: 22)
                            Text(g.name).lineLimit(1)
                            Spacer()
                            Text(mode == 0 ? (g.cpuPercent.map { Fmt.percent(Fmt.cpu($0, cores: model.coreCount, norm), decimals: 0) } ?? "—")
                                           : (g.memoryBytes.map { Fmt.bytes($0, units) } ?? "—"))
                                .monospacedDigit().foregroundStyle(.secondary).contentTransition(.numericText())
                        }.font(.callout)
                    }
                    if top.isEmpty { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
                }
            }
            .glassCard(radius: 26, padding: 14)

            DisclosureGroup(isExpanded: $showItems) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
                    chip("CPU", "cpu", $mbCPU); chip("Memory", "memorychip", $mbMem); chip("GPU", "square.stack.3d.up.fill", $mbGPU)
                    chip("Network", "arrow.up.arrow.down", $mbNet); chip("Disk I/O", "internaldrive", $mbDisk); chip("Storage", "externaldrive", $mbStorage)
                }
                .padding(.top, 8)
            } label: {
                Label("Menu bar items", systemImage: "menubar.rectangle").font(.callout.weight(.medium))
            }
            .glassCard(radius: 22, padding: 12)

            HStack {
                Button("Open Gauge", systemImage: "macwindow") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                    .buttonStyle(.glassProminent)
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.glass)
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.glass)
            }
        }
        .padding(12)
        .frame(width: 360)
        .onAppear { model.popoverVisible = true }
        .onDisappear { model.popoverVisible = false }
        .onChange(of: mbCPU) { model.refreshMenuBarImage() }
        .onChange(of: mbMem) { model.refreshMenuBarImage() }
        .onChange(of: mbGPU) { model.refreshMenuBarImage() }
        .onChange(of: mbNet) { model.refreshMenuBarImage() }
        .onChange(of: mbDisk) { model.refreshMenuBarImage() }
        .onChange(of: mbStorage) { model.refreshMenuBarImage() }
    }

    private func ring(_ t: String, _ v: Double, _ text: String, _ c: Color) -> some View {
        ZStack {
            RingGauge(value: v, color: c, lineWidth: 6).frame(width: 62, height: 62)
            VStack(spacing: -1) {
                Text(text).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                Text(t).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
        }
    }
    private func stat(_ symbol: String, _ text: String, _ c: Color) -> some View {
        HStack(spacing: 6) { Image(systemName: symbol).foregroundStyle(c).frame(width: 14); Text(text).monospacedDigit().contentTransition(.numericText()) }.font(.caption.weight(.medium))
    }
    private func chip(_ title: String, _ symbol: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) { Label(title, systemImage: symbol).font(.caption) }.toggleStyle(.button).buttonStyle(.glass).controlSize(.small)
    }
}
