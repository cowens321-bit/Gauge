import XCTest
import Darwin

/// Exercises the real OS interfaces (no mocks): CPU workloads, process churn, restricted metrics.
final class LiveSystemTests: XCTestCase {
    func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    func wall() -> UInt64 { UInt64(Date().timeIntervalSince1970 * 1e6) }

    func testReadsOwnProcessWithMemory() {
        let me = LibprocSource().readProcesses().first { $0.pid == getpid() }
        XCTAssertNotNil(me)
        XCTAssertNotNil(me?.counters)
        XCTAssertGreaterThan(me?.counters?.footprintBytes ?? 0, 1_000_000)
        XCTAssertNotNil(me?.path)
    }

    func testMeasuresHighCPUWorkload() {
        let src = LibprocSource()
        var tracker = RateTracker()
        let stop = ManagedAtomicFlag()
        let threads = 2
        for _ in 0..<threads { Thread.detachNewThread { var x = 0.0; while !stop.isSet { for i in 0..<10_000 { x += sin(Double(i)) } ; if x == 42 { print(x) } } } }
        defer { stop.set() }
        _ = tracker.update(records: src.readProcesses(), uptimeNs: nowNs(), wallMicros: wall())
        Thread.sleep(forTimeInterval: 1.5)
        let rates = tracker.update(records: src.readProcesses(), uptimeNs: nowNs(), wallMicros: wall())
        let mine = rates.first { $0.key.pid == getpid() }?.value
        XCTAssertNotNil(mine)
        // Two busy threads ≈ 200% (plus test-runner overhead); allow generous tolerance.
        XCTAssertGreaterThan(mine?.cpuPercent ?? 0, 150)
        XCTAssertLessThan(mine?.cpuPercent ?? 0, 260)
    }

    func testChildProcessLifecycleAndRapidChurn() throws {
        let src = LibprocSource()
        var tracker = RateTracker()
        let child = Process(); child.executableURL = URL(fileURLWithPath: "/bin/sleep"); child.arguments = ["30"]
        try child.run()
        let pid = child.processIdentifier
        _ = tracker.update(records: src.readProcesses(), uptimeNs: nowNs(), wallMicros: wall())
        // churn: spawn and reap many short-lived processes while sampling
        for _ in 0..<15 {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/true"); try p.run()
            _ = src.readProcesses()
            p.waitUntilExit()
        }
        let live = src.readProcesses()
        XCTAssertTrue(live.contains { $0.pid == pid })
        child.terminate(); child.waitUntilExit()
        let after = src.readProcesses()
        XCTAssertFalse(after.contains { $0.pid == pid }, "terminated process must disappear")
        _ = tracker.update(records: after, uptimeNs: nowNs(), wallMicros: wall())
    }

    func testChildIsAttributedToThisProcessTree() throws {
        let src = LibprocSource()
        let child = Process(); child.executableURL = URL(fileURLWithPath: "/bin/sleep"); child.arguments = ["10"]
        try child.run(); defer { child.terminate() }
        let recs = src.readProcesses()
        let kid = try XCTUnwrap(recs.first { $0.pid == child.processIdentifier })
        XCTAssertEqual(kid.parentPID, getpid())
        if src.responsibilityAPIAvailable {
            XCTAssertNotNil(src.responsiblePID(of: kid.pid))
        }
    }

    func testSystemMetricsAreSaneAndAvailabilityIsExplicit() {
        let m = MachSystemMetrics()
        _ = m.read(uptimeNs: nowNs())
        Thread.sleep(forTimeInterval: 0.6)
        let s = m.read(uptimeNs: nowNs())
        let cpu = try? XCTUnwrap(s.cpu)
        XCTAssertGreaterThan(cpu?.total ?? -1, 0); XCTAssertLessThanOrEqual(cpu?.total ?? 101, 100)
        let mem = try? XCTUnwrap(s.memory)
        XCTAssertEqual(mem?.totalBytes, ProcessInfo.processInfo.physicalMemory)
        XCTAssertLessThan(mem?.usedBytes ?? .max, mem?.totalBytes ?? 0)
        XCTAssertNotNil(s.network); XCTAssertNotNil(s.disk)
    }

    func testSamplerEndToEndAndSamplingIntervalCost() async {
        let sampler = Sampler()
        let ctx = SamplingContext(regularAppPaths: [], includeProcesses: true, network: nil)
        await sampler.resetProcessBaseline()
        _ = await sampler.sample(ctx)
        try? await Task.sleep(for: .milliseconds(500))
        let s = await sampler.sample(ctx)
        XCTAssertTrue(s.hasProcessData)
        XCTAssertGreaterThan(s.groups.count, 3)
        XCTAssertLessThan(s.diagnostics.sampleDurationMs, 250, "one full sample should be cheap")
        // The group containing this test process must exist and have measured CPU.
        let mine = s.groups.first { $0.processes.contains { $0.pid == getpid() } }
        XCTAssertNotNil(mine?.cpuPercent)
        let sysOnly = await sampler.sample(SamplingContext(regularAppPaths: [], includeProcesses: false, network: nil))
        XCTAssertFalse(sysOnly.hasProcessData); XCTAssertTrue(sysOnly.groups.isEmpty)
    }

    func testSamplerWithFakesIsDeterministic() async {
        let recs = [rec(1, path: "/Applications/A.app/Contents/MacOS/a", cpuNs: 0)]
        let sampler = Sampler(source: FakeSource(records: recs), system: FakeSystem())
        let s = await sampler.sample(SamplingContext(regularAppPaths: [], includeProcesses: true, network: nil))
        XCTAssertEqual(s.groups.count, 1)
        XCTAssertNil(s.system.cpu); XCTAssertNil(s.system.gpuUtilization)  // unavailable stays unavailable
    }
}

final class ManagedAtomicFlag: @unchecked Sendable {
    private let l = NSLock(); private var v = false
    var isSet: Bool { l.lock(); defer { l.unlock() }; return v }
    func set() { l.lock(); v = true; l.unlock() }
}

final class FormatterTests: XCTestCase {
    func testFormatters() {
        XCTAssertEqual(Fmt.power(1500), "1.50 W"); XCTAssertEqual(Fmt.power(80), "80 mW")
        XCTAssertEqual(Fmt.compactRate(1_500_000), "1.5M"); XCTAssertEqual(Fmt.compactRate(500), "500B")
        XCTAssertTrue(Fmt.bytes(1_073_741_824, .binary).contains("1"))
        XCTAssertEqual(Fmt.percent(12.34), "12.3%")
    }
}

final class NettopTests: XCTestCase {
    func testNettopSourceProducesPerPidRates() {
        let n = NettopNetworkSource()
        n.start(interval: 1)
        defer { n.stop() }
        // generate some loopback-independent traffic via a DNS lookup + local socket work
        let end = Date().addingTimeInterval(6)
        while Date() < end && n.currentRates().isEmpty { Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertFalse(n.currentRates().isEmpty, "nettop should yield per-pid rates after the first delta block")
        n.stop()
        XCTAssertTrue(n.currentRates().isEmpty, "stopping clears state")
        XCTAssertFalse(n.isRunning)
    }
}
