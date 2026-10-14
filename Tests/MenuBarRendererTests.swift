import XCTest
import AppKit

@MainActor
final class MenuBarRendererTests: XCTestCase {
    func sample() -> (SystemSnapshot, TimeSeries<SystemPoint>) {
        var h = TimeSeries<SystemPoint>()
        for i in 0..<30 {
            h.append(SystemPoint(t: Date().addingTimeInterval(Double(i)), cpuUser: 20 + Double(i % 7) * 4, cpuSystem: 8, memUsedPct: 60,
                                 memApp: 1, memWired: 1, memCompressed: 1, gpu: Double(i % 5) * 10, netIn: 1e6 * Double(i % 4), netOut: 2e5,
                                 diskRead: 3e6, diskWrite: 1e6), keeping: 600)
        }
        let s = SystemSnapshot(date: Date(), cpu: CPUUsage(user: 30, system: 8, coreCount: 10),
                               memory: MemoryUsage(totalBytes: 32 << 30, appBytes: 10 << 30, wiredBytes: 3 << 30, compressedBytes: 1 << 30,
                                                   cachedBytes: 6 << 30, freeBytes: 1 << 30, swapUsedBytes: 0, pressure: .normal),
                               gpuUtilization: 42, network: Throughput(inBps: 1_200_000, outBps: 90_000),
                               disk: Throughput(inBps: 3_000_000, outBps: 500_000),
                               storage: StorageUsage(totalBytes: 1_000_000_000_000, availableBytes: 412_000_000_000), thermalState: .nominal)
        return (s, h)
    }

    func testOnlyEnabledMetricsAreShown() {
        let d = UserDefaults(suiteName: "gauge.test.mb")!
        d.removePersistentDomain(forName: "gauge.test.mb")
        for k in [Pref.menuBarCPU, Pref.menuBarMemory, Pref.menuBarGPU, Pref.menuBarNetwork, Pref.menuBarDisk, Pref.menuBarStorage] { d.set(false, forKey: k) }
        d.set(true, forKey: Pref.menuBarCPU); d.set(true, forKey: Pref.menuBarStorage)
        let (s, h) = sample()
        let items = MenuBarRenderer.items(snapshot: s, history: h, defaults: d)
        XCTAssertEqual(items.map(\.id), ["cpu", "storage"])
        XCTAssertEqual(items[0].line1, "38%")
        XCTAssertEqual(items[1].line1, "412GB")
        d.set(true, forKey: Pref.menuBarNetwork); d.set(true, forKey: Pref.menuBarDisk); d.set(true, forKey: Pref.menuBarGPU); d.set(true, forKey: Pref.menuBarMemory)
        XCTAssertEqual(MenuBarRenderer.items(snapshot: s, history: h, defaults: d).map(\.id), ["cpu", "mem", "gpu", "net", "disk", "storage"])
    }

    func testUnavailableMetricsRenderAsDashesNotZero() {
        let d = UserDefaults(suiteName: "gauge.test.mb2")!
        d.set(true, forKey: Pref.menuBarGPU); d.set(true, forKey: Pref.menuBarNetwork)
        let (s, h) = sample()
        var none = s; none.gpuUtilization = nil; none.network = nil
        let items = MenuBarRenderer.items(snapshot: none, history: h, defaults: d)
        XCTAssertEqual(items.first { $0.id == "gpu" }?.line1, "n/a")
        XCTAssertEqual(items.first { $0.id == "net" }?.line1, "↓—")
    }

    func testRendersTemplateImageForEveryStyle() throws {
        let (s, h) = sample()
        let d = UserDefaults.standard
        for k in [Pref.menuBarCPU, Pref.menuBarMemory, Pref.menuBarGPU, Pref.menuBarNetwork, Pref.menuBarDisk, Pref.menuBarStorage] { d.set(true, forKey: k) }
        defer { for k in [Pref.menuBarCPU, Pref.menuBarMemory, Pref.menuBarGPU, Pref.menuBarNetwork, Pref.menuBarDisk, Pref.menuBarStorage, Pref.menuBarStyle] { d.removeObject(forKey: k) } }
        var widths: [CGFloat] = []
        for style in MenuBarStyle.allCases {
            d.set(style.rawValue, forKey: Pref.menuBarStyle)
            let img = MenuBarRenderer.render(snapshot: s, history: h)
            XCTAssertTrue(img.isTemplate); XCTAssertEqual(img.size.height, 22); XCTAssertGreaterThan(img.size.width, 40)
            widths.append(img.size.width)
            if let dir = ProcessInfo.processInfo.environment["GAUGE_SNAPSHOT_DIR"],
               let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                // draw black-on-white at 4x for inspection
                let scale: CGFloat = 4
                let out = NSImage(size: NSSize(width: img.size.width * scale, height: 22 * scale), flipped: false) { r in
                    NSColor.white.setFill(); r.fill(); img.draw(in: r); return true }
                if let t = out.tiffRepresentation, let r = NSBitmapImageRep(data: t), let png = r.representation(using: .png, properties: [:]) {
                    try png.write(to: URL(fileURLWithPath: dir + "/menubar-\(style.rawValue).png"))
                }
                _ = rep
            }
        }
        XCTAssertGreaterThan(widths[2], widths[0], "values+graphs is wider than values only")
    }
}

@MainActor
final class LaunchSafetyTests: XCTestCase {
    /// Regression: a defaults-changed notification delivered before launch finished used to render the menu
    /// bar image synchronously, re-entering AppKit font/appearance initialisation and aborting in libdispatch.
    func testDefaultsNotificationBeforeStartDoesNoRendering() async throws {
        let model = MonitorModel.shared
        XCTAssertFalse(model.started)
        UserDefaults.standard.set(true, forKey: Pref.showMenuBar)
        defer { UserDefaults.standard.removeObject(forKey: Pref.showMenuBar) }
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
        model.reevaluate()
        model.refreshMenuBarImage()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.menuBarImage.size.width, 0, "nothing may render before start()")
        XCTAssertFalse(model.started)
    }
}
