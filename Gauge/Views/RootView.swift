import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case applications, system
    var id: String { rawValue }
    var title: String { self == .applications ? "Applications" : "System" }
    var symbol: String { self == .applications ? "square.grid.2x2.fill" : "waveform.path.ecg" }
}

struct RootView: View {
    @Environment(MonitorModel.self) private var model
    @AppStorage(Pref.refreshInterval) private var refresh = 2.0
    @AppStorage(Pref.startMinimized) private var startMinimized = false
    @State private var selection: SidebarItem? =
        SidebarItem(rawValue: UserDefaults.standard.string(forKey: "launchPage") ?? "") ?? .applications

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
            .safeAreaInset(edge: .bottom) { status }
        } detail: {
            Group {
                switch selection ?? .applications {
                case .applications: ApplicationsView()
                case .system: SystemView()
                }
            }
            .background { AmbientBackground(heat: model.heat) }
        }
        .navigationTitle("Gauge")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Refresh", selection: $refresh) {
                        ForEach(RefreshOption.allCases) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.inline)
                } label: {
                    Label(refresh == 0 ? "Paused" : "\(Int(refresh)) s", systemImage: refresh == 0 ? "pause.circle" : "timer")
                }
                .help("Refresh interval")
            }
        }
        .background(WindowVisibilityReader(onChange: { model.windowVisible = $0 }, onFirstAppear: { w in
            if let screen = w.screen ?? NSScreen.main {          // never open larger than / outside the display
                var f = w.frame
                let v = screen.visibleFrame
                f.size.width = min(f.width, v.width); f.size.height = min(f.height, v.height)
                f.origin.x = min(max(f.origin.x, v.minX), v.maxX - f.width)
                f.origin.y = min(max(f.origin.y, v.minY), v.maxY - f.height)
                if f != w.frame { w.setFrame(f, display: true) }
            }
            if startMinimized { w.miniaturize(nil) }
        }))
        .onAppear { model.reevaluate() }
        .frame(minWidth: 620, minHeight: 480)
    }

    private var status: some View {
        HStack(spacing: 8) {
            Image(systemName: refresh == 0 ? "pause.circle.fill" : "circle.fill")
                .font(.system(size: 8)).foregroundStyle(refresh == 0 ? Color.orange : Color.green)
                .symbolEffect(.pulse, options: .nonRepeating, value: model.snapshot?.date)
            Text(refresh == 0 ? "Paused" : "Live · every \(Int(refresh)) s").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .padding(10)
    }
}
