import SwiftUI
import AppKit

enum Pref {
    static let refreshInterval = "refreshInterval"          // seconds; 0 == paused
    static let launchAtLogin = "launchAtLogin"            // desired default; the system holds the real state
    static let loginItemConfigured = "loginItemConfigured"
    static let showMenuBar = "showMenuBar"
    static let menuBarCPU = "menuBarCPU"
    static let menuBarMemory = "menuBarMemory"
    static let menuBarNetwork = "menuBarNetwork"
    static let menuBarGraph = "menuBarGraph"
    static let menuBarGPU = "menuBarGPU"
    static let menuBarDisk = "menuBarDisk"
    static let menuBarStorage = "menuBarStorage"
    static let menuBarStyle = "menuBarStyle"
    static let appearance = "appearance"
    static let defaultSort = "defaultSort"
    static let displayUnits = "displayUnits"
    static let historyMinutes = "historyMinutes"
    static let cpuNormalization = "cpuNormalization"
    static let perAppNetwork = "perAppNetwork"
    static let listScope = "listScope"
    static let visualEffects = "visualEffects"
    static let showInDock = "showInDock"
    static let alertsEnabled = "alertsEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            refreshInterval: 2.0, launchAtLogin: true, showMenuBar: true,
            menuBarCPU: true, menuBarMemory: true, menuBarNetwork: false, menuBarGraph: true,
            menuBarGPU: false, menuBarDisk: false, menuBarStorage: false, menuBarStyle: MenuBarStyle.value.rawValue, showInDock: false, alertsEnabled: false,
            appearance: AppearanceMode.system.rawValue, defaultSort: SortKey.cpu.rawValue,
            displayUnits: ByteUnits.binary.rawValue, historyMinutes: 10,
            cpuNormalization: CPUNormalization.perCore.rawValue, perAppNetwork: false,
            listScope: ListScope.userApps.rawValue, visualEffects: VisualEffects.glass.rawValue,
        ])
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? { self == .light ? .light : self == .dark ? .dark : nil }
    var nsAppearance: NSAppearance? {
        switch self { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) }
    }
}

enum ByteUnits: String, CaseIterable, Identifiable {
    case binary, decimal
    var id: String { rawValue }
    var title: String { self == .binary ? "Binary (GiB, MiB)" : "Decimal (GB, MB)" }
}

enum CPUNormalization: String, CaseIterable, Identifiable {
    case perCore, machine
    var id: String { rawValue }
    var title: String { self == .perCore ? "Per core (100% = one core)" : "Whole machine (100% = all cores)" }
}

enum SortKey: String, CaseIterable, Identifiable {
    case cpu, memory, name, energy, processes
    var id: String { rawValue }
    var title: String { self == .cpu ? "CPU" : rawValue.capitalized }
}

enum ListScope: String, CaseIterable, Identifiable {
    case userApps, allApps, everything
    var id: String { rawValue }
    var title: String {
        switch self { case .userApps: "Apps"; case .allApps: "All Apps"; case .everything: "Everything" }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case value, graph, both
    var id: String { rawValue }
    var title: String { switch self { case .value: "Values"; case .graph: "Graphs"; case .both: "Values & Graphs" } }
}

enum VisualEffects: String, CaseIterable, Identifiable {
    case glass, reduced
    var id: String { rawValue }
    var title: String { self == .glass ? "Liquid Glass" : "Reduced (lower CPU)" }
}

enum RefreshOption: Double, CaseIterable, Identifiable {
    case paused = 0, one = 1, two = 2, five = 5, ten = 10
    var id: Double { rawValue }
    var title: String { self == .paused ? "Paused" : "\(Int(rawValue)) second\(rawValue == 1 ? "" : "s")" }
}

private struct UnitsKey: EnvironmentKey { static let defaultValue = ByteUnits.binary }
private struct ReducedKey: EnvironmentKey { static let defaultValue = false }
private struct NormKey: EnvironmentKey { static let defaultValue = CPUNormalization.perCore }
extension EnvironmentValues {
    var byteUnits: ByteUnits { get { self[UnitsKey.self] } set { self[UnitsKey.self] = newValue } }
    var cpuNormalization: CPUNormalization { get { self[NormKey.self] } set { self[NormKey.self] = newValue } }
    /// True when live panels should use plain materials instead of Liquid Glass.
    var reducedEffects: Bool { get { self[ReducedKey.self] } set { self[ReducedKey.self] = newValue } }
}

/// Injects user preferences into the environment for any scene.
struct PreferencesInjector: ViewModifier {
    @AppStorage(Pref.displayUnits) private var units = ByteUnits.binary
    @AppStorage(Pref.cpuNormalization) private var norm = CPUNormalization.perCore
    @AppStorage(Pref.appearance) private var appearance = AppearanceMode.system
    @AppStorage(Pref.visualEffects) private var effects = VisualEffects.glass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.environment(\.byteUnits, units).environment(\.cpuNormalization, norm)
            .environment(\.reducedEffects, effects == .reduced || reduceTransparency)
            .preferredColorScheme(appearance.colorScheme)
    }
}
extension View { func injectPreferences() -> some View { modifier(PreferencesInjector()) } }
