import Foundation
import Darwin
import IOKit

protocol SystemMetricsProvider: AnyObject, Sendable {
    func read(uptimeNs: UInt64) -> SystemSnapshot
}

/// Whole-machine metrics from supported Mach / sysctl / IOKit interfaces.
/// Only ever touched from the sampler actor.
final class MachSystemMetrics: SystemMetricsProvider, @unchecked Sendable {
    private var prevTicks: [UInt32]?
    private var prevNet: (inB: UInt64, outB: UInt64)?
    private var prevDisk: (r: UInt64, w: UInt64)?
    private var prevUptime: UInt64?
    private let totalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    private let pageSize = UInt64(getpagesize())

    func read(uptimeNs: UInt64) -> SystemSnapshot {
        let dt: Double? = prevUptime.flatMap { uptimeNs > $0 ? Double(uptimeNs - $0) / 1e9 : nil }
        defer { prevUptime = uptimeNs }

        var net: Throughput?
        if let cur = Self.networkBytes() {
            if let p = prevNet, let dt { net = Throughput(inBps: Double(Self.sub(cur.inB, p.inB)) / dt,
                                                         outBps: Double(Self.sub(cur.outB, p.outB)) / dt) }
            prevNet = cur
        }
        var disk: Throughput?
        if let cur = Self.diskBytes() {
            if let p = prevDisk, let dt { disk = Throughput(inBps: Double(Self.sub(cur.r, p.r)) / dt,
                                                           outBps: Double(Self.sub(cur.w, p.w)) / dt) }
            prevDisk = cur
        }
        return SystemSnapshot(date: Date(), cpu: readCPU(), memory: readMemory(), gpuUtilization: Self.gpuUtilization(),
                              network: net, disk: disk, storage: readStorage(uptimeNs), thermalState: ProcessInfo.processInfo.thermalState)
    }

    // MARK: Storage (startup volume, refreshed at most every 15 s)
    private var storageCache: (StorageUsage, UInt64)?
    private func readStorage(_ now: UInt64) -> StorageUsage? {
        if let (u, t) = storageCache, now - t < 15_000_000_000 { return u }
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity, let avail = v.volumeAvailableCapacityForImportantUsage else { return storageCache?.0 }
        let u = StorageUsage(totalBytes: UInt64(total), availableBytes: UInt64(max(0, avail)))
        storageCache = (u, now)
        return u
    }

    private static func sub(_ a: UInt64, _ b: UInt64) -> UInt64 { a >= b ? a - b : 0 }

    // MARK: CPU
    private func readCPU() -> CPUUsage? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        let stride = Int(CPU_STATE_MAX)
        var ticks = [UInt32](repeating: 0, count: Int(cpuCount) * stride)
        for i in 0..<ticks.count { ticks[i] = UInt32(bitPattern: info[i]) }
        defer { prevTicks = ticks }
        guard let prev = prevTicks, prev.count == ticks.count else { return nil }
        var user = 0.0, sys = 0.0, total = 0.0
        for c in 0..<Int(cpuCount) {
            for s in 0..<stride {
                let d = Double(ticks[c * stride + s] &- prev[c * stride + s])
                total += d
                if s == Int(CPU_STATE_USER) || s == Int(CPU_STATE_NICE) { user += d }
                if s == Int(CPU_STATE_SYSTEM) { sys += d }
            }
        }
        guard total > 0 else { return nil }
        return CPUUsage(user: user / total * 100, system: sys / total * 100, coreCount: Int(cpuCount))
    }

    // MARK: Memory
    private func readMemory() -> MemoryUsage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let ps = pageSize
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * ps
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        var level: Int32 = 1
        var lsz = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &lsz, nil, 0)
        return MemoryUsage(totalBytes: totalMemory, appBytes: app,
                           wiredBytes: UInt64(stats.wire_count) * ps,
                           compressedBytes: UInt64(stats.compressor_page_count) * ps,
                           cachedBytes: (UInt64(stats.external_page_count) + purgeable) * ps,
                           freeBytes: UInt64(stats.free_count) * ps,
                           swapUsedBytes: swap.xsu_used,
                           pressure: MemoryPressure(rawValue: Int(level)) ?? .normal)
    }

    // MARK: Network (64-bit interface counters)
    static func networkBytes() -> (inB: UInt64, outB: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, UInt32(mib.count), &buf, &len, nil, 0) == 0 else { return nil }
        var inB: UInt64 = 0, outB: UInt64 = 0
        buf.withUnsafeBytes { raw in
            var off = 0
            while off + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr.self)
                let msgLen = Int(hdr.ifm_msglen)
                if msgLen <= 0 { break }
                if Int32(hdr.ifm_type) == RTM_IFINFO2, off + MemoryLayout<if_msghdr2>.size <= len {
                    let h2 = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr2.self)
                    var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(h2.ifm_index), &nameBuf) != nil {
                        let name = String(cString: nameBuf)
                        // Physical links only: avoids double counting VPN/bridge/tunnel interfaces.
                        if name.hasPrefix("en") || name.hasPrefix("pdp_ip") {
                            inB &+= h2.ifm_data.ifi_ibytes
                            outB &+= h2.ifm_data.ifi_obytes
                        }
                    }
                }
                off += msgLen
            }
        }
        return (inB, outB)
    }

    // MARK: Disk (IOBlockStorageDriver statistics)
    static func diskBytes() -> (r: UInt64, w: UInt64)? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iter) }
        var r: UInt64 = 0, w: UInt64 = 0, found = false
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            if let d = IORegistryEntryCreateCFProperty(svc, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                r &+= (d["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                w &+= (d["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
                found = true
            }
            IOObjectRelease(svc)
            svc = IOIteratorNext(iter)
        }
        return found ? (r, w) : nil
    }

    // MARK: GPU (IOAccelerator PerformanceStatistics)
    static func gpuUtilization() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iter) }
        var best: Double?
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            if let d = IORegistryEntryCreateCFProperty(svc, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let v = (d["Device Utilization %"] as? NSNumber)?.doubleValue {
                best = max(best ?? 0, v)
            }
            IOObjectRelease(svc)
            svc = IOIteratorNext(iter)
        }
        return best
    }
}
