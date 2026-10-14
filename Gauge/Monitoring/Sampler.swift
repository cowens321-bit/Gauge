import Foundation

struct SamplingContext: Sendable {
    var regularAppPaths: Set<String>
    var includeProcesses: Bool
    var network: (any NetworkRateSource)?
}

/// Performs all expensive sampling off the main actor.
actor Sampler {
    private let source: ProcessSource
    private let system: SystemMetricsProvider
    private var tracker = RateTracker()
    private let caches = AttributionCaches()
    private var responsibleCache: [ProcessIdentity: Int32] = [:]

    init(source: ProcessSource = LibprocSource(), system: SystemMetricsProvider = MachSystemMetrics()) {
        self.source = source
        self.system = system
    }

    func resetProcessBaseline() { tracker.reset() }

    func sample(_ ctx: SamplingContext) -> Snapshot {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let sys = system.read(uptimeNs: t0)
        var groups: [GroupSnapshot] = []
        var diag = Diagnostics(responsibilityAPIAvailable: source.responsibilityAPIAvailable)

        if ctx.includeProcesses {
            let records = source.readProcesses()
            let wall = UInt64(Date().timeIntervalSince1970 * 1_000_000)
            let rates = tracker.update(records: records, uptimeNs: DispatchTime.now().uptimeNanoseconds, wallMicros: wall)

            // Responsible-pid lookups are cached per process identity.
            var responsible: [Int32: Int32] = [:]
            var live = Set<ProcessIdentity>()
            for r in records {
                live.insert(r.id)
                if let c = responsibleCache[r.id] { responsible[r.pid] = c; continue }
                if let rp = source.responsiblePID(of: r.pid) { responsibleCache[r.id] = rp; responsible[r.pid] = rp }
            }
            if responsibleCache.count > live.count + 128 { responsibleCache = responsibleCache.filter { live.contains($0.key) } }

            let caches = self.caches
            caches.prepare(regular: ctx.regularAppPaths)
            let engine = AttributionEngine(bundleInfo: { caches.info($0) },
                                           owningBundleOf: { caches.owner(of: $0) })
            let attributions = engine.attribute(records, context: AttributionContext(regularAppPaths: ctx.regularAppPaths, responsible: responsible))
            let net = ctx.network.map { $0.currentRates() }
            groups = GroupAggregator.build(records: records, attributions: attributions, rates: rates,
                                           network: net, regularAppPaths: ctx.regularAppPaths)
            diag.processCount = records.count
            diag.unreadableProcessCount = records.filter { $0.counters == nil }.count
        }
        diag.sampleDurationMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        return Snapshot(date: Date(), system: sys, groups: groups, diagnostics: diag,
                        hasProcessData: ctx.includeProcesses, hasNetworkData: ctx.network != nil && ctx.includeProcesses)
    }

    static func readBundle(_ path: String) -> AppBundleInfo? {
        let infoPlist = path + "/Contents/Info.plist"
        guard let d = NSDictionary(contentsOfFile: infoPlist) else { return nil }
        let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let name = [d["CFBundleDisplayName"] as? String, d["CFBundleName"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? fileName
        return AppBundleInfo(path: path, name: name, bundleID: d["CFBundleIdentifier"] as? String)
    }
}

/// Per-path results that only change when apps launch/quit: owning bundle of an executable path and the
/// bundle's Info.plist name/identifier. Kept across ticks (only touched from inside the Sampler actor).
final class AttributionCaches: @unchecked Sendable {
    private var owners: [String: String?] = [:]
    private var infos: [String: AppBundleInfo?] = [:]
    private var regular: Set<String> = []

    func prepare(regular newRegular: Set<String>) {
        if newRegular != regular { regular = newRegular; owners.removeAll(keepingCapacity: true) }
        if owners.count > 20_000 { owners.removeAll() }   // bound memory on pathological systems
        if infos.count > 2_000 { infos.removeAll() }
    }
    func owner(of path: String) -> String? {
        if let hit = owners[path] { return hit }
        let o = AttributionEngine.owningBundle(forPath: path, regular: regular)
        owners[path] = o
        return o
    }
    func info(_ bundlePath: String) -> AppBundleInfo? {
        if let hit = infos[bundlePath] { return hit }
        let i = Sampler.readBundle(bundlePath)
        infos[bundlePath] = i
        return i
    }
}
