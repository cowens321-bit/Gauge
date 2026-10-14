import XCTest

final class DefaultsTests: XCTestCase {
    /// The product defaults: lightweight menu bar utility.
    func testShippedDefaults() {
        let keys = [Pref.refreshInterval, Pref.showMenuBar, Pref.menuBarStyle, Pref.showInDock, Pref.menuBarCPU,
                    Pref.menuBarMemory, Pref.menuBarNetwork, Pref.menuBarGPU, Pref.menuBarDisk, Pref.menuBarStorage, Pref.visualEffects]
        let d = UserDefaults.standard
        let saved = keys.map { ($0, d.object(forKey: $0)) }
        keys.forEach { d.removeObject(forKey: $0) }
        defer { saved.forEach { k, v in if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }
        Pref.registerDefaults()
        XCTAssertEqual(d.double(forKey: Pref.refreshInterval), 2, "scans every 2 seconds")
        XCTAssertTrue(d.bool(forKey: Pref.showMenuBar), "menu bar item on by default")
        XCTAssertFalse(d.bool(forKey: Pref.showInDock), "hidden from the Dock by default")
        XCTAssertEqual(d.string(forKey: Pref.menuBarStyle), MenuBarStyle.value.rawValue, "menu bar display = values")
        XCTAssertTrue(d.bool(forKey: Pref.menuBarCPU)); XCTAssertTrue(d.bool(forKey: Pref.menuBarMemory))
        XCTAssertFalse(d.bool(forKey: Pref.menuBarNetwork)); XCTAssertFalse(d.bool(forKey: Pref.menuBarGPU))
        XCTAssertEqual(d.string(forKey: Pref.visualEffects), VisualEffects.glass.rawValue)
    }
}
