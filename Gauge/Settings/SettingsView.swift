import SwiftUI
import ServiceManagement

struct SettingsView: View {
    /// Injected by the app target (keeps Sparkle out of the testable core).
    var updatesTab: AnyView? = nil
    @Environment(MonitorModel.self) private var model
    @AppStorage(Pref.menuBarGPU) private var mbGPU = false
    @AppStorage(Pref.menuBarDisk) private var mbDisk = false
    @AppStorage(Pref.menuBarStorage) private var mbStorage = false
    @AppStorage(Pref.menuBarStyle) private var mbStyle = MenuBarStyle.value
    @AppStorage(Pref.refreshInterval) private var refresh = 10.0
    @AppStorage(Pref.showInDock) private var showInDock = false
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @AppStorage(Pref.showMenuBar) private var showMenuBar = false
    @AppStorage(Pref.menuBarCPU) private var mbCPU = true
    @AppStorage(Pref.menuBarMemory) private var mbMem = true
    @AppStorage(Pref.menuBarNetwork) private var mbNet = false
    @AppStorage(Pref.menuBarGraph) private var mbGraph = true
    @AppStorage(Pref.appearance) private var appearance = AppearanceMode.system
    @AppStorage(Pref.visualEffects) private var effects = VisualEffects.glass
    @AppStorage(Pref.defaultSort) private var sort = SortKey.cpu
    @AppStorage(Pref.displayUnits) private var units = ByteUnits.binary
    @AppStorage(Pref.historyMinutes) private var history = 10
    @AppStorage(Pref.cpuNormalization) private var norm = CPUNormalization.perCore
    @AppStorage(Pref.perAppNetwork) private var perAppNetwork = false
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        TabView {
            Form {
                Picker("Refresh interval", selection: $refresh) {
                    ForEach(RefreshOption.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Chart history", selection: $history) {
                    ForEach([1, 5, 10, 30, 60], id: \.self) { Text("\($0) minute\($0 == 1 ? "" : "s")").tag($0) }
                }
                Text("History is kept in memory only and is never written to disk.").font(.caption).foregroundStyle(.secondary)
                Section("Startup") {
                    Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: setLogin))
                    if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                    Toggle("Show Gauge in the Dock", isOn: $showInDock)
                    Text("Off by default: Gauge lives in the menu bar. Click its icon, then “Open Gauge” for the full window.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Monitoring") {
                    Toggle("Per-app network activity (uses nettop)", isOn: $perAppNetwork)
                    Text("macOS has no public per-process network counters. This runs Apple's nettop tool while the window is open, which adds measurable CPU load.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Picker("Appearance", selection: $appearance) { ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) } }
                if systemReduceTransparency {
                    Label("macOS “Reduce transparency” is on, so Liquid Glass is switched off system-wide. Turn it off in System Settings ▸ Accessibility ▸ Display to see it.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Picker("Visual effects", selection: $effects) { ForEach(VisualEffects.allCases) { Text($0.title).tag($0) } }
                Text("Liquid Glass is GPU-composited and re-rendered whenever live numbers behind it change. Reduced uses standard materials and no animated background; it is also used automatically when macOS “Reduce transparency” is on.").font(.caption).foregroundStyle(.secondary)
                Picker("Default sort", selection: $sort) { ForEach(SortKey.allCases) { Text($0.title).tag($0) } }
                Picker("Display units", selection: $units) { ForEach(ByteUnits.allCases) { Text($0.title).tag($0) } }
                Picker("CPU percentage", selection: $norm) { ForEach(CPUNormalization.allCases) { Text($0.title).tag($0) } }
                Text("Per-core matches Activity Monitor: an app using three cores shows 300%. System-wide CPU is always 0–100%.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("Display", systemImage: "paintbrush") }

            Form {
                Section {
                    Toggle("Show Gauge in the menu bar", isOn: $showMenuBar)
                    LabeledContent("Preview") {
                        Image(nsImage: model.menuBarImage).renderingMode(.template).foregroundStyle(.primary)
                            .padding(.horizontal, 12).padding(.vertical, 6).glassEffect(.regular, in: .capsule)
                    }
                }
                Section("Show live usage for") {
                    Toggle("CPU", systemImage: "cpu", isOn: $mbCPU)
                    Toggle("Memory", systemImage: "memorychip", isOn: $mbMem)
                    Toggle("GPU", systemImage: "square.stack.3d.up.fill", isOn: $mbGPU)
                    Toggle("Network speed", systemImage: "arrow.up.arrow.down", isOn: $mbNet)
                    Toggle("Disk activity", systemImage: "internaldrive", isOn: $mbDisk)
                    Toggle("Free storage", systemImage: "externaldrive", isOn: $mbStorage)
                }.disabled(!showMenuBar)
                Section("Style") {
                    Picker("Display", selection: $mbStyle) { ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                }.disabled(!showMenuBar)
                Text("Temperature isn't offered: macOS provides no supported API for it. Click the menu bar item to toggle metrics quickly.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }

            if let updatesTab { updatesTab.tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") } }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 520)
        .injectPreferences()
        .onChange(of: mbCPU) { model.refreshMenuBarImage() }.onChange(of: mbMem) { model.refreshMenuBarImage() }
        .onChange(of: mbGPU) { model.refreshMenuBarImage() }.onChange(of: mbNet) { model.refreshMenuBarImage() }
        .onChange(of: mbDisk) { model.refreshMenuBarImage() }.onChange(of: mbStorage) { model.refreshMenuBarImage() }
        .onChange(of: mbStyle) { model.refreshMenuBarImage() }
        .onChange(of: showMenuBar) { model.reevaluate() }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = error.localizedDescription }
        loginEnabled = SMAppService.mainApp.status == .enabled
        if on && !loginEnabled && loginError == nil { loginError = "Approve Gauge in System Settings ▸ General ▸ Login Items." }
    }
}
