import AppKit
import Darwin

/// Safe termination. Graceful first; force only on explicit request; protected processes refused.
enum ProcessProtection {
    static let protectedBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.WindowServer",
        "com.apple.systemuiserver", "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.Spotlight", "com.apple.universalaccessd"
    ]
    static let protectedPathPrefixes = ["/System/Library/", "/usr/libexec/", "/usr/sbin/", "/sbin/"]

    /// Returns a user-facing reason if the process must not be terminated, or nil if allowed.
    static func reasonProtected(pid: Int32, uid: UInt32, path: String?, bundleID: String?,
                                currentUID: UInt32 = getuid(), selfPID: Int32 = getpid()) -> String? {
        if pid <= 1 { return "This is a core system process." }
        if pid == selfPID { return "Gauge cannot quit itself from here. Use Quit Gauge." }
        if uid != currentUID { return "This process belongs to another user or to the system." }
        if let b = bundleID, protectedBundleIDs.contains(b) { return "This is a protected macOS system component." }
        if let p = path, protectedPathPrefixes.contains(where: { p.hasPrefix($0) }) {
            return "This is a protected macOS system component."
        }
        return nil
    }

    static func reasonProtected(group g: GroupSnapshot) -> String? {
        if g.kind != .application { return "This is a collection of background services, not a single app. Open it to manage individual processes." }
        guard let root = g.processes.first(where: { $0.pid == g.rootPID }) ?? g.processes.first else { return "No running process." }
        return reasonProtected(pid: root.pid, uid: root.uid, path: g.bundlePath ?? root.path, bundleID: g.bundleID)
    }
}

@MainActor
enum ProcessController {
    static func runningApp(for g: GroupSnapshot) -> NSRunningApplication? {
        if let id = g.bundleID {
            let matches = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            if let m = matches.first(where: { $0.bundleURL?.path == g.bundlePath }) ?? matches.first { return m }
        }
        if let pid = g.rootPID { return NSRunningApplication(processIdentifier: pid) }
        return nil
    }

    /// Graceful quit. Returns false if refused/failed.
    @discardableResult
    static func quit(_ g: GroupSnapshot) -> Bool {
        guard ProcessProtection.reasonProtected(group: g) == nil else { return false }
        if let app = runningApp(for: g) { return app.terminate() }
        if let pid = g.rootPID { return kill(pid, SIGTERM) == 0 }
        return false
    }

    @discardableResult
    static func forceQuit(_ g: GroupSnapshot) -> Bool {
        guard ProcessProtection.reasonProtected(group: g) == nil else { return false }
        if let app = runningApp(for: g) {
            let ok = app.forceTerminate()
            // Helpers normally exit with their parent; reap any stragglers that are still ours to kill.
            for p in g.processes where p.pid != app.processIdentifier
                && ProcessProtection.reasonProtected(pid: p.pid, uid: p.uid, path: p.path, bundleID: nil) == nil {
                kill(p.pid, SIGKILL)
            }
            return ok
        }
        guard let pid = g.rootPID else { return false }
        return kill(pid, SIGKILL) == 0
    }

    @discardableResult
    static func terminate(process p: ProcessSnapshot, force: Bool) -> Bool {
        guard ProcessProtection.reasonProtected(pid: p.pid, uid: p.uid, path: p.path, bundleID: nil) == nil else { return false }
        return kill(p.pid, force ? SIGKILL : SIGTERM) == 0
    }

    static func revealInFinder(_ g: GroupSnapshot) {
        if let p = g.bundlePath { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
        else if let p = g.processes.first?.path { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
    }

    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
