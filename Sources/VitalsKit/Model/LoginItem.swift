import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the app can register itself as a login item.
public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Registers or unregisters the running app bundle. Throws if the system refuses, which
    /// happens for unbundled executables (e.g. `swift run`) and for apps the user has blocked.
    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    /// Whether the current process is running from a proper .app bundle, which login items require.
    public static var isRunningFromBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
