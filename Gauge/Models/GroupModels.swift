import Foundation

struct GroupKey: Hashable, Sendable {
    let value: String
    static let system = GroupKey(value: "pseudo:system")
    static let background = GroupKey(value: "pseudo:background")
    static let macOS = GroupKey(value: "pseudo:macos")
}

enum GroupKind: Sendable { case application, systemServices, macOSServices, backgroundServices }

/// How a process was tied to its group. Anything weaker than `.bundlePath` is reported as such.
enum AttributionReason: String, Sendable {
    case bundlePath          // executable lives inside the app bundle (certain)
    case responsibleProcess  // macOS "responsible process" points at the app (strong)
    case ancestry            // inferred from the parent-process chain (weaker)
    case unattributed        // no owning application could be established

    var isInferred: Bool { self == .ancestry }

    var explanation: String {
        switch self {
        case .bundlePath: return "Executable is inside the app bundle"
        case .responsibleProcess: return "macOS reports the app as responsible for this process"
        case .ancestry: return "Inferred from the parent-process chain"
        case .unattributed: return "No owning application could be determined"
        }
    }
}

struct AppBundleInfo: Sendable, Equatable {
    var path: String
    var name: String
    var bundleID: String?
}

struct Attribution: Sendable, Equatable {
    var key: GroupKey
    var kind: GroupKind
    var reason: AttributionReason
    var bundle: AppBundleInfo?
}

struct ProcessSnapshot: Identifiable, Sendable, Equatable {
    var id: ProcessIdentity
    var parentPID: Int32
    var uid: UInt32
    var name: String
    var path: String?
    var memoryBytes: UInt64?
    var rates: ProcessRates?
    var reason: AttributionReason
    var net: NetRate?
    var pid: Int32 { id.pid }
    var isReadable: Bool { memoryBytes != nil }
}

struct GroupSnapshot: Identifiable, Sendable, Equatable {
    let key: GroupKey
    let kind: GroupKind
    let name: String
    let bundleID: String?
    let bundlePath: String?
    let isRegularApp: Bool
    let processes: [ProcessSnapshot]

    // Aggregates – nil means "unavailable", never "zero".
    let cpuPercent: Double?
    let memoryBytes: UInt64?
    let powerMilliwatts: Double?
    let diskReadBps: Double?
    let diskWriteBps: Double?
    let netInBps: Double?
    let netOutBps: Double?
    let unreadableCount: Int
    let inferredCount: Int
    let rootPID: Int32?

    var id: String { key.value }
    var processCount: Int { processes.count }

    // Non-optional sort keys for Table comparators.
    var cpuSort: Double { cpuPercent ?? -1 }
    var memorySort: UInt64 { memoryBytes ?? 0 }
    var powerSort: Double { powerMilliwatts ?? -1 }
    var diskSort: Double { (diskReadBps ?? 0) + (diskWriteBps ?? 0) }
    var netSort: Double { (netInBps ?? 0) + (netOutBps ?? 0) }

    /// True for a user-facing application (as opposed to OS plumbing).
    var isUserApp: Bool {
        guard kind == .application, let p = bundlePath else { return false }
        if isRegularApp { return true }
        return !(p.hasPrefix("/System/") || p.hasPrefix("/usr/") || p.hasPrefix("/Library/Apple/")
                 || p.hasPrefix("/Library/Developer/"))
    }
}

extension GroupSnapshot {
    init(key: GroupKey, kind: GroupKind, name: String, bundleID: String?, bundlePath: String?,
         isRegularApp: Bool, processes: [ProcessSnapshot], hasNetwork: Bool) {
        self.key = key; self.kind = kind; self.name = name; self.bundleID = bundleID
        self.bundlePath = bundlePath; self.isRegularApp = isRegularApp; self.processes = processes

        let readable = processes.filter { $0.isReadable }
        self.unreadableCount = processes.count - readable.count
        self.inferredCount = processes.filter { $0.reason.isInferred }.count
        self.memoryBytes = readable.isEmpty ? nil : readable.reduce(0) { $0 + ($1.memoryBytes ?? 0) }

        let withRates = processes.compactMap { $0.rates }
        if withRates.isEmpty {
            cpuPercent = nil; powerMilliwatts = nil; diskReadBps = nil; diskWriteBps = nil
        } else {
            cpuPercent = withRates.reduce(0) { $0 + $1.cpuPercent }
            powerMilliwatts = withRates.reduce(0) { $0 + $1.powerMilliwatts }
            diskReadBps = withRates.reduce(0) { $0 + $1.diskReadBps }
            diskWriteBps = withRates.reduce(0) { $0 + $1.diskWriteBps }
        }
        if hasNetwork {
            netInBps = processes.reduce(0) { $0 + ($1.net?.inBps ?? 0) }
            netOutBps = processes.reduce(0) { $0 + ($1.net?.outBps ?? 0) }
        } else { netInBps = nil; netOutBps = nil }

        // Main process: oldest process whose executable is inside the bundle (or oldest overall).
        let inBundle = bundlePath.map { b in processes.filter { $0.path?.hasPrefix(b) == true } } ?? []
        let pool = inBundle.isEmpty ? processes : inBundle
        self.rootPID = pool.min(by: { $0.id.startTimeMicros < $1.id.startTimeMicros })?.pid
    }
}
