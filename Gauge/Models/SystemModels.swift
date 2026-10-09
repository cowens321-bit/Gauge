import Foundation

enum MemoryPressure: Int, Sendable { case normal = 1, warning = 2, critical = 4
    var label: String { switch self { case .normal: "Normal"; case .warning: "Warning"; case .critical: "Critical" } }
}

struct CPUUsage: Sendable, Equatable {
    /// Whole-machine percentages (0–100 == all cores busy).
    var user: Double
    var system: Double
    var total: Double { min(100, user + system) }
    var coreCount: Int
}

struct MemoryUsage: Sendable, Equatable {
    var totalBytes: UInt64
    var appBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var cachedBytes: UInt64
    var freeBytes: UInt64
    var swapUsedBytes: UInt64
    var pressure: MemoryPressure
    var usedBytes: UInt64 { appBytes + wiredBytes + compressedBytes }
    var usedFraction: Double { totalBytes == 0 ? 0 : min(1, Double(usedBytes) / Double(totalBytes)) }
}

struct Throughput: Sendable, Equatable {
    var inBps: Double   // read / download
    var outBps: Double  // write / upload
}

struct StorageUsage: Sendable, Equatable {
    var totalBytes: UInt64
    var availableBytes: UInt64
    var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }
    var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
}

struct SystemSnapshot: Sendable, Equatable {
    var date: Date
    var cpu: CPUUsage?
    var memory: MemoryUsage?
    var gpuUtilization: Double?     // 0–100, nil when the GPU exposes no counter
    var network: Throughput?
    var disk: Throughput?
    var storage: StorageUsage?
    var thermalState: ProcessInfo.ThermalState
}

struct Diagnostics: Sendable, Equatable {
    var processCount = 0
    var unreadableProcessCount = 0
    var responsibilityAPIAvailable = false
    var sampleDurationMs = 0.0
}

struct Snapshot: Sendable, Equatable {
    var date: Date
    var system: SystemSnapshot
    var groups: [GroupSnapshot]
    var diagnostics: Diagnostics
    var hasProcessData: Bool
    var hasNetworkData: Bool
}
