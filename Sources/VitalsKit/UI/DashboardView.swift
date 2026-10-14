import SwiftUI

/// The main panel content: one card per metric, laid out like Control Centre.
struct DashboardView: View {
    let monitor: Monitor
    let settings: Settings
    var maxHeight: CGFloat
    var openSettings: () -> Void
    var quit: () -> Void

    @State private var processSort: ProcessSort = .cpu

    private var window: TimeInterval { settings.graphWindow.seconds }
    private var interval: TimeInterval { settings.refreshInterval.seconds }
    private var s: MonitorSnapshot { monitor.snapshot }
    private var h: Histories { monitor.histories }

    var body: some View {
        VStack(spacing: 0) {
            FittedScrollView(maxHeight: maxHeight - 44) {
                VStack(spacing: 8) {
                    if settings.isVisible(.cpu) { cpuCard }
                    if settings.isVisible(.memory) { memoryCard }
                    HStack(alignment: .top, spacing: 8) {
                        if settings.isVisible(.gpu) { gpuCard }
                        if settings.isVisible(.battery), s.battery != nil { powerCard }
                    }
                    HStack(alignment: .top, spacing: 8) {
                        if settings.isVisible(.network) { networkCard }
                        if settings.isVisible(.disk) { diskCard }
                    }
                    if settings.isVisible(.processes) { processesCard }
                }
                .padding(12)
            }
            footer
        }
    }

    // MARK: Full-width cards

    private var levelTints: [Color] { [.accentColor, .accentColor.opacity(0.45), .accentColor.opacity(0.25)] }

