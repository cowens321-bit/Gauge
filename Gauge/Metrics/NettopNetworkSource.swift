import Foundation
import Darwin

protocol NetworkRateSource: Sendable {
    /// Latest per-pid network rates (bytes/second), empty until the first interval completes.
    func currentRates() -> [Int32: NetRate]
}

/// Per-app network attribution via Apple's `nettop` tool. macOS exposes no public per-process
/// network counters, so this is an opt-in fallback: it spawns `nettop` (which has a measurable CPU
/// cost) and parses its delta output. It is torn down as soon as the setting is turned off.
final class NettopNetworkSource: NetworkRateSource, @unchecked Sendable {
    private var process: Process?
    private let lock = NSLock()
    private var latest: [Int32: NetRate] = [:]
    private var building: [Int32: NetRate] = [:]
    private var blocksSeen = 0
    private var buffer = Data()
    private var interval: Double = 2

    func start(interval: Double) {
        stop()
        self.interval = max(1, interval.rounded())
        let p = Process()
        // nettop block-buffers when stdout is a pipe (no data for minutes); `script` gives it a pty so it
        // flushes every sample.
        p.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        p.arguments = ["-q", "/dev/null", "/usr/bin/nettop", "-P", "-d", "-L", "1000000", "-s", "\(Int(self.interval))",
                       "-x", "-J", "bytes_in,bytes_out"]
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            self?.consume(d)
        }
        do { try p.run(); process = p } catch { process = nil }
    }

    func stop() {
        process?.standardOutput.flatMap { ($0 as? Pipe)?.fileHandleForReading.readabilityHandler = nil }
        if let p = process, p.isRunning {
            // Terminate the nettop child as well, otherwise it would be orphaned.
            var kids = [pid_t](repeating: 0, count: 8)
            let n = proc_listchildpids(p.processIdentifier, &kids, Int32(kids.count * MemoryLayout<pid_t>.size))
            for k in kids.prefix(max(0, Int(n))) where k > 0 { kill(k, SIGTERM) }
            p.terminate()
        }
        process = nil
        lock.lock(); latest = [:]; building = [:]; blocksSeen = 0; buffer = Data(); lock.unlock()
    }

    var isRunning: Bool { process?.isRunning == true }

    func currentRates() -> [Int32: NetRate] {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    private func consume(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            handle(line: line)
        }
    }

    /// Format: header `,bytes_in,bytes_out,` starts a block; rows are `name.pid,in,out,`.
    private func handle(line: String) {
        if line.contains(",bytes_in") {
            // Block boundary: publish the previous block (the very first one is cumulative, so skip it).
            if blocksSeen > 1 {
                latest = building.mapValues { NetRate(inBps: $0.inBps / interval, outBps: $0.outBps / interval) }
            }
            blocksSeen += 1
            building = [:]
            return
        }
        let parts = line.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 3, let dot = parts[0].lastIndex(of: "."),
              let pid = Int32(parts[0][parts[0].index(after: dot)...]),
              let inB = Double(parts[1]), let outB = Double(parts[2]) else { return }
        building[pid] = NetRate(inBps: inB, outBps: outB)
    }
}
