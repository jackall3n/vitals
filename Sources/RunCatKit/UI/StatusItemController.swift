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
        button.image = IndicatorRenderer.render(bars: bars, appearance: button.effectiveAppearance)

        if settings.showCPUText, let cpu = snapshot.cpu {
            // Figure spaces keep "7%" as wide as "100%" so the item never shifts its neighbours.
            let text = "\(Int((cpu.total * 100).rounded()))%"
            button.title = String(repeating: "\u{2007}", count: max(0, 4 - text.count)) + text
        } else {
            button.title = ""
        }
        if button.image == nil && button.title.isEmpty {
            button.title = "•" // never leave the item invisible
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
