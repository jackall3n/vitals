import AppKit

/// Draws the menu bar indicator: a row of slim vertical bars, one per metric.
public enum IndicatorRenderer {
    public struct Bar: Equatable, Sendable {
        public var load: Double
        public var level: LoadLevel
        public init(load: Double, level: LoadLevel) {
            self.load = load
            self.level = level
        }
    }

    public static let barWidth: CGFloat = 3
    public static let barGap: CGFloat = 2
    public static let imageHeight: CGFloat = 16
    static let barMaxHeight: CGFloat = 12
    static let barMinHeight: CGFloat = 2
    static let baseline: CGFloat = 2
    static let horizontalPadding: CGFloat = 1

    public static func imageWidth(barCount: Int) -> CGFloat {
        guard barCount > 0 else { return 0 }
        return CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap + horizontalPadding * 2
    }

    /// Renders bars in the given appearance so the "normal" colour matches the menu bar's
    /// label colour in both light and dark modes. Returns `nil` when there is nothing to draw.
    public static func render(bars: [Bar], appearance: NSAppearance? = nil) -> NSImage? {
        guard !bars.isEmpty else { return nil }
        let size = NSSize(width: imageWidth(barCount: bars.count), height: imageHeight)
        let image = NSImage(size: size, flipped: false) { rect in
            let draw = {
                for (index, bar) in bars.enumerated() {
                    let x = horizontalPadding + CGFloat(index) * (barWidth + barGap)
                    let track = NSBezierPath(roundedRect: NSRect(x: x, y: baseline, width: barWidth, height: barMaxHeight),
                                             xRadius: barWidth / 2, yRadius: barWidth / 2)
                    NSColor.labelColor.withAlphaComponent(0.18).setFill()
                    track.fill()

                    let clamped = min(1, max(0, bar.load))
                    let height = max(barMinHeight, (barMaxHeight * clamped).rounded())
                    let fill = NSBezierPath(roundedRect: NSRect(x: x, y: baseline, width: barWidth, height: height),
                                            xRadius: barWidth / 2, yRadius: barWidth / 2)
                    color(for: bar.level).setFill()
                    fill.fill()
                }
            }
            if let appearance {
                appearance.performAsCurrentDrawingAppearance(draw)
            } else {
                draw()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func color(for level: LoadLevel) -> NSColor {
        switch level {
        case .normal: .labelColor
        case .warning: .systemOrange
        case .critical: .systemRed
        }
    }
}
