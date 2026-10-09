import XCTest

final class AttributionTests: XCTestCase {
    let chrome = "/Applications/Google Chrome.app"
    var chromeExe: String { chrome + "/Contents/MacOS/Google Chrome" }
    var chromeHelper: String { chrome + "/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)" }

    func testChromeHelpersFoldIntoOneEntry() {
        let regular: Set<String> = [chrome]
        var recs = [rec(100, path: chromeExe, mem: 300)]
        for i in 0..<6 { recs.append(rec(Int32(101 + i), ppid: 100, path: chromeHelper, mem: 100)) }
        recs.append(rec(200, path: "/usr/bin/other", mem: 5))
        let groups = groupSnapshots(recs, regular: regular)
        let g = groups.first { $0.bundlePath == chrome }!
        XCTAssertEqual(g.processCount, 7)
        XCTAssertEqual(g.memoryBytes, 900)
        XCTAssertEqual(g.name, "Google Chrome")
        XCTAssertEqual(g.rootPID, 100)
        XCTAssertEqual(groups.filter { $0.kind == .application }.count, 1)
    }

    func testHelperAppsNotRegularStillFoldWithoutRunningInfo() {
        let recs = [rec(1, path: chromeExe), rec(2, path: chromeHelper)]
        XCTAssertEqual(groupSnapshots(recs).filter { $0.kind == .application }.count, 1)
    }

