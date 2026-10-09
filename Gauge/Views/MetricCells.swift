import SwiftUI

/// Number plus a thin gradient meter; turns orange/red when usage is unusually high.
struct BarCell: View {
    let text: String
    let fraction: Double
    let severity: Severity
    var help: String = ""
    var body: some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(severity == .normal ? Color.primary : severity.color)
            .fontWeight(severity == .normal ? .regular : .semibold)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.vertical, 3)
            .background(alignment: .bottomLeading) {
                Capsule().fill(severity.color.gradient.opacity(severity == .normal ? 0.55 : 1))
                    .frame(height: 3)
                    .scaleEffect(x: max(0.001, min(1, fraction)), y: 1, anchor: .leading)
                    .padding(.horizontal, 2)
            }
            .help(help)
    }
}

struct AppNameCell: View {
    let group: GroupSnapshot
    var body: some View {
        HStack(spacing: 10) {
            AppNameIcon(group: group).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(group.name).lineLimit(1).fontWeight(.medium)
                if group.kind != .application {
                    Text("Not attributed to an app").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if group.inferredCount > 0 {
                Image(systemName: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
                    .help("\(group.inferredCount) process(es) were attributed by parent-process ancestry and may be imprecise.")
            }
            if group.unreadableCount > 0 {
                Image(systemName: "lock").font(.caption).foregroundStyle(.secondary)
                    .help("\(group.unreadableCount) process(es) are protected by macOS; their usage is not included.")
            }
        }
    }
}

struct AppNameIcon: View {
    let group: GroupSnapshot
    var body: some View {
        switch group.kind {
        case .application: Image(nsImage: IconCache.shared.icon(forBundlePath: group.bundlePath)).resizable().interpolation(.high)
        case .systemServices, .macOSServices: Image(systemName: "gearshape.2.fill").resizable().scaledToFit().foregroundStyle(.secondary)
        case .backgroundServices: Image(systemName: "terminal.fill").resizable().scaledToFit().foregroundStyle(.secondary)
        }
    }
}
