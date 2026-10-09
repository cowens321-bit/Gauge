import Foundation

func rec(_ pid: Int32, start: UInt64 = 1_000_000, ppid: Int32 = 1, uid: UInt32 = 501, name: String? = nil,
         path: String? = nil, cpuNs: UInt64? = 0, mem: UInt64 = 1_000_000,
         read: UInt64 = 0, write: UInt64 = 0, energy: UInt64 = 0) -> ProcessRecord {
    ProcessRecord(id: ProcessIdentity(pid: pid, startTimeMicros: start), parentPID: ppid, uid: uid,
                  name: name ?? "p\(pid)", path: path,
                  counters: cpuNs.map { ProcessCounters(cpuTimeNs: $0, footprintBytes: mem, diskReadBytes: read, diskWriteBytes: write, billedEnergyNJ: energy) })
}

struct FakeSource: ProcessSource {
    var records: [ProcessRecord] = []
    var responsible: [Int32: Int32] = [:]
    var responsibilityAPIAvailable: Bool { true }
    func readProcesses() -> [ProcessRecord] { records }
    func responsiblePID(of pid: Int32) -> Int32? { responsible[pid] }
}

final class FakeSystem: SystemMetricsProvider, @unchecked Sendable {
    func read(uptimeNs: UInt64) -> SystemSnapshot {
        SystemSnapshot(date: Date(), cpu: nil, memory: nil, gpuUtilization: nil, network: nil, disk: nil, storage: nil, thermalState: .nominal)
    }
}

let engine = AttributionEngine(bundleInfo: { path in
    let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    return AppBundleInfo(path: path, name: name, bundleID: "test." + name.replacingOccurrences(of: " ", with: ""))
})

func groupSnapshots(_ records: [ProcessRecord], responsible: [Int32: Int32] = [:], regular: Set<String> = [],
                    rates: [ProcessIdentity: ProcessRates] = [:]) -> [GroupSnapshot] {
    let a = engine.attribute(records, context: AttributionContext(regularAppPaths: regular, responsible: responsible))
    return GroupAggregator.build(records: records, attributions: a, rates: rates, network: nil, regularAppPaths: regular)
}