    func testSafariWebContentViaResponsibleProcess() {
        let safari = "/System/Cryptexes/App/System/Applications/Safari.app"
        let recs = [rec(10, path: safari + "/Contents/MacOS/Safari"),
                    rec(11, ppid: 1, path: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"),
                    rec(12, ppid: 1, path: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.Networking.xpc/Contents/MacOS/com.apple.WebKit.Networking")]
        let attrs = engine.attribute(recs, context: AttributionContext(regularAppPaths: [safari], responsible: [11: 10, 12: 10]))
        XCTAssertEqual(attrs[recs[1].id]?.reason, .responsibleProcess)
        XCTAssertEqual(attrs[recs[1].id]?.key.value, safari)
        let groups = groupSnapshots(recs, responsible: [11: 10, 12: 10], regular: [safari])
        XCTAssertEqual(groups.first { $0.bundlePath == safari }?.processCount, 3)
    }

    func testWithoutResponsibleInfoWebKitIsNotGuessedFromName() {
        let recs = [rec(10, path: "/Applications/Safari.app/Contents/MacOS/Safari"),
                    rec(11, ppid: 1, path: "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent")]
        let a = engine.attribute(recs, context: AttributionContext())
        XCTAssertEqual(a[recs[1].id]?.reason, .unattributed)
    }

    func testTerminalChildrenViaResponsible() {
        let term = "/System/Applications/Utilities/Terminal.app"
        let recs = [rec(5, path: term + "/Contents/MacOS/Terminal"),
                    rec(6, ppid: 5, path: "/bin/zsh"), rec(7, ppid: 6, path: "/usr/bin/yes"), rec(8, ppid: 6, path: "/usr/local/bin/node")]
        let groups = groupSnapshots(recs, responsible: [6: 5, 7: 5, 8: 5])
        let t = groups.first { $0.bundlePath == term }!
        XCTAssertEqual(t.processCount, 4)
        XCTAssertEqual(t.inferredCount, 0)
    }

    func testAncestryIsFlaggedAsInferred() {
        let recs = [rec(5, path: "/Applications/Foo.app/Contents/MacOS/Foo"),
                    rec(6, ppid: 5, path: "/bin/sh"), rec(7, ppid: 6, path: "/usr/bin/make")]
        let groups = groupSnapshots(recs)
        let g = groups.first { $0.bundlePath == "/Applications/Foo.app" }!
        XCTAssertEqual(g.processCount, 3)
        XCTAssertEqual(g.inferredCount, 2)
    }

    func testXcodeAndNestedInstrumentsAreSeparateWhenInstrumentsIsRegular() {
        let xcode = "/Applications/Xcode.app"
        let instr = xcode + "/Contents/Applications/Instruments.app"
        let recs = [rec(1, path: xcode + "/Contents/MacOS/Xcode"),
                    rec(2, path: xcode + "/Contents/SharedFrameworks/XCBuildService.xpc/Contents/MacOS/XCBuildService"),
                    rec(3, path: instr + "/Contents/MacOS/Instruments")]
        let groups = groupSnapshots(recs, regular: [xcode, instr])
        XCTAssertEqual(groups.first { $0.bundlePath == xcode }?.processCount, 2)
        XCTAssertEqual(groups.first { $0.bundlePath == instr }?.processCount, 1)
    }

    func testXcodeBuildToolsViaResponsibleAndSimulatorApps() {
        let xcode = "/Applications/Xcode.app"
        let recs = [rec(100, path: xcode + "/Contents/MacOS/Xcode"),
                    rec(101, ppid: 100, path: "/usr/bin/clang"),
                    rec(102, ppid: 100, path: "/Library/Developer/CoreSimulator/Volumes/iOS_1/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/Applications/MobileSafari.app/MobileSafari")]
        let groups = groupSnapshots(recs, responsible: [101: 100, 102: 100], regular: [xcode])
        XCTAssertEqual(groups.first { $0.bundlePath == xcode }?.processCount, 3)
        XCTAssertNil(groups.first { $0.name == "MobileSafari" })
    }

    func testDockerStyleVMAndContainersInsideBundle() {
        let d = "/Applications/Docker.app"
        let recs = [rec(1, path: d + "/Contents/MacOS/com.docker.backend"),
                    rec(2, path: d + "/Contents/MacOS/com.docker.virtualization", mem: 4_000),
                    rec(3, path: d + "/Contents/Resources/bin/docker-proxy")]
        XCTAssertEqual(groupSnapshots(recs).first { $0.bundlePath == d }?.processCount, 3)
    }

    func testUnattributedGoToPseudoGroupsAndRootSeparated() {
        let recs = [rec(1, uid: 0, path: "/usr/sbin/mDNSResponder"), rec(2, uid: 501, path: "/usr/local/bin/redis"),
                    rec(3, uid: 0, path: nil)]
        let groups = groupSnapshots(recs)
        XCTAssertEqual(groups.first { $0.kind == .systemServices }?.processCount, 2)
        XCTAssertEqual(groups.first { $0.kind == .backgroundServices }?.processCount, 1)
        XCTAssertTrue(groups.allSatisfy { $0.processes.allSatisfy { $0.reason == .unattributed } })
    }

    func testAppleServicesAreSeparatedFromThirdPartyBackgroundProcesses() {
        let recs = [rec(1, path: "/System/Library/PrivateFrameworks/X.framework/XPCServices/com.apple.foo.xpc/Contents/MacOS/foo"),
                    rec(2, path: "/usr/local/bin/redis-server"), rec(3, path: "/opt/homebrew/bin/postgres")]
        let g = groupSnapshots(recs)
        XCTAssertEqual(g.first { $0.kind == .macOSServices }?.processCount, 1)
        XCTAssertEqual(g.first { $0.kind == .backgroundServices }?.processCount, 2)
    }

    func testSameExecutableNameInDifferentAppsNotMerged() {
        let recs = [rec(1, path: "/Applications/A.app/Contents/MacOS/helper"), rec(2, path: "/Applications/B.app/Contents/MacOS/helper")]
        XCTAssertEqual(groupSnapshots(recs).filter { $0.kind == .application }.count, 2)
    }

    func testResponsibleLoopsDoNotHang() {
        let recs = [rec(1, path: "/bin/a"), rec(2, path: "/bin/b")]
        let a = engine.attribute(recs, context: AttributionContext(responsible: [1: 2, 2: 1]))
        XCTAssertEqual(a.count, 2)
    }

    func testAppRelaunchMergesByBundlePathAcrossPIDs() {
        let exe = "/Applications/Foo.app/Contents/MacOS/Foo"
        let first = groupSnapshots([rec(10, start: 1, path: exe)])
        let second = groupSnapshots([rec(99, start: 9, path: exe)])
        XCTAssertEqual(first.first?.key, second.first?.key)
    }

    func testBundleCandidateParsing() {
        XCTAssertEqual(AttributionEngine.appBundleCandidates(in: "/a/B.app/Contents/X.app/Contents/MacOS/x"), ["/a/B.app", "/a/B.app/Contents/X.app"])
        XCTAssertEqual(AttributionEngine.appBundleCandidates(in: "/usr/bin/ls"), [])
        XCTAssertEqual(AttributionEngine.appBundleCandidates(in: "/a/.app/x"), [])
    }
}
