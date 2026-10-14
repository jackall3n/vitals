import AppKit
import Observation

/// Entry point used by the launcher. Wires settings, monitor and the status item together.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let settings = Settings()
    public private(set) var monitor: Monitor!
    private var statusItem: StatusItemController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        monitor = Monitor(interval: settings.refreshInterval.seconds)
        monitor.sampleNow()
        statusItem = StatusItemController(monitor: monitor, settings: settings)
        monitor.start()
        observeSettings()
        syncLoginItem()
        // Development hooks: `-ShowPanel YES` opens the panel on launch; `-Screenshot <dir>` renders
        // the indicator and panel to PNGs in <dir> and quits; `-LoginItemStatus YES` prints the
        // SMAppService registration state and quits.
        if UserDefaults.standard.bool(forKey: "UnregisterLoginItem") {
            do { try LoginItem.setEnabled(false); print("unregistered, status=\(LoginItem.status)") }
            catch { print("unregister failed: \(error)") }
            exit(0)
        }
        if UserDefaults.standard.bool(forKey: "LoginItemStatus") {
            print("bundle=\(Bundle.main.bundleURL.path) fromBundle=\(LoginItem.isRunningFromBundle) " +
                  "setting=\(settings.openAtLogin) status=\(LoginItem.status) enabled=\(LoginItem.isEnabled)")
            exit(0)
        }
        if UserDefaults.standard.bool(forKey: "ShowPanel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in statusItem.showPanel() }
        }
        if let dir = UserDefaults.standard.string(forKey: "Screenshot") {
            // `-ScreenshotDelay <seconds>` lets the graphs accumulate history first.
            let delay = max(2.5, UserDefaults.standard.double(forKey: "ScreenshotDelay"))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                Screenshotter.run(into: dir, statusItem: statusItem, monitor: monitor, settings: settings)
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.refreshInterval
            _ = settings.openAtLogin
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.monitor.setInterval(self.settings.refreshInterval.seconds)
                self.syncLoginItem()
                self.observeSettings()
            }
        }
    }

    /// Applies the user's open-at-login preference. Silently skipped when not running from a
    /// bundle, since `swift run` builds can't be registered.
    private func syncLoginItem() {
        guard LoginItem.isRunningFromBundle else { return }
        do {
            try LoginItem.setEnabled(settings.openAtLogin)
        } catch {
            NSLog("Vitals: could not update login item: \(error)")
        }
    }
}

public enum VitalsApp {
    /// Runs the application. Never returns.
    @MainActor
    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
