import Foundation
import Darwin

/// Abstraction over the OS so monitoring logic can be tested with fakes.
protocol ProcessSource: Sendable {
    func readProcesses() -> [ProcessRecord]
    /// macOS "responsible process" for `pid`, or nil if unavailable.
    func responsiblePID(of pid: Int32) -> Int32?
    var responsibilityAPIAvailable: Bool { get }
}

/// Real implementation on top of libproc. Uses only public APIs except for the optional
/// `responsibility_get_pid_responsible_for_pid` symbol, which is resolved at runtime with `dlsym`
/// and silently skipped if absent (grouping then falls back to bundle path + ancestry).
final class LibprocSource: ProcessSource, @unchecked Sendable {
    private struct StaticInfo { var name: String; var path: String? }
    private var cache: [ProcessIdentity: StaticInfo] = [:]
    private let lock = NSLock()
    private let timebase: (numer: UInt64, denom: UInt64)

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private let responsibleFn: ResponsibleFn?

    init() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        timebase = (UInt64(tb.numer), UInt64(max(tb.denom, 1)))
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, "responsibility_get_pid_responsible_for_pid") {
            responsibleFn = unsafeBitCast(sym, to: ResponsibleFn.self)
        } else {
            responsibleFn = nil
        }
    }

    var responsibilityAPIAvailable: Bool { responsibleFn != nil }

    func responsiblePID(of pid: Int32) -> Int32? {
        guard let fn = responsibleFn else { return nil }
        let r = fn(pid)
        return r > 0 ? r : nil
    }

    func readProcesses() -> [ProcessRecord] {
        let size = MemoryLayout<pid_t>.size
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(needed) / size + 64)
        let got = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * size))
        guard got > 0 else { return [] }
        let n = Int(got) / size

        var out: [ProcessRecord] = []
        out.reserveCapacity(n)
        var live = Set<ProcessIdentity>()
        lock.lock(); defer { lock.unlock() }
        for i in 0..<n {
            let pid = pids[i]
            if pid <= 0 { continue }
            var bsd = proc_bsdinfo()
            let bsz = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsz) == bsz else { continue }
            let id = ProcessIdentity(pid: pid,
                                     startTimeMicros: bsd.pbi_start_tvsec * 1_000_000 + bsd.pbi_start_tvusec)
            live.insert(id)
            let info: StaticInfo
            if let c = cache[id] { info = c } else {
                let name = withUnsafeBytes(of: &bsd.pbi_name) { b -> String in
                    let s = String(cString: b.bindMemory(to: CChar.self).baseAddress!)
                    return s.isEmpty ? withUnsafeBytes(of: &bsd.pbi_comm) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) } : s
                }
                var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
                let len = proc_pidpath(pid, &buf, UInt32(buf.count))
                let path = len > 0 ? String(cString: buf) : nil
                info = StaticInfo(name: name, path: path)
                cache[id] = info
            }
            out.append(ProcessRecord(id: id, parentPID: Int32(bsd.pbi_ppid), uid: bsd.pbi_uid,
                                     name: info.name, path: info.path, counters: counters(for: pid)))
        }
        if cache.count > live.count + 64 { cache = cache.filter { live.contains($0.key) } }
        return out
    }

    private func counters(for pid: pid_t) -> ProcessCounters? {
        var ru = rusage_info_v6()
        let rc = withUnsafeMutablePointer(to: &ru) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        guard rc == 0 else { return nil }
        let ticks = ru.ri_user_time &+ ru.ri_system_time
        return ProcessCounters(cpuTimeNs: ticks &* timebase.numer / timebase.denom,
                               footprintBytes: ru.ri_phys_footprint,
                               diskReadBytes: ru.ri_diskio_bytesread,
                               diskWriteBytes: ru.ri_diskio_byteswritten,
                               billedEnergyNJ: ru.ri_billed_energy)
    }
}
