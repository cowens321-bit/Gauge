import XCTest
import AppKit

@MainActor
final class AppActivationTests: XCTestCase {
    func defaults(dock: Bool, menuBar: Bool) -> UserDefaults {
        let d = UserDefaults(suiteName: "gauge.test.act.\(UUID().uuidString)")!
        d.set(dock, forKey: Pref.showInDock); d.set(menuBar, forKey: Pref.showMenuBar)
        return d
    }

    func testMenuBarOnlyIsAccessory() {
        XCTAssertEqual(AppActivation.desiredPolicy(defaults: defaults(dock: false, menuBar: true), hasWindow: false), .accessory)
    }
    func testOpenWindowMakesItARegularAppWithMenus() {
        XCTAssertEqual(AppActivation.desiredPolicy(defaults: defaults(dock: false, menuBar: true), hasWindow: true), .regular)
    }
    func testShowInDockAlwaysRegular() {
        XCTAssertEqual(AppActivation.desiredPolicy(defaults: defaults(dock: true, menuBar: true), hasWindow: false), .regular)
    }
    func testHiddenMenuBarItemKeepsAppReachable() {
        XCTAssertEqual(AppActivation.desiredPolicy(defaults: defaults(dock: false, menuBar: false), hasWindow: false), .regular)
    }

    func testOnlyRealWindowsCount() {
        let f = AppActivation.countsAsAppWindow
        XCTAssertTrue(f(true, false, true, true, false), "visible titled window")
        XCTAssertTrue(f(false, true, true, true, false), "minimised window still counts (restorable from the Dock)")
        XCTAssertFalse(f(false, false, true, true, false), "closed/hidden window")
        XCTAssertFalse(f(true, false, true, true, true), "menu bar extra panel")
        XCTAssertFalse(f(true, false, false, true, false), "borderless (status item) window")
        XCTAssertFalse(f(true, false, true, false, false), "floating/overlay level")
    }
}
