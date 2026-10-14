import SwiftUI

/// In-panel settings, pushed over the dashboard.
struct SettingsView: View {
    @Bindable var settings: Settings
    var maxHeight: CGFloat
    var back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            FittedScrollView(maxHeight: maxHeight - 40) {
                VStack(spacing: 8) {
                    generalCard
                    menuBarCard
                    refreshCard
                    thresholdsCard
                    sectionsCard
                    Button("Reset to Defaults") { settings.resetToDefaults() }
                        .controlSize(.small)
                        .padding(.top, 4)
                }
                .padding(12)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: back) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("Back")
                }
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Settings").font(.subheadline.weight(.semibold))
            Spacer()
            Color.clear.frame(width: 44, height: 1) // balance the back button so the title centres
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var generalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SettingsRow(title: "Open at login") {
                    Toggle("", isOn: $settings.openAtLogin).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                if !LoginItem.isRunningFromBundle {
                    Text("Only available when running from Vitals.app.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var menuBarCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Menu Bar")
                ForEach(Array(settings.indicatorMetrics.enumerated()), id: \.element) { index, metric in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).font(.caption)
                        Text(metric.title).font(.subheadline)
                        Spacer()
                        OrderButton(symbol: "chevron.up", enabled: index > 0) { move(metric, by: -1) }
                        OrderButton(symbol: "chevron.down", enabled: index < settings.indicatorMetrics.count - 1) { move(metric, by: 1) }
                        Button { settings.indicatorMetrics.removeAll { $0 == metric } } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                let missing = IndicatorMetric.allCases.filter { !settings.indicatorMetrics.contains($0) }
                if !missing.isEmpty {
                    HStack(spacing: 6) {
                        Text("Add").font(.caption).foregroundStyle(.secondary)
                        ForEach(missing) { metric in
                            Button(metric.title) { settings.indicatorMetrics.append(metric) }
                                .controlSize(.mini)
                        }
                    }
                }
                Divider().opacity(0.5)
                SettingsRow(title: "Show CPU percentage", subtitle: "Fixed width, so the menu bar never shifts") {
                    Toggle("", isOn: $settings.showCPUText).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
    }

    private func move(_ metric: IndicatorMetric, by offset: Int) {
        guard let index = settings.indicatorMetrics.firstIndex(of: metric) else { return }
        let target = index + offset
        guard settings.indicatorMetrics.indices.contains(target) else { return }
        settings.indicatorMetrics.swapAt(index, target)
    }

    private var refreshCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(title: "Refresh every") {
                    Picker("", selection: $settings.refreshInterval) {
                        ForEach(RefreshInterval.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 130)
                }
                SettingsRow(title: "Graph window") {
                    Picker("", selection: $settings.graphWindow) {
                        ForEach(GraphWindow.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 130)
                }
            }
        }
    }

    private var thresholdsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Indicator Colours")
                ThresholdSlider(title: "Amber above", color: .orange, value: $settings.warningThreshold, range: 0.1...0.95)
                    .onChange(of: settings.warningThreshold) { _, new in
                        if settings.criticalThreshold <= new { settings.criticalThreshold = min(1, new + 0.05) }
                    }
                ThresholdSlider(title: "Red above", color: .red, value: $settings.criticalThreshold, range: 0.15...1)
                    .onChange(of: settings.criticalThreshold) { _, new in
                        if settings.warningThreshold >= new { settings.warningThreshold = max(0, new - 0.05) }
                    }
            }
        }
    }

    private var sectionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle("Panel Sections")
                ForEach(PanelSection.allCases) { section in
                    SettingsRow(title: section.title) {
                        Toggle("", isOn: Binding(
                            get: { settings.isVisible(section) },
                            set: { settings.setVisible(section, $0) }
                        ))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    }
                }
            }
        }
    }
}

// MARK: - Settings widgets

struct SectionTitle: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .kerning(0.4)
    }
}

struct SettingsRow<Control: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            control
        }
    }
}

struct OrderButton: View {
    var symbol: String
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(enabled ? .secondary : .quaternary)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct ThresholdSlider: View {
    var title: String
    var color: Color
    @Binding var value: Double
    var range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.subheadline)
            Slider(value: $value, in: range, step: 0.05).controlSize(.small)
            Text(Format.percent(value))
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
