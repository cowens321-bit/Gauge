import Foundation

struct SystemPoint: Sendable, Equatable {
    var t: Date
    var cpuUser: Double
    var cpuSystem: Double
    var memUsedPct: Double
    var memApp: Double, memWired: Double, memCompressed: Double   // GB
    var gpu: Double?
    var netIn: Double?, netOut: Double?
    var diskRead: Double?, diskWrite: Double?
}

struct GroupPoint: Sendable, Equatable {
    var t: Date
    var cpu: Double?
    var mem: Double?       // bytes
    var disk: Double?
    var net: Double?
}

protocol Timestamped { var t: Date { get } }
extension SystemPoint: Timestamped {}
extension GroupPoint: Timestamped {}

/// Append-only, time-bounded history. Trims lazily so appends stay O(1) amortised.
struct TimeSeries<P: Timestamped & Sendable>: Sendable {
    private(set) var points: [P] = []
    private var head = 0
    private(set) var dropped = 0   // total points ever trimmed; keeps downsampling stable across ticks

    var count: Int { points.count - head }
    var isEmpty: Bool { count == 0 }
    var last: P? { isEmpty ? nil : points.last }
    var visible: ArraySlice<P> { points[head...] }

    mutating func append(_ p: P, keeping duration: TimeInterval) {
        points.append(p)
        trim(olderThan: p.t.addingTimeInterval(-duration))
    }

    mutating func trim(olderThan cutoff: Date) {
        while head < points.count, points[head].t < cutoff { head += 1; dropped += 1 }
        if head > 256 && head * 2 > points.count {
            points.removeFirst(head); head = 0
        }
    }

    /// Evenly strided points, at most `maxPoints`, always including the newest.
    func downsampled(maxPoints: Int) -> [P] {
        let v = visible
        guard v.count > maxPoints, maxPoints > 1 else { return Array(v) }
        let stride = Double(v.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { v[v.startIndex + Int((Double($0) * stride).rounded())] }
    }

    /// Downsampling anchored to absolute sample numbers, so a given sample is either always or never
    /// drawn. This keeps animated charts from shimmering as the window slides.
    func stable(maxPoints: Int) -> [P] {
        let v = visible
        guard v.count > maxPoints, maxPoints > 1 else { return Array(v) }
        let k = Int((Double(v.count) / Double(maxPoints)).rounded(.up))
        let base = dropped
        var out: [P] = []
        out.reserveCapacity(maxPoints + 1)
        for (i, p) in v.enumerated() where (base + i) % k == 0 { out.append(p) }
        if let last = v.last, out.last?.t != last.t { out.append(last) }
        return out
    }

    /// Splits history into runs separated by gaps (paused / hidden / sleeping) so charts do not
    /// draw lines across missing samples.
    static func segmentIndices(_ pts: [P], gap: TimeInterval) -> [Int] {
        var seg = 0
        var out: [Int] = []
        var prev: Date?
        for p in pts {
            if let pr = prev, p.t.timeIntervalSince(pr) > gap { seg += 1 }
            out.append(seg); prev = p.t
        }
        return out
    }
}
