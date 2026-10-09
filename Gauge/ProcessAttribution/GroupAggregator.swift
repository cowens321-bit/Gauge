import Foundation

enum GroupAggregator {
    static func build(records: [ProcessRecord],
                      attributions: [ProcessIdentity: Attribution],
                      rates: [ProcessIdentity: ProcessRates],
                      network: [Int32: NetRate]?,
                      regularAppPaths: Set<String>) -> [GroupSnapshot] {
        var buckets: [GroupKey: (attr: Attribution, procs: [ProcessSnapshot])] = [:]
        for r in records {
            guard let a = attributions[r.id] else { continue }
            let snap = ProcessSnapshot(id: r.id, parentPID: r.parentPID, uid: r.uid, name: r.name, path: r.path,
                                       memoryBytes: r.counters?.footprintBytes, rates: rates[r.id],
                                       reason: a.reason, net: network?[r.pid])
            buckets[a.key, default: (a, [])].procs.append(snap)
        }
        return buckets.map { key, b in
            let kind = b.attr.kind
            let name: String
            switch kind {
            case .application: name = b.attr.bundle?.name ?? key.value
            case .systemServices: name = "System Services (root)"
            case .macOSServices: name = "macOS Services"
            case .backgroundServices: name = "Background Services"
            }
            return GroupSnapshot(key: key, kind: kind, name: name,
                                 bundleID: b.attr.bundle?.bundleID, bundlePath: b.attr.bundle?.path,
                                 isRegularApp: b.attr.bundle.map { regularAppPaths.contains($0.path) } ?? false,
                                 processes: b.procs.sorted { ($0.memoryBytes ?? 0) > ($1.memoryBytes ?? 0) },
                                 hasNetwork: network != nil)
        }
    }
}
