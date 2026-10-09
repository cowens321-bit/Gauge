import SwiftUI

struct AppInspector: View {
    @Environment(MonitorModel.self) private var model
    @Environment(\.byteUnits) private var units
    @Environment(\.cpuNormalization) private var norm
    let group: GroupSnapshot

    var body: some View {
        let hist = model.groupHistory[group.id]
        let pts = hist?.stable(maxPoints: 150) ?? []
        let gap = max(model.interval * 3.5, 5)
        let blocked = ProcessProtection.reasonProtected(group: group)

        ScrollView {
            GlassEffectContainer(spacing: 2) {
                VStack(alignment: .leading, spacing: 14) {
                    header.entrance(0)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        StatTile(title: norm == .perCore ? "CPU (of one core)" : "CPU (of machine)",
                                 value: group.cpuPercent.map { Fmt.percent(Fmt.cpu($0, cores: model.coreCount, norm)) } ?? "—",
                                 tint: group.cpuPercent.map { Severity.cpu($0, cores: model.coreCount) == .normal ? .primary : Severity.cpu($0, cores: model.coreCount).color } ?? .primary)
                        StatTile(title: "Memory", value: group.memoryBytes.map { Fmt.bytes($0, units) } ?? "—",
                                 help: "Physical footprint, summed over all processes")
                        StatTile(title: "Energy (avg power)", value: group.powerMilliwatts.map(Fmt.power) ?? "—",
                                 help: "Energy billed to the app's processes per second. Not Activity Monitor's Energy Impact score.")
                        StatTile(title: "Processes", value: "\(group.processCount)")
                        StatTile(title: "Disk read", value: group.diskReadBps.map { Fmt.rate($0, units) } ?? "—")
                        StatTile(title: "Disk write", value: group.diskWriteBps.map { Fmt.rate($0, units) } ?? "—")
                        if group.netInBps != nil {
                            StatTile(title: "Network ↓", value: Fmt.rate(group.netInBps ?? 0, units))
                            StatTile(title: "Network ↑", value: Fmt.rate(group.netOutBps ?? 0, units))
                        }
                    }
                    .entrance(1)

                    chartCard("CPU", color: Palette.cpu) {
                        TimeChart(series: [.make("CPU", color: Palette.cpu, kind: .area, gap: gap,
                                                 pts.map { ($0.t, $0.cpu.map { Fmt.cpu($0, cores: model.coreCount, norm) }) })],
                                  window: model.chartWindow(pts), format: { String(format: "%.0f%%", $0) }, height: 110, showLegend: false)
                    }.entrance(2)
                    chartCard("Memory", color: Palette.memory) {
                        TimeChart(series: [.make("Memory", color: Palette.memory, kind: .area, gap: gap,
                                                 pts.map { ($0.t, $0.mem.map { $0 / 1_048_576 }) })],
                                  window: model.chartWindow(pts), format: { String(format: "%.0f MB", $0) }, height: 110, showLegend: false)
                    }.entrance(3)
                    if pts.contains(where: { $0.disk != nil }) {
                        chartCard("Disk activity", color: Palette.write) {
                            TimeChart(series: [.make("Disk", color: Palette.write, kind: .area, gap: gap, pts.map { ($0.t, $0.disk.map { $0 / 1024 }) })],
                                      window: model.chartWindow(pts), format: { String(format: "%.0f KB/s", $0) }, height: 90, showLegend: false)
                        }.entrance(4)
                    }

                    details.entrance(5)
                    processList.entrance(6)
                    actions(blocked: blocked).entrance(7)
                }
            }
            .padding(16)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func chartCard<C: View>(_ title: String, color: Color, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) { Circle().fill(color.gradient).frame(width: 8, height: 8); Text(title).font(.headline) }
            c()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: color, radius: 22, padding: 14)
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppNameIcon(group: group).frame(width: 52, height: 52)
                .padding(10).glassEffect(.regular, in: .rect(cornerRadius: 22))
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name).font(.title2.weight(.semibold)).lineLimit(2)
                Text(group.bundleID ?? (group.kind == .application ? "No bundle identifier" : "Collection of unattributed processes"))
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if group.inferredCount > 0 {
                    Label("\(group.inferredCount) of \(group.processCount) attributed by ancestry (inferred)", systemImage: "questionmark.circle")
                        .font(.caption2).foregroundStyle(.orange)
                }
                if group.unreadableCount > 0 {
                    Label("\(group.unreadableCount) protected processes not measurable", systemImage: "lock")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details").font(.headline)
            row("Executable", group.processes.first(where: { $0.pid == group.rootPID })?.path ?? "—")
            if let b = group.bundlePath { row("Bundle", b) }
            row("PIDs", group.processes.map { String($0.pid) }.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }.joined(separator: ", "))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 22, padding: 14)
    }

    private func row(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.caption.monospaced()).textSelection(.enabled).lineLimit(4)
        }
    }

    private var processList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Processes (\(group.processCount))").font(.headline)
            VStack(spacing: 0) {
                ForEach(group.processes.prefix(300)) { p in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(p.name).lineLimit(1)
                            HStack(spacing: 4) {
                                Text("PID \(p.pid)")
                                if p.reason != .bundlePath { Text("· \(label(p.reason))").foregroundStyle(p.reason.isInferred ? .orange : .secondary) }
                            }.font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(p.rates.map { Fmt.percent(Fmt.cpu($0.cpuPercent, cores: model.coreCount, norm)) } ?? "—").monospacedDigit()
                                .contentTransition(.numericText())
                            Text(p.memoryBytes.map { Fmt.bytes($0, units) } ?? "protected").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                    .padding(.vertical, 6)
                    .help(p.reason.explanation + (p.path.map { "\n\($0)" } ?? ""))
                    .contextMenu {
                        Button("Copy PID") { ProcessController.copy(String(p.pid)) }
                        Divider()
                        let blocked = ProcessProtection.reasonProtected(pid: p.pid, uid: p.uid, path: p.path, bundleID: nil) != nil
                        Button("Quit Process") { model.pending = PendingAction(kind: .killProcess(p, force: false), group: group) }.disabled(blocked)
                        Button("Force Kill Process…") { model.pending = PendingAction(kind: .killProcess(p, force: true), group: group) }.disabled(blocked)
                    }
                    if p.id != group.processes.prefix(300).last?.id { Divider().opacity(0.4) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 22, padding: 14)
    }

    private func label(_ r: AttributionReason) -> String {
        switch r { case .bundlePath: "bundle"; case .responsibleProcess: "responsible app"; case .ancestry: "inferred"; case .unattributed: "unattributed" }
    }

    @ViewBuilder private func actions(blocked: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Reveal", systemImage: "folder") { ProcessController.revealInFinder(group) }
                Button("Copy PID", systemImage: "number") { ProcessController.copy(group.rootPID.map(String.init) ?? "") }
                if let b = group.bundleID { Button("Copy ID", systemImage: "doc.on.doc") { ProcessController.copy(b) } }
            }
            .buttonStyle(.glass)
            HStack(spacing: 8) {
                Button("Quit", systemImage: "power") { model.pending = PendingAction(kind: .quit, group: group) }
                    .buttonStyle(.glassProminent)
                Button("Force Quit…", systemImage: "exclamationmark.octagon") { model.pending = PendingAction(kind: .forceQuit, group: group) }
                    .buttonStyle(.glassProminent).tint(.red)
            }
            .disabled(blocked != nil)
            Text(blocked ?? "Quit asks the app to close gracefully. Force Quit ends it immediately and can lose unsaved work.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlSize(.regular)
    }
}
