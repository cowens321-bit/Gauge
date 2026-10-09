import XCTest

final class AggregationTests: XCTestCase {
    let exe = "/Applications/Foo.app/Contents/MacOS/Foo"

    func testMemoryAndCPUAggregation() {
        let recs = [rec(1, path: exe, mem: 100), rec(2, ppid: 1, path: exe + "x", mem: 250)]
        let rates = [recs[0].id: ProcessRates(cpuPercent: 10, diskReadBps: 1, diskWriteBps: 2, powerMilliwatts: 5),
                     recs[1].id: ProcessRates(cpuPercent: 35, diskReadBps: 3, diskWriteBps: 4, powerMilliwatts: 7)]
        let g = groupSnapshots(recs, rates: rates)[0]
        XCTAssertEqual(g.memoryBytes, 350)
        XCTAssertEqual(g.cpuPercent!, 45, accuracy: 1e-9)
        XCTAssertEqual(g.diskReadBps!, 4, accuracy: 1e-9)
        XCTAssertEqual(g.powerMilliwatts!, 12, accuracy: 1e-9)
    }

    func testRestrictedProcessesAreExcludedNotZeroed() {
        let recs = [rec(1, path: exe, mem: 100), rec(2, ppid: 1, path: exe + "h", cpuNs: nil)]
        let g = groupSnapshots(recs)[0]
        XCTAssertEqual(g.unreadableCount, 1)
        XCTAssertEqual(g.memoryBytes, 100)
        XCTAssertNil(g.cpuPercent, "no rates yet -> unknown, not 0")
    }

    func testAllRestrictedMeansUnavailable() {
        let g = groupSnapshots([rec(1, uid: 0, path: nil, cpuNs: nil)])[0]
        XCTAssertNil(g.memoryBytes); XCTAssertNil(g.cpuPercent)
    }

    func testNetworkNilWhenSourceOff() {
        XCTAssertNil(groupSnapshots([rec(1, path: exe)])[0].netInBps)
    }

    func testNetworkAggregatesByPid() {
        let recs = [rec(1, path: exe), rec(2, ppid: 1, path: exe)]
        let a = engine.attribute(recs, context: AttributionContext())
        let g = GroupAggregator.build(records: recs, attributions: a, rates: [:],
                                      network: [1: NetRate(inBps: 10, outBps: 1), 2: NetRate(inBps: 5, outBps: 2)], regularAppPaths: [])[0]
        XCTAssertEqual(g.netInBps, 15); XCTAssertEqual(g.netOutBps, 3)
    }

    func testTimeSeriesTrimsAndSegments() {
        var s = TimeSeries<GroupPoint>()
        let t0 = Date(timeIntervalSince1970: 0)
        for i in 0..<10 { s.append(GroupPoint(t: t0.addingTimeInterval(Double(i)), cpu: 1, mem: 1, disk: nil, net: nil), keeping: 4.5) }
        XCTAssertEqual(s.count, 5)
        XCTAssertEqual(s.visible.first?.t, t0.addingTimeInterval(5))
        let seg = TimeSeries<GroupPoint>.segmentIndices([GroupPoint(t: t0, cpu: 1, mem: 1, disk: nil, net: nil),
                                                         GroupPoint(t: t0.addingTimeInterval(1), cpu: 1, mem: 1, disk: nil, net: nil),
                                                         GroupPoint(t: t0.addingTimeInterval(60), cpu: 1, mem: 1, disk: nil, net: nil)], gap: 5)
        XCTAssertEqual(seg, [0, 0, 1])
    }

    func testDownsamplingKeepsNewest() {
        var s = TimeSeries<GroupPoint>()
        for i in 0..<1000 { s.append(GroupPoint(t: Date(timeIntervalSince1970: Double(i)), cpu: Double(i), mem: nil, disk: nil, net: nil), keeping: 10_000) }
        let d = s.downsampled(maxPoints: 100)
        XCTAssertEqual(d.count, 100); XCTAssertEqual(d.last?.cpu, 999); XCTAssertEqual(d.first?.cpu, 0)
    }