    private var cpuCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                let total = s.cpu?.total ?? 0
                CardHeader(symbol: "cpu", title: "CPU", value: Format.percent(total))
                AreaChart(points: h.cpuTotal.window(window), window: window, interval: interval, tint: settings.level(for: total).tint)
                if let cpu = s.cpu {
                    HStack(spacing: 10) {
                        ForEach(Array(cpu.levels.enumerated()), id: \.offset) { i, level in
                            LegendItem(color: levelTints[i % levelTints.count], label: level.name, value: Format.percent(level.load))
                        }
                        Spacer()
                    }
                    CoreStrip(sample: cpu, tints: levelTints)
                }
            }
        }
    }

    private var memoryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                let m = s.memory
                let pressure = m?.pressure ?? 0
                let level = settings.level(for: pressure)
                CardHeader(symbol: "memorychip", title: "Memory", value: Format.percent(pressure), detail: "pressure")
                AreaChart(points: h.memoryPressure.window(window), window: window, interval: interval, tint: level.tint)
                if let m {
                    let total = Double(m.totalBytes)
                    SegmentedBar(segments: [
                        .init(label: "App", fraction: Double(m.appBytes) / total, color: .accentColor),
                        .init(label: "Wired", fraction: Double(m.wiredBytes) / total, color: .accentColor.opacity(0.55)),
                        .init(label: "Compressed", fraction: Double(m.compressedBytes) / total, color: .accentColor.opacity(0.3)),
                    ])
                    HStack(spacing: 10) {
                        LegendItem(color: .accentColor, label: "App", value: Format.bytes(m.appBytes))
                        LegendItem(color: .accentColor.opacity(0.55), label: "Wired", value: Format.bytes(m.wiredBytes))
                        LegendItem(color: .accentColor.opacity(0.3), label: "Compressed", value: Format.bytes(m.compressedBytes))
                        Spacer(minLength: 0)
                    }
                    HStack {
                        Text("\(Format.bytes(m.usedBytes)) of \(Format.bytes(m.totalBytes)) used")
                        Spacer()
                        Text(m.swapUsedBytes > 0 ? "Swap \(Format.bytes(m.swapUsedBytes))" : "No swap")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                }
            }
        }
    }

    // MARK: Half-width cards

    private var gpuCard: some View {
        let g = s.gpu?.utilization ?? 0
        return CompactCard(symbol: "cube", title: "GPU", value: Format.percent(g),
                           footnote: s.gpu.map { "\(Format.bytes($0.allocatedBytes)) allocated" } ?? "—") {
            AreaChart(points: h.gpu.window(window), window: window, interval: interval, tint: settings.level(for: g).tint, height: 30)
        }
    }

    private var powerCard: some View {
        let b = s.battery
        return CompactCard(symbol: b?.externalPower == true ? "bolt.fill" : "battery.75percent", title: "Power", tint: .green,
                           value: Format.watts(b?.systemPowerWatts ?? 0),
                           footnote: b.map(batteryFootnote) ?? "—") {
            AreaChart(points: h.systemPower.window(window), window: window, interval: interval, tint: .green, yMax: nil, height: 30)
        }
    }

    /// e.g. "82% · charging 24.6 W · 45 min to full" or "61% · draining 9.1 W · 4h 10m left".
    private func batteryFootnote(_ b: BatterySample) -> String {
        let rate = Format.watts(abs(b.batteryPowerWatts))
        var parts = [Format.percent(b.charge)]
        switch b.state {
        case .charging:
            parts.append("charging \(rate)")
            if let m = b.minutesRemaining { parts.append("\(Format.duration(minutes: m)) to full") }
        case .discharging:
            parts.append("draining \(rate)")
            if let m = b.minutesRemaining { parts.append("\(Format.duration(minutes: m)) left") }
        case .full, .acNotCharging:
            // At 100% "charged" is implied; otherwise say why it isn't charging.
            if b.state == .acNotCharging { parts.append("not charging") }
            if let adapter = b.adapterWatts { parts.append("\(Int(adapter)) W adapter") }
        }
        return parts.joined(separator: " · ")
    }

    private var networkCard: some View {
        let n = s.network
        return CompactCard(symbol: "network", title: "Network", value: Format.rate(n?.downloadRate ?? 0), valuePrefix: "arrow.down",
                           footnote: "↑ \(Format.rate(n?.uploadRate ?? 0))") {
            DualLineChart(series: [
                .init(name: "Down", points: h.networkDown.window(window), tint: .accentColor),
                .init(name: "Up", points: h.networkUp.window(window), tint: .secondary),
            ], window: window, interval: interval, height: 30)
        }
    }

    private var diskCard: some View {
        let d = s.disk
        return CompactCard(symbol: "internaldrive", title: "Disk", value: Format.rate(d?.readRate ?? 0), valuePrefix: "arrow.down",
                           footnote: d.map { "↑ \(Format.rate($0.writeRate)) · \(Format.storage($0.freeBytes)) free" } ?? "—") {
            DualLineChart(series: [
                .init(name: "Read", points: h.diskRead.window(window), tint: .accentColor),
                .init(name: "Write", points: h.diskWrite.window(window), tint: .secondary),
            ], window: window, interval: interval, height: 30)
        }
    }

    // MARK: Processes

    private enum ProcessSort: String, CaseIterable { case cpu = "CPU", memory = "Memory" }

    private var processesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CardTitle(symbol: "list.bullet", title: "Top Processes")
                    Spacer()
                    Picker("Sort", selection: $processSort) {
                        ForEach(ProcessSort.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.mini)
                    .frame(width: 110)
                }
                if let p = s.processes {
                    let rows = processSort == .cpu ? p.topByCPU : p.topByMemory
                    let peak = processSort == .cpu
                        ? max(rows.map(\.cpu).max() ?? 0, 0.01)
                        : Double(max(rows.map(\.memoryBytes).max() ?? 1, 1))
                    VStack(spacing: 5) {
                        ForEach(rows) { proc in
                            let fraction = processSort == .cpu ? proc.cpu / peak : Double(proc.memoryBytes) / peak
                            HStack(spacing: 8) {
                                Text(proc.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(width: 124, alignment: .leading)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(.primary.opacity(0.07))
                                        Capsule().fill(Color.accentColor.opacity(0.75))
                                            .frame(width: max(3, geo.size.width * fraction))
                                    }
                                }
                                .frame(height: 5)
                                .animation(.easeOut(duration: 0.3), value: fraction)
                                Text(processSort == .cpu ? Format.percent(proc.cpu) : Format.bytes(proc.memoryBytes))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 58, alignment: .trailing)
                            }
                        }
                    }
                    Text("\(p.processCount) processes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    // Process CPU needs two samples; the first arrives within a second of opening.
                    Text("Sampling…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 11, weight: .semibold))
                Text("Vitals").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            Spacer()
            FooterButton(symbol: "gearshape.fill", help: "Settings", action: openSettings)
            FooterButton(symbol: "power", help: "Quit Vitals", action: quit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 44)
        .background(.primary.opacity(0.04))
        .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5) }
    }
}

/// Title row, a large value, a chart, and a one-line footnote. For half-width cards.
struct CompactCard<ChartContent: View>: View {
    var symbol: String
    var title: String
    var tint: Color = .accentColor
    var value: String
    var valuePrefix: String? = nil
    var footnote: String
    @ViewBuilder var chart: ChartContent

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                CardTitle(symbol: symbol, title: title, tint: tint)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if let valuePrefix {
                        Image(systemName: valuePrefix)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    HeadlineValue(text: value, size: 20)
                }
                chart
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
            }
        }
    }
}

struct FooterButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(hovering ? 0.95 : 0.7))
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(hovering ? 0.14 : 0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
