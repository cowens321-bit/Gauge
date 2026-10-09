import XCTest

final class ProtectionTests: XCTestCase {
    func testProtected() {
        XCTAssertNotNil(ProcessProtection.reasonProtected(pid: 1, uid: 0, path: "/sbin/launchd", bundleID: nil, currentUID: 501, selfPID: 99))
        XCTAssertNotNil(ProcessProtection.reasonProtected(pid: 300, uid: 0, path: "/usr/sbin/x", bundleID: nil, currentUID: 501, selfPID: 99))
        XCTAssertNotNil(ProcessProtection.reasonProtected(pid: 301, uid: 501, path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", bundleID: "com.apple.finder", currentUID: 501, selfPID: 99))
        XCTAssertNotNil(ProcessProtection.reasonProtected(pid: 99, uid: 501, path: "/x", bundleID: nil, currentUID: 501, selfPID: 99))
    }
    func testAllowed() {
        XCTAssertNil(ProcessProtection.reasonProtected(pid: 500, uid: 501, path: "/Applications/Foo.app/Contents/MacOS/Foo", bundleID: "com.foo", currentUID: 501, selfPID: 99))
        XCTAssertNil(ProcessProtection.reasonProtected(pid: 501, uid: 501, path: "/System/Applications/Calculator.app/Contents/MacOS/Calculator", bundleID: "com.apple.calculator", currentUID: 501, selfPID: 99))
    }
    func testPseudoGroupsCannotBeQuit() {
        let g = groupSnapshots([rec(5, path: "/usr/local/bin/x")]).first!
        XCTAssertNotNil(ProcessProtection.reasonProtected(group: g))
    }
}
