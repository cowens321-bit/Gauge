import Foundation

/// Decides when an app has been using "a lot" for long enough to deserve a notification.
/// Pure and deterministic so it can be tested without notifications or real processes.
struct UsageAlertTracker {
    struct Config: Equatable {
        var cpuPercent: Double = 80          // 100 == one full core
        var memoryFraction: Double = 0.25    // of physical RAM
        var sustain: TimeInterval = 120      // must stay over the line this long
        var cooldown: TimeInterval = 30 * 60 // per app and kind
    }
    enum Kind: String, Sendable { case cpu, memory }
    struct Alert: Equatable, Sendable {
        var groupID: String
        var name: String
        var kind: Kind
        var value: Double     // cpu: percent of a core; memory: bytes
        var duration: TimeInterval
    }

    var config = Config()
    private var overSince: [String: Date] = [:]
    private var lastFired: [String: Date] = [:]

    init(config: Config = Config()) { self.config = config }

    mutating func update(groups: [GroupSnapshot], totalMemory: UInt64, now: Date) -> [Alert] {
        var alerts: [Alert] = []
        var stillOver = Set<String>()
        for g in groups where g.kind == .application {
            let checks: [(Kind, Double?, Bool)] = [
                (.cpu, g.cpuPercent, (g.cpuPercent ?? 0) >= config.cpuPercent),
                (.memory, g.memoryBytes.map(Double.init),
                 totalMemory > 0 && Double(g.memoryBytes ?? 0) >= config.memoryFraction * Double(totalMemory)),
            ]
            for (kind, value, over) in checks where over {
                let key = "\(g.id)|\(kind.rawValue)"
                stillOver.insert(key)
                let since = overSince[key] ?? now
                overSince[key] = since
                let held = now.timeIntervalSince(since)
                guard held >= config.sustain else { continue }
                if let last = lastFired[key], now.timeIntervalSince(last) < config.cooldown { continue }
                lastFired[key] = now
                alerts.append(Alert(groupID: g.id, name: g.name, kind: kind, value: value ?? 0, duration: held))
            }
        }
        // Dropping below the line (or the app quitting) resets the streak.
        overSince = overSince.filter { stillOver.contains($0.key) }
        return alerts
    }
}
