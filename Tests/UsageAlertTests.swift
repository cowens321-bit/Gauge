import XCTest

final class UsageAlertTests: XCTestCase {
    let total: UInt64 = 32 << 30
    func group(_ id: String, cpu: Double?, mem: UInt64 = 100 << 20, kind: GroupKind = .application) -> GroupSnapshot {
        let p = ProcessSnapshot(id: ProcessIdentity(pid: 1, startTimeMicros: 1), parentPID: 1, uid: 501, name: id, path: nil,
                                memoryBytes: mem, rates: cpu.map { ProcessRates(cpuPercent: $0, diskReadBps: 0, diskWriteBps: 0, powerMilliwatts: 0) },
                                reason: .bundlePath, net: nil)
        return GroupSnapshot(key: GroupKey(value: id), kind: kind, name: id, bundleID: nil, bundlePath: "/Applications/\(id).app",
                             isRegularApp: true, processes: [p], hasNetwork: false)
    }
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testFiresOnlyAfterSustainedHighCPU() {
        var t = UsageAlertTracker()
        for s in stride(from: 0.0, to: 120, by: 10) {
            XCTAssertTrue(t.update(groups: [group("Busy", cpu: 150)], totalMemory: total, now: t0 + s).isEmpty, "not yet at \(s)s")
        }
        let a = t.update(groups: [group("Busy", cpu: 150)], totalMemory: total, now: t0 + 120)
        XCTAssertEqual(a.map(\.kind), [.cpu]); XCTAssertEqual(a.first?.name, "Busy")
    }

    func testDipResetsTheStreak() {
        var t = UsageAlertTracker()
        _ = t.update(groups: [group("A", cpu: 150)], totalMemory: total, now: t0)
        _ = t.update(groups: [group("A", cpu: 10)], totalMemory: total, now: t0 + 60)
        XCTAssertTrue(t.update(groups: [group("A", cpu: 150)], totalMemory: total, now: t0 + 130).isEmpty)
        XCTAssertFalse(t.update(groups: [group("A", cpu: 150)], totalMemory: total, now: t0 + 250).isEmpty)
    }

    func testCooldownPreventsRepeats() {
        var t = UsageAlertTracker()
        _ = t.update(groups: [group("A", cpu: 200)], totalMemory: total, now: t0)
        XCTAssertEqual(t.update(groups: [group("A", cpu: 200)], totalMemory: total, now: t0 + 120).count, 1)
        XCTAssertTrue(t.update(groups: [group("A", cpu: 200)], totalMemory: total, now: t0 + 600).isEmpty)
        XCTAssertEqual(t.update(groups: [group("A", cpu: 200)], totalMemory: total, now: t0 + 120 + 1800).count, 1)
    }

    func testMemoryAlert() {
        var t = UsageAlertTracker()
        let big = group("Hog", cpu: 1, mem: 10 << 30)   // 10 GB of 32 GB
        _ = t.update(groups: [big], totalMemory: total, now: t0)
        XCTAssertEqual(t.update(groups: [big], totalMemory: total, now: t0 + 120).map(\.kind), [.memory])
    }

    func testIgnoresBackgroundServicesAndUnknownCPU() {
        var t = UsageAlertTracker()
        let svc = group("pseudo", cpu: 500, kind: .systemServices)
        let unknown = group("NoRates", cpu: nil)
        _ = t.update(groups: [svc, unknown], totalMemory: total, now: t0)
        XCTAssertTrue(t.update(groups: [svc, unknown], totalMemory: total, now: t0 + 300).isEmpty)
    }

    func testQuitAppForgetsStreak() {
        var t = UsageAlertTracker()
        _ = t.update(groups: [group("A", cpu: 200)], totalMemory: total, now: t0)
        _ = t.update(groups: [], totalMemory: total, now: t0 + 60)
        XCTAssertTrue(t.update(groups: [group("A", cpu: 200)], totalMemory: total, now: t0 + 130).isEmpty)
    }
}
