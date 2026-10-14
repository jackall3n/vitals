import SwiftUI

/// Builds a smooth path through time-series points, mapped into `size` with the newest sample
/// at the right edge. Shared by the chart views below; drawn with Canvas so a tick costs one
/// CoreGraphics pass rather than a Swift Charts layout.
enum Sparkline {
    static func mappedPoints(_ points: [HistoryPoint], window: TimeInterval, upper: Double, size: CGSize) -> [CGPoint] {
        guard let last = points.last, window > 0, upper > 0 else { return [] }
        let start = last.time.timeIntervalSinceReferenceDate - window
        return points.map { p in
            let x = CGFloat((p.time.timeIntervalSinceReferenceDate - start) / window) * size.width
            let y = size.height - CGFloat(min(1, max(0, p.value / upper))) * size.height
            return CGPoint(x: max(0, min(size.width, x)), y: y)
        }
    }

    /// Catmull-Rom spline converted to cubic Béziers; drawing is clipped to the chart bounds so
    /// any slight overshoot never escapes.
    static func path(through pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        guard pts.count > 1 else { return path }
        if pts.count == 2 {
            path.addLine(to: pts[1])
            return path
        }
        for i in 0..<(pts.count - 1) {
            let p0 = i > 0 ? pts[i - 1] : pts[i]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = i + 2 < pts.count ? pts[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    static func area(under line: Path, points pts: [CGPoint], height: CGFloat) -> Path {
        var area = line
        guard let last = pts.last, let first = pts.first else { return area }
        area.addLine(to: CGPoint(x: last.x, y: height))
        area.addLine(to: CGPoint(x: first.x, y: height))
        area.closeSubpath()
        return area
    }

    static func draw(_ ctx: inout GraphicsContext, points: [HistoryPoint], window: TimeInterval, upper: Double,
                     size: CGSize, tint: Color, fillOpacity: Double) {
        let pts = mappedPoints(points, window: window, upper: upper, size: size)
        guard !pts.isEmpty else { return }
        let line = path(through: pts)
        let area = area(under: line, points: pts, height: size.height)
        ctx.fill(area, with: .linearGradient(
            Gradient(colors: [tint.opacity(fillOpacity), tint.opacity(0.02)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        if pts.count == 1 {
            ctx.fill(Path(ellipseIn: CGRect(x: pts[0].x - 2, y: pts[0].y - 2, width: 4, height: 4)), with: .color(tint))
        }
    }
}

/// A compact area chart with no axes, pinned so the newest sample sits at the right edge.
struct AreaChart: View {
    var points: [HistoryPoint]
    var window: TimeInterval
    var tint: Color = .accentColor
    /// Upper bound of the y axis. `nil` scales to the data.
    var yMax: Double? = 1
    var height: CGFloat = 40

    private var upper: Double {
        if let yMax { return yMax }
        let peak = points.map(\.value).max() ?? 0
        return peak > 0 ? peak * 1.15 : 1
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            ctx.clip(to: Path(CGRect(origin: .zero, size: size)))
            Sparkline.draw(&ctx, points: points, window: window, upper: upper, size: size, tint: tint, fillOpacity: 0.35)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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

    private var upper: Double {
        let peak = series.flatMap { $0.points.map(\.value) }.max() ?? 0
        return peak > 0 ? peak * 1.15 : 1
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            ctx.clip(to: Path(CGRect(origin: .zero, size: size)))
            // Draw the secondary series first so the primary sits on top.
            for s in series.reversed() {
                Sparkline.draw(&ctx, points: s.points, window: window, upper: upper, size: size, tint: s.tint, fillOpacity: 0.25)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
