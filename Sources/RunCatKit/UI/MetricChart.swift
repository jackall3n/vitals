import Charts
import SwiftUI

/// A compact area chart with no axes, pinned so the newest sample sits at the right edge.
struct AreaChart: View {
    var points: [HistoryPoint]
    var window: TimeInterval
    var tint: Color = .accentColor
    /// Upper bound of the y axis. `nil` scales to the data.
    var yMax: Double? = 1
    var height: CGFloat = 40

    private var domain: ClosedRange<Date> {
        let end = points.last?.time ?? Date()
        return end.addingTimeInterval(-window)...end
    }

    private var upper: Double {
        if let yMax { return yMax }
        let peak = points.map(\.value).max() ?? 0
        return peak > 0 ? peak * 1.15 : 1
    }

    var body: some View {
        Chart(points) { p in
            AreaMark(x: .value("Time", p.time), y: .value("Value", p.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(colors: [tint.opacity(0.38), tint.opacity(0.03)], startPoint: .top, endPoint: .bottom)
                )
            LineMark(x: .value("Time", p.time), y: .value("Value", p.value))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(tint)
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...upper)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(.easeOut(duration: 0.3), value: points.count)
    }
}

/// Two series on one chart (e.g. download/upload), sharing a y scale derived from both.
struct DualLineChart: View {
    struct Series: Identifiable {
        var id: String { name }
        var name: String
        var points: [HistoryPoint]
        var tint: Color
    }

    var series: [Series]
    var window: TimeInterval
    var height: CGFloat = 40

    private var domain: ClosedRange<Date> {
        let end = series.compactMap { $0.points.last?.time }.max() ?? Date()
        return end.addingTimeInterval(-window)...end
    }

    private var upper: Double {
        let peak = series.flatMap { $0.points.map(\.value) }.max() ?? 0
        return peak > 0 ? peak * 1.15 : 1
    }

    var body: some View {
        Chart {
            ForEach(series) { s in
                ForEach(s.points) { p in
                    AreaMark(x: .value("Time", p.time), y: .value(s.name, p.value), series: .value("Series", s.name))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(colors: [s.tint.opacity(0.28), s.tint.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                        )
                    LineMark(x: .value("Time", p.time), y: .value(s.name, p.value), series: .value("Series", s.name))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(s.tint)
                }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...upper)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(.easeOut(duration: 0.3), value: series.first?.points.count ?? 0)
    }
}

/// A horizontal bar split into proportional coloured segments, e.g. memory composition.
struct SegmentedBar: View {
    struct Segment: Identifiable {
        var id: String { label }
        var label: String
        var fraction: Double
        var color: Color
    }

    var segments: [Segment]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(segments.filter { $0.fraction > 0.002 }) { s in
                    Rectangle()
                        .fill(s.color)
                        .frame(width: max(2, geo.size.width * s.fraction))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(.primary.opacity(0.07))
        .clipShape(Capsule())
        .animation(.easeOut(duration: 0.3), value: segments.map(\.fraction))
    }
}

/// One slim bar per CPU core, grouped by performance level.
struct CoreStrip: View {
    var sample: CPUSample
    var tints: [Color]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(sample.levels.enumerated()), id: \.offset) { index, level in
                HStack(spacing: 2.5) {
                    ForEach(Array(level.coreRange), id: \.self) { core in
                        let load = core < sample.perCore.count ? sample.perCore[core] : 0
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(.primary.opacity(0.07))
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(tints[index % tints.count])
                                .frame(height: max(2, (14 * load).rounded()))
                        }
                        .frame(height: 14)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: sample.perCore)
    }
}
