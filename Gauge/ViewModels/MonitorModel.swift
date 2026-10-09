import SwiftUI
import AppKit

enum PendingActionKind { case quit, forceQuit, killProcess(ProcessSnapshot, force: Bool) }
struct PendingAction: Identifiable {
    let id = UUID()
    let kind: PendingActionKind
    let group: GroupSnapshot
}

/// Owns the sampling loop and the in-memory history. All heavy work happens in `Sampler` (off the
/// main actor); this type only applies finished snapshots.
@MainActor @Observable
final class MonitorModel {
    static let shared = MonitorModel()

    private(set) var snapshot: Snapshot?
    private(set) var menuBarImage = NSImage()
    private(set) var systemHistory = TimeSeries<SystemPoint>()
    private(set) var groupHistory: [String: TimeSeries<GroupPoint>] = [:]
    private(set) var interval: Double = 2
    private(set) var isSampling = false
    var pending: PendingAction?
    var lastActionMessage: String?

    var windowVisible = false { didSet { if oldValue != windowVisible { reevaluate() } } }
    var popoverVisible = false { didSet { if oldValue != popoverVisible { reevaluate() } } }

    @ObservationIgnored private let sampler = Sampler()
    @ObservationIgnored private let nettop = NettopNetworkSource()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var loopSignature = ""
    @ObservationIgnored private var nettopInterval: Double?
    @ObservationIgnored private var historySeconds: TimeInterval = 600
    @ObservationIgnored private var observer: NSObjectProtocol?

    let coreCount = ProcessInfo.processInfo.activeProcessorCount
    let totalMemory = ProcessInfo.processInfo.physicalMemory

    private init() {
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reevaluate() }
        }
    }

    func group(id: String) -> GroupSnapshot? { snapshot?.groups.first { $0.id == id } }

    func shutdown() { loop?.cancel(); nettop.stop() }

    // MARK: Scheduling
    func reevaluate() {
        let d = UserDefaults.standard
        let interval = d.double(forKey: Pref.refreshInterval)
        let menuBar = d.bool(forKey: Pref.showMenuBar)
        let wantNet = d.bool(forKey: Pref.perAppNetwork)
        historySeconds = max(1, d.double(forKey: Pref.historyMinutes)) * 60
        self.interval = interval
        refreshMenuBarImage()

        let wantsProcs = windowVisible || popoverVisible
        let wantsAny = interval > 0 && (wantsProcs || menuBar)
        let useNet = wantsAny && wantsProcs && wantNet
        if useNet {
            if !nettop.isRunning || nettopInterval != interval { nettop.start(interval: interval); nettopInterval = interval }
        } else if nettop.isRunning { nettop.stop(); nettopInterval = nil }

        guard wantsAny else { loop?.cancel(); loop = nil; loopSignature = ""; isSampling = false; return }
        let sig = "\(interval)|\(wantsProcs)|net\(useNet ? 1 : 0)"
        if sig == loopSignature, loop != nil { return }
        loopSignature = sig
        loop?.cancel()
        isSampling = true
        loop = Task { [weak self] in await self?.run(interval: interval, procs: wantsProcs, net: useNet) }
    }

    private func context(procs: Bool, net: Bool) -> SamplingContext {
        var regular = Set<String>()
        if procs {
            for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular {
                if let p = a.bundleURL?.path { regular.insert(p) }
            }
        }
        return SamplingContext(regularAppPaths: regular, includeProcesses: procs, network: net ? nettop : nil)
    }

    private func run(interval: Double, procs: Bool, net: Bool) async {
        if procs {
            await sampler.resetProcessBaseline()
            _ = await sampler.sample(context(procs: true, net: net))
            try? await Task.sleep(for: .milliseconds(600))
        }
        while !Task.isCancelled {
            let snap = await sampler.sample(context(procs: procs, net: net))
            if Task.isCancelled { return }
            withAnimation(.smooth(duration: 0.35)) { apply(snap) }
            try? await Task.sleep(for: .seconds(interval), tolerance: .milliseconds(150))
        }
    }

    // MARK: History
    private func apply(_ s: Snapshot) {
        let prior = snapshot
        // Keep the last full process list visible when a system-only sample arrives.
        snapshot = s.hasProcessData ? s : Snapshot(date: s.date, system: s.system, groups: prior?.groups ?? [],
                                                   diagnostics: prior?.diagnostics ?? s.diagnostics,
                                                   hasProcessData: false, hasNetworkData: false)
        let gb = 1_073_741_824.0
        let m = s.system.memory
        let p = SystemPoint(t: s.date, cpuUser: s.system.cpu?.user ?? 0, cpuSystem: s.system.cpu?.system ?? 0,
                            memUsedPct: (m?.usedFraction ?? 0) * 100,
                            memApp: Double(m?.appBytes ?? 0) / gb, memWired: Double(m?.wiredBytes ?? 0) / gb,
                            memCompressed: Double(m?.compressedBytes ?? 0) / gb,
                            gpu: s.system.gpuUtilization, netIn: s.system.network?.inBps, netOut: s.system.network?.outBps,
                            diskRead: s.system.disk?.inBps, diskWrite: s.system.disk?.outBps)
        systemHistory.append(p, keeping: historySeconds)
        refreshMenuBarImage()

        guard s.hasProcessData else { return }
        var seen = Set<String>()
        for g in s.groups {
            seen.insert(g.id)
            var series = groupHistory[g.id] ?? TimeSeries<GroupPoint>()
            series.append(GroupPoint(t: s.date, cpu: g.cpuPercent, mem: g.memoryBytes.map { Double($0) },
                                     disk: g.diskReadBps.map { $0 + (g.diskWriteBps ?? 0) },
                                     net: g.netInBps.map { $0 + (g.netOutBps ?? 0) }), keeping: historySeconds)
            groupHistory[g.id] = series
        }
        let cutoff = s.date.addingTimeInterval(-historySeconds)
        for k in groupHistory.keys where !seen.contains(k) {
            groupHistory[k]?.trim(olderThan: cutoff)
            if groupHistory[k]?.isEmpty == true { groupHistory[k] = nil }
        }
    }

    var historyWindow: TimeInterval { historySeconds }

    /// Chart x-range that grows with the data we actually have (min 60 s) up to `cap`, so a fresh
    /// launch does not show a mostly empty 10-minute axis.
    func chartWindow<P: Timestamped>(_ pts: [P], cap: TimeInterval? = nil) -> TimeInterval {
        let upper = min(cap ?? historySeconds, historySeconds)
        guard let f = pts.first, let l = pts.last else { return min(60, upper) }
        return min(upper, max(60, l.t.timeIntervalSince(f.t) * 1.05))
    }

    /// 0...1 "how stressed is the machine", drives the ambient background tint.
    var heat: Double {
        guard let s = snapshot?.system else { return 0 }
        let cpu = (s.cpu?.total ?? 0) / 100
        let mem: Double = switch s.memory?.pressure { case .critical: 1; case .warning: 0.55; default: 0 }
        return max(cpu * 1.15, mem)
    }

    func refreshMenuBarImage() {
        guard UserDefaults.standard.bool(forKey: Pref.showMenuBar) else { return }
        menuBarImage = MenuBarRenderer.render(snapshot: snapshot?.system, history: systemHistory)
    }
}
