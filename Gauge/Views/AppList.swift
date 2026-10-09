import SwiftUI

enum AppColumn: String, CaseIterable, Identifiable {
    case name, cpu, memory, energy, disk, network, processes
    var id: String { rawValue }

    var width: CGFloat? {
        switch self {
        case .name: nil
        case .cpu: 128
        case .memory: 104
        case .energy: 84
        case .disk: 96
        case .network: 96
        case .processes: 72
        }
    }
    func title(_ norm: CPUNormalization) -> String {
        switch self {
        case .name: "Application"
        case .cpu: norm == .perCore ? "CPU (of a core)" : "CPU (of machine)"
        case .memory: "Memory"
        case .energy: "Energy"
        case .disk: "Disk"
        case .network: "Network"
        case .processes: "Procs"
        }
    }
    var startsAscending: Bool { self == .name }

    func comparator(ascending: Bool) -> KeyPathComparator<GroupSnapshot> {
        let o: SortOrder = ascending ? .forward : .reverse
        switch self {
        case .name: return KeyPathComparator(\GroupSnapshot.name, comparator: .localizedStandard, order: o)
        case .cpu: return KeyPathComparator(\GroupSnapshot.cpuSort, order: o)
        case .memory: return KeyPathComparator(\GroupSnapshot.memorySort, order: o)
        case .energy: return KeyPathComparator(\GroupSnapshot.powerSort, order: o)
        case .disk: return KeyPathComparator(\GroupSnapshot.diskSort, order: o)
        case .network: return KeyPathComparator(\GroupSnapshot.netSort, order: o)
        case .processes: return KeyPathComparator(\GroupSnapshot.processCount, order: o)
        }
    }

    init(_ key: SortKey) {
        switch key { case .cpu: self = .cpu; case .memory: self = .memory; case .name: self = .name
                     case .energy: self = .energy; case .processes: self = .processes }
    }
}

struct SortSpec: Equatable {
    var column: AppColumn
    var ascending: Bool
    var comparators: [KeyPathComparator<GroupSnapshot>] { [column.comparator(ascending: ascending)] }
}

/// Lazy, natively rendered application list. (SwiftUI's `Table` wraps every cell in an AppKit hosting
/// view that is re-rendered on the CPU each tick; this keeps live updates cheap.)
struct AppList: View {
    @Environment(MonitorModel.self) private var model
    @Environment(\.byteUnits) private var units
    @Environment(\.cpuNormalization) private var norm
    let rows: [GroupSnapshot]
    @Binding var selection: String?
    @Binding var sort: SortSpec
    let showNetwork: Bool
    var onOpen: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            let cols = visibleColumns(width: geo.size.width)
            VStack(spacing: 0) {
                header(cols)
                Divider().opacity(0.35)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { g in
                            AppRow(group: g, columns: cols, isSelected: selection == g.id, cores: model.coreCount,
                                   total: model.totalMemory, units: units, norm: norm)
                                .equatable()
                                .onTapGesture(count: 2) { selection = g.id; onOpen(g.id) }
                                .onTapGesture { selection = g.id }
                                .contextMenu { GroupActions(group: g) }
                        }
                    }
                    .padding(8)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .focusable()
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.return) { if let s = selection { onOpen(s) }; return .handled }
            }
        }
    }

    private func visibleColumns(width: CGFloat) -> [AppColumn] {
        var c: [AppColumn] = [.name, .cpu, .memory]
        if width >= 560 { c.append(.processes) }
        if width >= 680 { c.insert(.energy, at: 3) }
        if width >= 790 { c.insert(.disk, at: c.contains(.energy) ? 4 : 3) }
        if width >= 900 && showNetwork { c.insert(.network, at: c.firstIndex(of: .processes) ?? c.count) }
        return c
    }

    private func header(_ cols: [AppColumn]) -> some View {
        HStack(spacing: 0) {
            ForEach(cols) { col in
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        if sort.column == col { sort.ascending.toggle() } else { sort = SortSpec(column: col, ascending: col.startsAscending) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if col != .name { Spacer(minLength: 0) }
                        Text(col.title(norm)).lineLimit(1)
                        if sort.column == col {
                            Image(systemName: sort.ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                                .transition(.scale.combined(with: .opacity))
                        }
                        if col == .name { Spacer(minLength: 0) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(sort.column == col ? Color.primary : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: col.width, alignment: .leading)
                .frame(maxWidth: col.width == nil ? .infinity : nil)
                .padding(.leading, col == .name ? 52 : 0)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func move(_ d: Int) {
        guard !rows.isEmpty else { return }
        let i = rows.firstIndex { $0.id == selection } ?? (d > 0 ? -1 : rows.count)
        selection = rows[min(max(i + d, 0), rows.count - 1)].id
    }
}

struct AppRow: View, Equatable {
    let group: GroupSnapshot
    let columns: [AppColumn]
    let isSelected: Bool
    let cores: Int
    let total: UInt64
    let units: ByteUnits
    let norm: CPUNormalization
    @State private var hovering = false

    static func == (a: AppRow, b: AppRow) -> Bool {
        a.group == b.group && a.columns == b.columns && a.isSelected == b.isSelected && a.units == b.units && a.norm == b.norm
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns) { col in
                cell(col)
                    .frame(width: col.width, alignment: col == .name ? .leading : .trailing)
                    .frame(maxWidth: col.width == nil ? .infinity : nil, alignment: .leading)
            }
        }
        .padding(.horizontal, 8).frame(height: 44)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (hovering ? Color.primary.opacity(0.06) : .clear))
                .overlay { if isSelected { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.accentColor.opacity(0.45)) } }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder private func cell(_ col: AppColumn) -> some View {
        switch col {
        case .name: AppNameCell(group: group)
        case .cpu:
            if let raw = group.cpuPercent {
                BarCell(text: Fmt.percent(Fmt.cpu(raw, cores: cores, norm)), fraction: raw / (Double(cores) * 100) * 4,
                        severity: Severity.cpu(raw, cores: cores)).padding(.trailing, 14)
            } else { UnavailableLabel(text: "—").padding(.trailing, 14) }
        case .memory:
            if let m = group.memoryBytes {
                BarCell(text: Fmt.bytes(m, units), fraction: Double(m) / Double(total) * 4, severity: Severity.memory(m, total: total),
                        help: "Physical memory footprint summed over \(group.processCount) process(es)").padding(.trailing, 14)
            } else { UnavailableLabel(text: "—").padding(.trailing, 14) }
        case .energy:
            if let p = group.powerMilliwatts {
                Text(Fmt.power(p)).monospacedDigit().foregroundStyle(p > 2000 ? Color.orange : .primary).padding(.trailing, 14)
            } else { UnavailableLabel(text: "—").padding(.trailing, 14) }
        case .disk:
            if group.diskReadBps != nil { Text(Fmt.rate(group.diskSort, units)).monospacedDigit().padding(.trailing, 14) }
            else { UnavailableLabel(text: "—").padding(.trailing, 14) }
        case .network:
            if group.netInBps != nil { Text(Fmt.rate(group.netSort, units)).monospacedDigit().padding(.trailing, 14) }
            else { Text("…").foregroundStyle(.tertiary).padding(.trailing, 14) }
        case .processes:
            Text("\(group.processCount)").monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
