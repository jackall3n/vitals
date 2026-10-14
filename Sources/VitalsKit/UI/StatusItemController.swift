import AppKit
import Observation
import SwiftUI

/// Owns the NSStatusItem, keeps its image and title in sync with the monitor, and toggles the panel.
@MainActor
public final class StatusItemController {
    private let statusItem: NSStatusItem
    private let panel: PanelWindowController
    private let monitor: Monitor
    private let settings: Settings
    let panelHost = PanelHost()
    /// What the status item currently shows, so identical ticks don't trigger a redraw.
    private var renderedKey: [Int] = []
    private var renderedTitle = ""

    public init(monitor: Monitor, settings: Settings) {
        self.monitor = monitor
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let host = panelHost
        panel = PanelWindowController { PanelRoot(monitor: monitor, settings: settings, host: host) }
        host.resize = { [weak self] size in self?.panel.apply(contentSize: size) }
        host.close = { [weak self] in self?.closePanel() }
        panel.onClose = { [weak self] in
            self?.monitor.includeProcesses = false
            self?.statusItem.button?.highlight(false)
        }

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .regular), weight: .regular)
        }
        observeAndRefresh()
    }

    var statusButton: NSStatusBarButton? { statusItem.button }
    var panelWindow: NSWindow { panel.window }

    /// Re-renders whenever anything the indicator depends on changes.
    private func observeAndRefresh() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAndRefresh() }
        }
    }

    func refresh() {
        guard let button = statusItem.button else { return }
        let snapshot = monitor.snapshot
        let bars: [IndicatorRenderer.Bar] = settings.indicatorMetrics.map { metric in
            let load: Double
            switch metric {
            case .cpu: load = snapshot.cpu?.total ?? 0
            case .memory: load = snapshot.memory?.pressure ?? 0
            case .gpu: load = snapshot.gpu?.utilization ?? 0
            }
            return IndicatorRenderer.Bar(load: load, level: settings.level(for: load))
        }
        // Bars are drawn at whole-point heights, so quantise before deciding whether to redraw.
        let appearanceIsDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let key = bars.flatMap { [Int(($0.load * 12).rounded()), $0.level == .normal ? 0 : ($0.level == .warning ? 1 : 2)] }
            + [appearanceIsDark ? 1 : 0]
        if key != renderedKey {
            renderedKey = key
            button.image = IndicatorRenderer.render(bars: bars, appearance: button.effectiveAppearance)
        }

        var title = ""
        if settings.showCPUText, let cpu = snapshot.cpu {
            // Figure spaces keep "7%" as wide as "100%" so the item never shifts its neighbours.
            let text = "\(Int((cpu.total * 100).rounded()))%"
            title = String(repeating: "\u{2007}", count: max(0, 4 - text.count)) + text
        }
        if bars.isEmpty && title.isEmpty {
            title = "•" // never leave the item invisible
        }
        if title != renderedTitle {
            renderedTitle = title
            button.title = title
        }
    }

    @objc private func togglePanel() {
        if panel.isShown {
            panel.close()
        } else {
            showPanel()
        }
    }

    public func showPanel() {
        guard !panel.isShown, let button = statusItem.button else { return }
        button.highlight(true)
        monitor.includeProcesses = true
        panel.show(under: button)
    }

    public func closePanel() {
        panel.close()
        monitor.includeProcesses = false
        statusItem.button?.highlight(false)
    }

}
