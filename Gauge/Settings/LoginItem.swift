import Foundation
import ServiceManagement

/// Launch-at-login, backed by `SMAppService.mainApp`. The system's registration is the source of truth;
/// Gauge only decides the *default*: on, applied once on first run from an installed location, and never
/// re-applied after the user has made a choice.
enum LoginItem {
    struct Hooks {
        var status: () -> SMAppService.Status = { SMAppService.mainApp.status }
        var register: () throws -> Void = { try SMAppService.mainApp.register() }
        var unregister: () throws -> Void = { try SMAppService.mainApp.unregister() }
    }
    nonisolated(unsafe) static var hooks = Hooks()

    static var isEnabled: Bool { hooks.status() == .enabled }
    static var needsApproval: Bool { hooks.status() == .requiresApproval }

    /// Only register from a real install, otherwise the login item would point at a DMG or build folder.
    static func isInstalledLocation(_ bundlePath: String) -> Bool {
        let home = (NSHomeDirectory() as NSString).appendingPathComponent("Applications") + "/"
        return bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix(home)
    }

    /// User toggle. Records that the user has chosen, so the default is never applied again.
    static func set(_ on: Bool, defaults: UserDefaults = .standard) throws {
        defaults.set(true, forKey: Pref.loginItemConfigured)
        defaults.set(on, forKey: Pref.launchAtLogin)
        if on { try hooks.register() } else { try hooks.unregister() }
    }

    /// First-run default. Returns true if it registered Gauge.
    @discardableResult
    static func applyDefaultIfNeeded(defaults: UserDefaults = .standard, bundlePath: String = Bundle.main.bundlePath) -> Bool {
        guard !defaults.bool(forKey: Pref.loginItemConfigured) else { return false }
        guard isInstalledLocation(bundlePath) else { return false }   // try again once it is installed
        defaults.set(true, forKey: Pref.loginItemConfigured)
        guard defaults.bool(forKey: Pref.launchAtLogin) else { return false }
        if hooks.status() == .enabled { return false }
        do { try hooks.register(); return true } catch { return false }
    }
}
