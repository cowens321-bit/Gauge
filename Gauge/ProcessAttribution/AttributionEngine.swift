import Foundation

struct AttributionContext: Sendable {
    /// Bundle paths of running apps with `.regular` activation policy (Dock apps).
    var regularAppPaths: Set<String> = []
    /// pid -> macOS responsible pid.
    var responsible: [Int32: Int32] = [:]
}

/// Decides which application every process belongs to. In priority order:
///  1. the executable lives inside an `.app` bundle           -> certain
///  2. macOS' "responsible process" resolves to an app        -> strong
///  3. an ancestor in the parent chain belongs to an app      -> inferred (flagged)
///  4. otherwise it is reported as unattributed (never guessed from the executable name)
struct AttributionEngine {
    var bundleInfo: (String) -> AppBundleInfo?

    static func appBundleCandidates(in path: String) -> [String] {
        // Simulator runtimes embed hundreds of unrelated .app bundles; attribute those via the
        // responsible process (Simulator.app / Xcode) rather than their own bundle.
        if path.contains("/CoreSimulator/Devices/") || path.contains("/CoreSimulator/Volumes/") { return [] }
        var result: [String] = []
        var prefix = ""
        for comp in path.split(separator: "/", omittingEmptySubsequences: true) {
            prefix += "/" + comp
            if comp.hasSuffix(".app") && comp.count > 4 { result.append(prefix) }
        }
        return result
    }

    /// Picks the owning bundle for an executable path. Nested bundles (helpers) fold into the
    /// outermost app, except a nested bundle that is itself a Dock app (e.g. Instruments inside Xcode).
    static func owningBundle(forPath path: String, regular: Set<String>) -> String? {
        let c = appBundleCandidates(in: path)
        guard !c.isEmpty else { return nil }
        if let inner = c.last(where: { regular.contains($0) }) { return inner }
        return c.first
    }

    /// Executables shipped with macOS (agents, XPC services, frameworks) that have no owning app.
    static func isApplePath(_ path: String?) -> Bool {
        guard let p = path else { return false }
        return ["/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/bin/", "/sbin/", "/Library/Apple/"].contains { p.hasPrefix($0) }
    }

    func attribute(_ records: [ProcessRecord], context: AttributionContext) -> [ProcessIdentity: Attribution] {
        var byPID: [Int32: ProcessRecord] = [:]
        for r in records { byPID[r.pid] = r }
        var infoCache: [String: AppBundleInfo] = [:]

        func info(_ bundlePath: String) -> AppBundleInfo {
            if let i = infoCache[bundlePath] { return i }
            let i = bundleInfo(bundlePath) ?? AppBundleInfo(
                path: bundlePath,
                name: ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension,
                bundleID: nil)
            infoCache[bundlePath] = i
            return i
        }
        func app(_ bundlePath: String, _ reason: AttributionReason) -> Attribution {
            Attribution(key: GroupKey(value: bundlePath), kind: .application, reason: reason, bundle: info(bundlePath))
        }
        func bundle(of rec: ProcessRecord) -> String? {
            rec.path.flatMap { Self.owningBundle(forPath: $0, regular: context.regularAppPaths) }
        }

        var out: [ProcessIdentity: Attribution] = [:]
        out.reserveCapacity(records.count)
        for rec in records {
            if let b = bundle(of: rec) { out[rec.id] = app(b, .bundlePath); continue }

            // 2. responsible process (follow up to 4 hops)
            var cur = rec.pid
            var found: String?
            for _ in 0..<4 {
                guard let r = context.responsible[cur], r != cur, r > 1, let rr = byPID[r] else { break }
                if let b = bundle(of: rr) { found = b; break }
                cur = r
            }
            if let b = found { out[rec.id] = app(b, .responsibleProcess); continue }

            // 3. ancestry
            var parent = rec.parentPID
            var depth = 0
            var inferred: String?
            while parent > 1, depth < 32, let pr = byPID[parent] {
                if let b = bundle(of: pr) { inferred = b; break }
                parent = pr.parentPID; depth += 1
            }
            if let b = inferred { out[rec.id] = app(b, .ancestry); continue }

            // 4. unattributed
            let (key, kind): (GroupKey, GroupKind)
            if rec.uid == 0 { (key, kind) = (.system, .systemServices) }
            else if Self.isApplePath(rec.path) { (key, kind) = (.macOS, .macOSServices) }
            else { (key, kind) = (.background, .backgroundServices) }
            out[rec.id] = Attribution(key: key, kind: kind, reason: .unattributed, bundle: nil)
        }
        return out
    }
}