    func testChartSeriesBreaksOnMissingAndGaps() {
        let t0 = Date(timeIntervalSince1970: 0)
        let s = ChartSeries.make("x", color: .red, gap: 5, [(t0, 1), (t0.addingTimeInterval(1), nil), (t0.addingTimeInterval(2), 3), (t0.addingTimeInterval(30), 4)])
        XCTAssertEqual(s.points.map(\.seg), [0, 1, 2])
    }
}

final class FilterSortTests: XCTestCase {
    func make() -> [GroupSnapshot] {
        let recs = [rec(1, path: "/Applications/Alpha.app/Contents/MacOS/a", mem: 300),
                    rec(2, path: "/Applications/Beta.app/Contents/MacOS/b", mem: 100),
                    rec(3, path: "/Applications/Gamma.app/Contents/MacOS/g", mem: 200),
                    rec(4, ppid: 3, path: "/Applications/Gamma.app/Contents/MacOS/gh", mem: 200),
                    rec(5, uid: 0, name: "daemon", path: "/usr/sbin/daemon"), rec(6, path: "/System/Applications/Calculator.app/Contents/MacOS/Calc")]
        let rates = Dictionary(uniqueKeysWithValues: recs.enumerated().map {
            ($1.id, ProcessRates(cpuPercent: Double(10 - $0), diskReadBps: 0, diskWriteBps: 0, powerMilliwatts: Double($0))) })
        return groupSnapshots(recs, rates: rates)
    }

    func testScopes() {
        let g = make()
        XCTAssertEqual(AppFilter.apply(g, scope: .userApps, query: "").count, 3)
        XCTAssertEqual(AppFilter.apply(g, scope: .allApps, query: "").count, 4)
        XCTAssertEqual(AppFilter.apply(g, scope: .everything, query: "").count, 5)
    }

    func testSearchByNameBundleIDPIDAndProcess() {
        let g = make()
        XCTAssertEqual(AppFilter.apply(g, scope: .everything, query: "alph").map(\.name), ["Alpha"])
        XCTAssertEqual(AppFilter.apply(g, scope: .everything, query: "test.beta").map(\.name), ["Beta"])
        XCTAssertEqual(AppFilter.apply(g, scope: .everything, query: "4").map(\.name), ["Gamma"])
        XCTAssertEqual(AppFilter.apply(g, scope: .everything, query: "daemon").first?.kind == .systemServices, true)
        XCTAssertTrue(AppFilter.apply(g, scope: .everything, query: "zzz").isEmpty)
    }

    func testSorting() {
        let g = AppFilter.apply(make(), scope: .userApps, query: "")
        XCTAssertEqual(g.sorted(using: AppFilter.comparators(for: .memory)).map(\.name), ["Gamma", "Alpha", "Beta"].sorted { a, b in
            let m: [String: Int] = ["Alpha": 300, "Beta": 100, "Gamma": 400]; return m[a]! > m[b]! })
        XCTAssertEqual(g.sorted(using: AppFilter.comparators(for: .name)).map(\.name), ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(g.sorted(using: AppFilter.comparators(for: .processes)).first?.name, "Gamma")
        XCTAssertEqual(g.sorted(using: AppFilter.comparators(for: .cpu)).first?.name, "Gamma")  // 8% + 7% across two processes
    }

    func testMissingMetricsSortLast() {
        var g = make()
        g.append(GroupSnapshot(key: GroupKey(value: "/x/Nil.app"), kind: .application, name: "Nil", bundleID: nil, bundlePath: "/x/Nil.app",
                               isRegularApp: true, processes: [], hasNetwork: false))
        XCTAssertEqual(g.sorted(using: AppFilter.comparators(for: .cpu)).last?.name, "Nil")
    }

    func testSeverity() {
        XCTAssertEqual(Severity.cpu(20, cores: 10), .normal)
        XCTAssertEqual(Severity.cpu(150, cores: 10), .elevated)
        XCTAssertEqual(Severity.cpu(600, cores: 10), .high)
        XCTAssertEqual(Severity.memory(9, total: 100), .normal)
        XCTAssertEqual(Severity.memory(30, total: 100), .high)
    }
}
