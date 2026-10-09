import SwiftUI
import Charts

struct ChartPoint: Identifiable {
    let id: Int
    let t: Date
    let v: Double
    let seg: Int
}

struct ChartSeries: Identifiable {
    enum Kind { case line, area, stackedArea }
    let id: String
    let name: String
    let color: Color
    let kind: Kind
    let points: [ChartPoint]

    /// Builds a series, starting a new segment at every missing value or time gap so that charts
    /// never interpolate across samples that were not taken. Point ids derive from the timestamp so
    /// that marks keep their identity (and animate smoothly) as the window slides.
    static func make(_ name: String, color: Color, kind: Kind = .line, gap: TimeInterval,
                     _ values: [(Date, Double?)]) -> ChartSeries {
        var pts: [ChartPoint] = []
        var seg = 0
        var prev: Date?
        for (t, v) in values {
            if let pr = prev, t.timeIntervalSince(pr) > gap { seg += 1 }
            prev = t
            guard let v else { seg += 1; continue }
            pts.append(ChartPoint(id: Int(t.timeIntervalSinceReferenceDate * 1000), t: t, v: v, seg: seg))
        }
        return ChartSeries(id: name, name: name, color: color, kind: kind, points: pts)
    }

    var fill: LinearGradient {
        LinearGradient(colors: [color.opacity(kind == .stackedArea ? 0.9 : 0.42), color.opacity(kind == .stackedArea ? 0.55 : 0.02)],
                       startPoint: .top, endPoint: .bottom)
    }
}

@ChartContentBuilder
private func marks(for s: ChartSeries, p: ChartPoint) -> some ChartContent {
    let seg = "\(s.name)\(p.seg)"
    switch s.kind {
    case .line:
        LineMark(x: .value("Time", p.t), y: .value(s.name, p.v), series: .value("seg", seg))
            .foregroundStyle(s.color.gradient).lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
    case .area:
        AreaMark(x: .value("Time", p.t), y: .value(s.name, p.v), series: .value("seg", seg), stacking: .unstacked)
            .foregroundStyle(s.fill).interpolationMethod(.monotone)
        LineMark(x: .value("Time", p.t), y: .value(s.name, p.v), series: .value("seg", seg))
            .foregroundStyle(s.color).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
    case .stackedArea:
        AreaMark(x: .value("Time", p.t), y: .value(s.name, p.v), series: .value("seg", seg), stacking: .standard)
            .foregroundStyle(s.fill).interpolationMethod(.monotone)
    }
}

/// Full-size interactive chart: gradient fills, glowing live point, scrubbing with a glass tooltip.
struct TimeChart: View {
    let series: [ChartSeries]
    let window: TimeInterval
    var yDomain: ClosedRange<Double>? = nil
    var format: (Double) -> String = { String(format: "%.0f", $0) }
    var height: CGFloat = 150
    var showLegend = true
    @State private var selected: Date?

    private var end: Date { series.compactMap { $0.points.last?.t }.max() ?? Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showLegend && series.count > 1 {
                HStack(spacing: 12) { ForEach(series) { LegendDot(color: $0.color, name: $0.name) } }
            }
            chart.frame(height: height)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series) { s in
                ForEach(s.points) { p in marks(for: s, p: p) }
                if s.kind != .stackedArea, let last = s.points.last {
                    PointMark(x: .value("Time", last.t), y: .value(s.name, last.v)).symbolSize(260).foregroundStyle(s.color.opacity(0.22))
                    PointMark(x: .value("Time", last.t), y: .value(s.name, last.v)).symbolSize(55).foregroundStyle(s.color)
                }
            }
            if let sel = nearest {
                RuleMark(x: .value("Time", sel.0))
                    .foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sel.0, format: .dateTime.hour().minute().second()).font(.caption2).foregroundStyle(.secondary)
                            ForEach(sel.1, id: \.0) { n, v in
                                HStack(spacing: 5) { Circle().fill(color(for: n)).frame(width: 6, height: 6)
                                    Text("\(n)  \(format(v))").font(.caption2.monospacedDigit().weight(.medium)) }
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    }
            }
        }
        .chartXScale(domain: end.addingTimeInterval(-window)...end)
        .chartYScale(domain: yDomain ?? 0...max(1, (series.flatMap { $0.points.map(\.v) }.max() ?? 1) * 1.2))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4])).foregroundStyle(.secondary.opacity(0.35))
                AxisValueLabel(format: .dateTime.hour().minute().second()).foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4])).foregroundStyle(.secondary.opacity(0.35))
                AxisValueLabel { if let d = v.as(Double.self) { Text(format(d)).font(.caption2).foregroundStyle(.secondary) } }
            }
        }
        .chartXSelection(value: $selected)
        .chartLegend(.hidden)
        .transaction { $0.animation = nil }   // data ticks redraw instantly; only numbers/rings animate
    }

    private func color(for name: String) -> Color { series.first { $0.name == name }?.color ?? .primary }

    private var nearest: (Date, [(String, Double)])? {
        guard let selected else { return nil }
        var best: Date?
        for s in series { for p in s.points where best == nil || abs(p.t.timeIntervalSince(selected)) < abs(best!.timeIntervalSince(selected)) { best = p.t } }
        guard let b = best else { return nil }
        let vals: [(String, Double)] = series.compactMap { s in
            s.points.first(where: { abs($0.t.timeIntervalSince(b)) < 0.001 }).map { (s.name, $0.v) }
        }
        return (b, vals)
    }
}

/// Axis-less chart for summary cards.
struct MiniChart: View {
    let series: [ChartSeries]
    let window: TimeInterval
    var yDomain: ClosedRange<Double>
    var body: some View {
        let end = series.compactMap { $0.points.last?.t }.max() ?? Date()
        Chart {
            ForEach(series) { s in
                ForEach(s.points) { p in marks(for: s, p: p) }
                if s.kind != .stackedArea, let last = s.points.last {
                    PointMark(x: .value("t", last.t), y: .value("v", last.v)).symbolSize(120).foregroundStyle(s.color.opacity(0.25))
                    PointMark(x: .value("t", last.t), y: .value("v", last.v)).symbolSize(28).foregroundStyle(s.color)
                }
            }
        }
        .chartLegend(.hidden).chartXAxis(.hidden).chartYAxis(.hidden)
        .chartXScale(domain: end.addingTimeInterval(-window)...end)
        .chartYScale(domain: yDomain)
        .chartPlotStyle { $0.padding(.horizontal, 4) }
        .transaction { $0.animation = nil }
    }
}
