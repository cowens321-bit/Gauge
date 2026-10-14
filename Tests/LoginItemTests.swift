import XCTest
import ServiceManagement

final class LoginItemTests: XCTestCase {
    var d: UserDefaults!
    var registered = 0, unregistered = 0
    var status: SMAppService.Status = .notRegistered
    let saved = LoginItem.hooks

    override func setUp() {
        d = UserDefaults(suiteName: "gauge.test.login.\(UUID().uuidString)")!
        d.register(defaults: [Pref.launchAtLogin: true])
        registered = 0; unregistered = 0; status = .notRegistered
        LoginItem.hooks = .init(status: { [unowned self] in status },
                                register: { [unowned self] in registered += 1; status = .enabled },
                                unregister: { [unowned self] in unregistered += 1; status = .notRegistered })
    }
    override func tearDown() { LoginItem.hooks = saved }

    func testOnByDefaultOnFirstRunFromApplications() {
        XCTAssertTrue(LoginItem.applyDefaultIfNeeded(defaults: d, bundlePath: "/Applications/Gauge.app"))
        XCTAssertEqual(registered, 1)
        XCTAssertTrue(LoginItem.isEnabled)
    }

    func testAppliedOnlyOnce() {
        LoginItem.applyDefaultIfNeeded(defaults: d, bundlePath: "/Applications/Gauge.app")
        status = .notRegistered   // e.g. removed in System Settings
        XCTAssertFalse(LoginItem.applyDefaultIfNeeded(defaults: d, bundlePath: "/Applications/Gauge.app"))
        XCTAssertEqual(registered, 1)
    }

    func testUserOptOutIsRespectedForever() throws {
        LoginItem.applyDefaultIfNeeded(defaults: d, bundlePath: "/Applications/Gauge.app")
        try LoginItem.set(false, defaults: d)
        XCTAssertEqual(unregistered, 1); XCTAssertFalse(LoginItem.isEnabled)
        for _ in 0..<3 { LoginItem.applyDefaultIfNeeded(defaults: d, bundlePath: "/Applications/Gauge.app") }
        XCTAssertEqual(registered, 1, "never re-enabled after the user turned it off")
    }

    func testUserChoiceBeforeFirstDefaultWins() throws {
        try LoginItem.set(false, defaults: d)
        XCTAssertFalse(LoginItem.applyDefaultIfNeeded(defaults: d, bundlePath: "/Applications/Gauge.app"))
        XCTAssertEqual(registered, 0)
    }

    func testNotRegisteredFromDMGOrBuildFolderButAppliedOnceInstalled() {
        XCTAssertFalse(LoginItem.applyDefaultIfNeeded(defaults: d, bundlePath: "/Volumes/Gauge 1.3.0/Gauge.app"))
        XCTAssertFalse(LoginItem.applyDefaultIfNeeded(defaults: d, bundlePath: "/Users/x/Gauge/build/Release/Gauge.app"))
        XCTAssertEqual(registered, 0)
        XCTAssertTrue(LoginItem.applyDefaultIfNeeded(defaults: d, bundlePath: "/Applications/Gauge.app"))
        XCTAssertEqual(registered, 1)
    }

    func testUserApplicationsFolderCounts() {
        XCTAssertTrue(LoginItem.isInstalledLocation(NSHomeDirectory() + "/Applications/Gauge.app"))
    }

    func testToggleBackOn() throws {
        try LoginItem.set(false, defaults: d)
        try LoginItem.set(true, defaults: d)
        XCTAssertEqual(registered, 1); XCTAssertTrue(LoginItem.isEnabled)
    }
}
