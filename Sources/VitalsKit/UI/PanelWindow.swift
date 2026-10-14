import AppKit
import SwiftUI

/// A borderless, non-activating panel anchored under the status item, in the style of the
/// system's Control Centre modules. Closes on click-outside, Escape, or when the app resigns.
///
/// Sizing: the SwiftUI root reports its size through `PanelHost.resize`, and the window follows.
@MainActor
final class PanelWindowController {
    static let cornerRadius: CGFloat = 22
    static let width: CGFloat = 360

    private let panel: NSPanel
    private let hosting: NSHostingView<AnyView>
    private let makeContent: () -> AnyView
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    /// Last size the content reported; reused so re-opening the panel starts at the right size.
    private var lastContentSize = NSSize(width: PanelWindowController.width, height: 420)
    /// Called after the panel closes for any reason (click-outside, Escape, programmatic).
    var onClose: () -> Void = {}

    var isShown: Bool { panel.isVisible }
    var window: NSWindow { panel }

    init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        makeContent = { AnyView(content()) }
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: lastContentSize),
                        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false

        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(origin: .zero, size: lastContentSize)
        panel.contentView = hosting
    }

    func show(under button: NSView) {
        guard let buttonWindow = button.window, let screen = buttonWindow.screen ?? NSScreen.main else { return }
        // Content is only mounted while visible so SwiftUI does no work when the panel is closed.
        hosting.rootView = makeContent()
        hosting.layoutSubtreeIfNeeded()
        let size = lastContentSize
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = anchor.midX - size.width / 2
        let margin: CGFloat = 8
        x = min(max(x, screen.visibleFrame.minX + margin), screen.visibleFrame.maxX - size.width - margin)
        let y = anchor.minY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        installMonitors()
    }

    func close() {
        guard panel.isVisible else { return }
        removeMonitors()
        panel.orderOut(nil)
        hosting.rootView = AnyView(EmptyView())
        onClose()
    }

    /// Called by the SwiftUI root whenever its size changes. Keeps the top edge anchored.
    func apply(contentSize: CGSize) {
        guard contentSize.width > 1, contentSize.height > 1 else { return }
        let size = NSSize(width: Self.width, height: contentSize.height.rounded())
        lastContentSize = size
        guard panel.isVisible else { return }
        var frame = panel.frame
        guard abs(frame.height - size.height) > 0.5 || abs(frame.width - size.width) > 0.5 else { return }
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
    }

    private func installMonitors() {
        removeMonitors()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.close()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        clickMonitor = nil
        keyMonitor = nil
    }
}
