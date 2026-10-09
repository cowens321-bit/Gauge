import Foundation

/// Unique identity of a process instance. PIDs are recycled by the kernel, so the start
/// time is part of the identity: the same pid with a different start time is a different process.
struct ProcessIdentity: Hashable, Sendable, CustomStringConvertible {
    let pid: Int32
    /// Process start time in microseconds since the Unix epoch.
    let startTimeMicros: UInt64
    var description: String { "\(pid)@\(startTimeMicros)" }
}

/// Cumulative per-process counters as reported by `proc_pid_rusage`.
struct ProcessCounters: Sendable, Equatable {
    var cpuTimeNs: UInt64          // user + system, nanoseconds
    var footprintBytes: UInt64     // phys_footprint (the figure Activity Monitor calls "Memory")
    var diskReadBytes: UInt64
    var diskWriteBytes: UInt64
    var billedEnergyNJ: UInt64     // nanojoules billed to the process
}

/// One process as seen at a single sample. `counters == nil` means the kernel denied access
/// (typically another user's / root's process) – the values are unavailable, not zero.
struct ProcessRecord: Sendable, Equatable {
    var id: ProcessIdentity
    var parentPID: Int32
    var uid: UInt32
    var name: String
    var path: String?
    var counters: ProcessCounters?
    var pid: Int32 { id.pid }
}

/// Rates derived from two consecutive samples.
struct ProcessRates: Sendable, Equatable {
    /// 100 == one fully busy core (Activity Monitor convention).
    var cpuPercent: Double
    var diskReadBps: Double
    var diskWriteBps: Double
    var powerMilliwatts: Double
}

struct NetRate: Sendable, Equatable {
    var inBps: Double
    var outBps: Double
}
