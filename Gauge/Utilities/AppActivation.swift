import AppKit
import SwiftUI

/// Menu bar utility activation rules.
///
/// * Only the menu bar item is showing → `.accessory`: no Dock icon, no app menu.
/// * A Gauge window is open (main window, Settings, the update dialog) → `.regular`: the window comes to the
///   front properly and the **Gauge** app menu (Check for Updates…, Settings…, Quit) appears at the top left.
/// * "Show in Dock" on, or the menu bar item hidden → always `.regular`.
@MainActor
enum AppActivation {
    /// A real app window: titled, normal level, not the menu bar extra panel.
    static func isAppWindow(_ w: NSWindow) -> Bool {
        countsAsAppWindow(visible: w.isVisible, miniaturized: w.isMiniaturized, titled: w.styleMask.contains(.titled),
                          normalLevel: w.level == .normal, isPanel: w is NSPanel)
    }
    nonisolated static func countsAsAppWindow(visible: Bool, miniaturized: Bool, titled: Bool, normalLevel: Bool, isPanel: Bool) -> Bool {
        (visible || miniaturized) && titled && normalLevel && !isPanel
    }

    static var hasAppWindow: Bool { NSApp.windows.contains(where: isAppWindow) }

    static func desiredPolicy(defaults d: UserDefaults = .standard, hasWindow: Bool) -> NSApplication.ActivationPolicy {
        (d.bool(forKey: Pref.showInDock) || !d.bool(forKey: Pref.showMenuBar) || hasWindow) ? .regular : .accessory
    }

    static func update() {
        let policy = desiredPolicy(hasWindow: hasAppWindow)
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    /// Become a foreground app, then bring `window` (matched by identifier) to the front once it exists.
    static func bringToFront(windowMatching id: String? = nil) {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate()
        // The window may only be created on the next run-loop turn; retry briefly.
        func focus(_ attempt: Int) {
            let target = NSApp.windows.first { w in
                isAppWindow(w) && (id == nil || (w.identifier?.rawValue.contains(id!) ?? false))
            }
            if let target {
                if target.isMiniaturized { target.deminiaturize(nil) }
                target.makeKeyAndOrderFront(nil)
                NSApp.activate()
            } else if attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focus(attempt + 1) }
            }
        }
        DispatchQueue.main.async { focus(0) }
    }
}

/// Environment action so views outside the app target (e.g. the menu bar popover) can trigger Sparkle.
private struct CheckForUpdatesKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues {
    var checkForUpdates: (() -> Void)? { get { self[CheckForUpdatesKey.self] } set { self[CheckForUpdatesKey.self] = newValue } }
}

extension Notification.Name {
    /// Asks the scene layer to open the main window. `userInfo["select"]` may carry an app group id to inspect.
    static let gaugeOpenMainWindow = Notification.Name("gauge.openMainWindow")
    /// Asks the main window to select (and inspect) the app group id in `object`.
    static let gaugeSelectGroup = Notification.Name("gauge.selectGroup")
}
