import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: Pref.showMenuBar)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hop to the next run-loop turn so nothing runs inside launch-time AppKit initialisation.
        Task { @MainActor in MonitorModel.shared.start() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { MonitorModel.shared.shutdown() }
    }
}

@main
struct GaugeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(Pref.showMenuBar) private var showMenuBar = true
    private var model: MonitorModel { MonitorModel.shared }   // not touched before registerDefaults() has run
    @StateObject private var updater = UpdateController()

    init() {
        Pref.registerDefaults()
        if CommandLine.arguments.contains("--dump") { HeadlessDump.run() }
    }

    var body: some Scene {
        Window("Gauge", id: "main") {
            RootView().environment(model).injectPreferences()
        }
        .defaultSize(width: 1240, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }.disabled(!updater.canCheck)
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarPopover().environment(model).injectPreferences()
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView(updatesTab: AnyView(UpdatesTab(updater: updater))).environment(model) }
    }
}

/// `Gauge --dump [seconds]` prints one measured sample as JSON and exits (used for validation
/// against Activity Monitor / top, and for headless smoke tests).
enum HeadlessDump {
    static func run() -> Never {
        let args = CommandLine.arguments
        let gap = args.firstIndex(of: "--dump").flatMap { Double(args.dropFirst($0 + 1).first ?? "") } ?? 2
        let sem = DispatchSemaphore(value: 0)
        var out = ""
        Task.detached {
            let sampler = Sampler()
            let ctx = SamplingContext(regularAppPaths: [], includeProcesses: true, network: nil)
            _ = await sampler.sample(ctx)
            try? await Task.sleep(for: .seconds(gap))
            let s = await sampler.sample(ctx)
            var procs: [[String: Any]] = []
            for g in s.groups { for p in g.processes {
                procs.append(["pid": Int(p.pid), "name": p.name, "group": g.name, "reason": p.reason.rawValue,
                              "cpu": p.rates?.cpuPercent as Any? ?? NSNull(), "mem": p.memoryBytes.map { Int($0) } as Any? ?? NSNull()])
            } }
            let groups = s.groups.sorted { $0.cpuSort > $1.cpuSort }.map { g -> [String: Any] in
                ["name": g.name, "kind": "\(g.kind)", "procs": g.processCount, "cpu": g.cpuPercent as Any? ?? NSNull(),
                 "mem": g.memoryBytes.map { Int($0) } as Any? ?? NSNull(), "inferred": g.inferredCount, "unreadable": g.unreadableCount]
            }
            let sys: [String: Any] = ["cpu": s.system.cpu?.total as Any? ?? NSNull(), "memUsed": s.system.memory.map { Int($0.usedBytes) } as Any? ?? NSNull(),
                "gpu": s.system.gpuUtilization as Any? ?? NSNull(), "sampleMs": s.diagnostics.sampleDurationMs, "processes": s.diagnostics.processCount]
            let data = try? JSONSerialization.data(withJSONObject: ["system": sys, "groups": groups, "processes": procs], options: [.sortedKeys])
            out = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            sem.signal()
        }
        sem.wait()
        print(out)
        exit(0)
    }
}
