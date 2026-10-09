import XCTest

final class RateTrackerTests: XCTestCase {
    let sec: UInt64 = 1_000_000_000

    func testCPUDeltaOneCoreIs100Percent() {
        var t = RateTracker()
        _ = t.update(records: [rec(10, cpuNs: 0)], uptimeNs: 10 * sec, wallMicros: 100_000_000)
        let r = t.update(records: [rec(10, cpuNs: 2 * sec)], uptimeNs: 12 * sec, wallMicros: 102_000_000)
        XCTAssertEqual(r[ProcessIdentity(pid: 10, startTimeMicros: 1_000_000)]!.cpuPercent, 100, accuracy: 0.001)
    }

    func testMultiCoreExceeds100() {
        var t = RateTracker()
        _ = t.update(records: [rec(10, cpuNs: 0)], uptimeNs: 0, wallMicros: 5_000_000)
        let r = t.update(records: [rec(10, cpuNs: 6 * sec)], uptimeNs: 2 * sec, wallMicros: 7_000_000)
        XCTAssertEqual(r.values.first!.cpuPercent, 300, accuracy: 0.001)
    }

    func testFirstSampleHasNoRates() {
        var t = RateTracker()
        XCTAssertTrue(t.update(records: [rec(1, cpuNs: 5 * sec)], uptimeNs: sec, wallMicros: 10_000_000).isEmpty)
    }

    func testPIDReuseDoesNotInheritOldCounters() {
        var t = RateTracker()
        _ = t.update(records: [rec(50, start: 1_000_000, cpuNs: 100 * sec)], uptimeNs: 0, wallMicros: 5_000_000)
        // Same pid, later start time, tiny CPU: must NOT be diffed against the 100 s of the old process.
        let new = rec(50, start: 6_000_000, cpuNs: sec / 2)
        let r = t.update(records: [new], uptimeNs: 2 * sec, wallMicros: 7_000_000)
        XCTAssertEqual(r[new.id]!.cpuPercent, 25, accuracy: 0.001)   // 0.5 s over 2 s, counted from zero
    }

    func testUnknownOldProcessGetsNoRate() {
        var t = RateTracker()
        _ = t.update(records: [rec(1, cpuNs: 0)], uptimeNs: 0, wallMicros: 5_000_000)
        // pid 2 started long before the previous sample but was never seen -> no baseline
        let r = t.update(records: [rec(1, cpuNs: 0), rec(2, start: 1_000, cpuNs: 9 * sec)], uptimeNs: sec, wallMicros: 6_000_000)
        XCTAssertNil(r[ProcessIdentity(pid: 2, startTimeMicros: 1_000)])
    }

    func testShortLivedProcessBornBetweenSamples() {
        var t = RateTracker()
        _ = t.update(records: [rec(1, cpuNs: 0)], uptimeNs: 0, wallMicros: 5_000_000)
        let born = rec(77, start: 5_500_000, cpuNs: sec)
        let r = t.update(records: [rec(1, cpuNs: 0), born], uptimeNs: 2 * sec, wallMicros: 7_000_000)
        XCTAssertEqual(r[born.id]!.cpuPercent, 50, accuracy: 0.001)
    }

    func testTerminatedProcessIsPruned() {
        var t = RateTracker()
        _ = t.update(records: [rec(1, cpuNs: 0), rec(2, cpuNs: 0)], uptimeNs: 0, wallMicros: 5_000_000)
        let r = t.update(records: [rec(1, cpuNs: sec)], uptimeNs: sec, wallMicros: 6_000_000)
        XCTAssertNotNil(r[ProcessIdentity(pid: 1, startTimeMicros: 1_000_000)])
        XCTAssertNil(r[ProcessIdentity(pid: 2, startTimeMicros: 1_000_000)])
        // pid 2 reappears with the same identity later (impossible in practice) -> needs fresh baseline
        let r3 = t.update(records: [rec(1, cpuNs: sec), rec(2, cpuNs: 5 * sec)], uptimeNs: 2 * sec, wallMicros: 7_000_000)
        XCTAssertNil(r3[ProcessIdentity(pid: 2, startTimeMicros: 1_000_000)])
    }

    func testRestrictedProcessYieldsNilNotZero() {
        var t = RateTracker()
        let locked = rec(9, cpuNs: nil)
        _ = t.update(records: [locked], uptimeNs: 0, wallMicros: 5_000_000)
        let r = t.update(records: [locked], uptimeNs: sec, wallMicros: 6_000_000)
        XCTAssertNil(r[locked.id])
    }

    func testCounterGoingBackwardsIsIgnored() {
        var t = RateTracker()
        _ = t.update(records: [rec(1, cpuNs: 10 * sec)], uptimeNs: 0, wallMicros: 5_000_000)
        XCTAssertTrue(t.update(records: [rec(1, cpuNs: 5 * sec)], uptimeNs: sec, wallMicros: 6_000_000).isEmpty)
    }

    func testNonAdvancingClockIsSafe() {
        var t = RateTracker()
        _ = t.update(records: [rec(1, cpuNs: 0)], uptimeNs: 5 * sec, wallMicros: 5_000_000)
        XCTAssertTrue(t.update(records: [rec(1, cpuNs: sec)], uptimeNs: 5 * sec, wallMicros: 5_000_000).isEmpty)
    }

    func testDiskAndEnergyRates() {
        var t = RateTracker()
        _ = t.update(records: [rec(1, cpuNs: 0, read: 0, write: 0, energy: 0)], uptimeNs: 0, wallMicros: 5_000_000)
        let r = t.update(records: [rec(1, cpuNs: 0, read: 4_000_000, write: 2_000_000, energy: 2_000_000_000)], uptimeNs: 2 * sec, wallMicros: 7_000_000)
        let v = r.values.first!
        XCTAssertEqual(v.diskReadBps, 2_000_000, accuracy: 0.1)
        XCTAssertEqual(v.diskWriteBps, 1_000_000, accuracy: 0.1)
        XCTAssertEqual(v.powerMilliwatts, 1000, accuracy: 0.01)   // 2 J over 2 s = 1 W
    }

    func testNormalization() {
        XCTAssertEqual(Fmt.cpu(300, cores: 10, .perCore), 300)
        XCTAssertEqual(Fmt.cpu(300, cores: 10, .machine), 30)
    }
}
