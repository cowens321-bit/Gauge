import Foundation

/// Pure filtering + sorting so it can be unit tested without UI.
enum AppFilter {
    static func apply(_ groups: [GroupSnapshot], scope: ListScope, query: String) -> [GroupSnapshot] {
        let scoped = groups.filter { g in
            switch scope {
            case .userApps: return g.isUserApp
            case .allApps: return g.kind == .application
            case .everything: return true
            }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return scoped }
        return scoped.filter { matches($0, q) }
    }

    static func matches(_ g: GroupSnapshot, _ q: String) -> Bool {
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if g.name.range(of: q, options: opts) != nil { return true }
        if g.bundleID?.range(of: q, options: opts) != nil { return true }
        if let pid = Int32(q), g.processes.contains(where: { $0.pid == pid }) { return true }
        return g.processes.contains { $0.name.range(of: q, options: opts) != nil }
    }

    static func comparators(for key: SortKey) -> [KeyPathComparator<GroupSnapshot>] {
        switch key {
        case .cpu: return [.init(\.cpuSort, order: .reverse)]
        case .memory: return [.init(\.memorySort, order: .reverse)]
        case .energy: return [.init(\.powerSort, order: .reverse)]
        case .processes: return [.init(\.processCount, order: .reverse)]
        case .name: return [.init(\.name, comparator: .localizedStandard)]
        }
    }
}
