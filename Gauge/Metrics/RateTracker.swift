import Foundation

/// Turns successive cumulative counters into rates.
///
/// * Identity is (pid, start time) so a recycled PID never inherits another process's history.
/// * A process that started after the previous sample has its whole lifetime counted as the delta.
/// * A process we could not read, or whose counters went backwards, yields no rate (nil), not zero.
/// * Processes that disappeared are dropped from state on the next update.
struct RateTracker {
    private var previous: [ProcessIdentity: ProcessCounters] = [:]
    private var previousUptimeNs: UInt64?
    private var previousWallMicros: UInt64 = 0

    mutating func reset() { previous = [:]; previousUptimeNs = nil }

    /// `uptimeNs` must be a monotonic clock; `wallMicros` is Unix time used only to detect births.
    mutating func update(records: [ProcessRecord], uptimeNs: UInt64, wallMicros: UInt64)
        -> [ProcessIdentity: ProcessRates] {
        var next: [ProcessIdentity: ProcessCounters] = [:]
        next.reserveCapacity(records.count)
        for r in records { if let c = r.counters { next[r.id] = c } }
        defer { previous = next; previousUptimeNs = uptimeNs; previousWallMicros = wallMicros }

        guard let prevT = previousUptimeNs, uptimeNs > prevT else { return [:] }
        let dt = Double(uptimeNs - prevT) / 1_000_000_000
        var out: [ProcessIdentity: ProcessRates] = [:]
        out.reserveCapacity(records.count)
        for r in records {
            guard let cur = r.counters else { continue }
            let base: ProcessCounters
            if let p = previous[r.id] {
                base = p
            } else if r.id.startTimeMicros >= previousWallMicros {
                base = ProcessCounters(cpuTimeNs: 0, footprintBytes: 0, diskReadBytes: 0, diskWriteBytes: 0, billedEnergyNJ: 0)
            } else {
                continue   // existed before but we never saw it (e.g. was unreadable) – no baseline
            }
            guard cur.cpuTimeNs >= base.cpuTimeNs else { continue }
            let dCPU = Double(cur.cpuTimeNs - base.cpuTimeNs)
            out[r.id] = ProcessRates(
                cpuPercent: dCPU / (dt * 1e9) * 100,
                diskReadBps: Double(Self.sub(cur.diskReadBytes, base.diskReadBytes)) / dt,
                diskWriteBps: Double(Self.sub(cur.diskWriteBytes, base.diskWriteBytes)) / dt,
                powerMilliwatts: Double(Self.sub(cur.billedEnergyNJ, base.billedEnergyNJ)) / dt / 1e6)
        }
        return out
    }

    private static func sub(_ a: UInt64, _ b: UInt64) -> UInt64 { a >= b ? a - b : 0 }
}
