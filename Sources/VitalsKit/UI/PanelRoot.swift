import SwiftUI

/// Shared state between the panel window and its SwiftUI content.
@MainActor
@Observable
final class PanelHost {
    var showingSettings = false
    @ObservationIgnored var resize: (CGSize) -> Void = { _ in }
    @ObservationIgnored var close: () -> Void = {}
}

/// The panel's root: a glass sheet that hosts either the dashboard or settings.
struct PanelRoot: View {
    let monitor: Monitor
    let settings: Settings
    let host: PanelHost

    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 40
    }

    var body: some View {
        ZStack {
            if host.showingSettings {
                SettingsView(settings: settings, maxHeight: maxHeight) {
                    withAnimation(.snappy(duration: 0.28)) { host.showingSettings = false }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                DashboardView(monitor: monitor, settings: settings, maxHeight: maxHeight,
                              openSettings: { withAnimation(.snappy(duration: 0.28)) { host.showingSettings = true } },
                              quit: { NSApp.terminate(nil) })
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: PanelWindowController.width)
        .background {
            RoundedRectangle(cornerRadius: PanelWindowController.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PanelWindowController.cornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: PanelWindowController.cornerRadius, style: .continuous))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { host.resize($0) }
    }
}

/// A vertical scroll view that is only as tall as its content, up to `maxHeight`.
struct FittedScrollView<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        if DevFlags.screenshotMode {
            // Offline rendering can't wait for the measurement below; show everything unscrolled.
            content
        } else {
            ScrollView(.vertical) {
                content
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(contentHeight, 1), maxHeight))
        }
    }
}

// MARK: - Shared building blocks

/// A rounded module in the style of Control Centre's tiles.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
            }
    }
}

/// Icon + title on the left, a headline value on the right. For full-width cards.
struct CardHeader: View {
    var symbol: String
    var title: String
    var tint: Color = .accentColor
    var value: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            CardTitle(symbol: symbol, title: title, tint: tint)
            Spacer(minLength: 8)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HeadlineValue(text: value, size: 17)
        }
    }
}

struct CardTitle: View {
    var symbol: String
    var title: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
    }
}

struct HeadlineValue: View {
    var text: String
    var size: CGFloat = 20

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
    }
}

/// A small coloured dot + label + value, used in legends.
struct LegendItem: View {
    var color: Color
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().contentTransition(.numericText())
        }
        .font(.caption)
        .lineLimit(1)
        .fixedSize()
    }
}

enum Format {
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Memory sizes: binary units, one decimal from GB upwards (e.g. "17.3 GB", "512 MB").
    static func bytes(_ value: UInt64) -> String {
        let v = Double(value)
        let gib = 1024.0 * 1024 * 1024
        if v >= gib { return String(format: "%.1f GB", v / gib) }
        if v >= 1024 * 1024 { return String(format: "%.0f MB", v / (1024 * 1024)) }
        if v >= 1024 { return String(format: "%.0f KB", v / 1024) }
        return "\(value) B"
    }

    /// Storage sizes: decimal units like Finder (e.g. "750 GB", "1.02 TB").
    static func storage(_ value: UInt64) -> String {
        let v = Double(value)
        if v >= 1e12 { return String(format: "%.2f TB", v / 1e12) }
        if v >= 1e9 { return String(format: "%.0f GB", v / 1e9) }
        if v >= 1e6 { return String(format: "%.0f MB", v / 1e6) }
        return String(format: "%.0f KB", v / 1e3)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bytesPerSecond
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let digits = index == 0 ? 0 : (value < 10 ? 1 : 0)
        return String(format: "%.\(digits)f %@", value, units[index])
    }

    static func watts(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m) min"
    }
}

extension LoadLevel {
    var tint: Color {
        switch self {
        case .normal: .accentColor
        case .warning: .orange
        case .critical: .red
        }
    }
}
