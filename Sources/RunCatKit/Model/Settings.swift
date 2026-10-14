import Foundation
import Observation

public enum IndicatorMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, memory, gpu
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        }
    }
}

public enum RefreshInterval: Int, Codable, CaseIterable, Identifiable, Sendable {
    case oneSecond = 1, twoSeconds = 2, fiveSeconds = 5
    public var id: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue) }
    public var title: String { "\(rawValue)s" }
}

public enum GraphWindow: Int, Codable, CaseIterable, Identifiable, Sendable {
    case oneMinute = 60, fiveMinutes = 300
    public var id: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue) }
    public var title: String {
        switch self {
        case .oneMinute: "1 min"
        case .fiveMinutes: "5 min"
        }
    }
}

public enum PanelSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, memory, gpu, network, disk, battery, processes
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .network: "Network"
        case .disk: "Disk"
        case .battery: "Battery & Power"
        case .processes: "Processes"
        }
    }
}

/// User preferences, persisted to `UserDefaults` on every change.
@Observable
public final class Settings {
    public static let defaultWarningThreshold = 0.6
    public static let defaultCriticalThreshold = 0.85

    public var openAtLogin: Bool { didSet { store.set(openAtLogin, forKey: Key.openAtLogin) } }
    public var indicatorMetrics: [IndicatorMetric] { didSet { store.set(indicatorMetrics.map(\.rawValue), forKey: Key.indicatorMetrics) } }
    public var showCPUText: Bool { didSet { store.set(showCPUText, forKey: Key.showCPUText) } }
    public var refreshInterval: RefreshInterval { didSet { store.set(refreshInterval.rawValue, forKey: Key.refreshInterval) } }
    public var graphWindow: GraphWindow { didSet { store.set(graphWindow.rawValue, forKey: Key.graphWindow) } }
    /// Load at which indicator bars turn amber, 0...1.
    public var warningThreshold: Double { didSet { store.set(warningThreshold, forKey: Key.warningThreshold) } }
    /// Load at which indicator bars turn red, 0...1.
    public var criticalThreshold: Double { didSet { store.set(criticalThreshold, forKey: Key.criticalThreshold) } }
    public var hiddenSections: Set<PanelSection> { didSet { store.set(hiddenSections.map(\.rawValue).sorted(), forKey: Key.hiddenSections) } }

    @ObservationIgnored private let store: UserDefaults

    enum Key {
        static let openAtLogin = "openAtLogin"
        static let indicatorMetrics = "indicatorMetrics"
        static let showCPUText = "showCPUText"
        static let refreshInterval = "refreshInterval"
        static let graphWindow = "graphWindow"
        static let warningThreshold = "warningThreshold"
        static let criticalThreshold = "criticalThreshold"
        static let hiddenSections = "hiddenSections"
    }

    public init(store: UserDefaults = .standard) {
        self.store = store
        openAtLogin = store.object(forKey: Key.openAtLogin) as? Bool ?? true
        let rawMetrics = store.stringArray(forKey: Key.indicatorMetrics) ?? []
        let metrics = rawMetrics.compactMap(IndicatorMetric.init(rawValue:))
        indicatorMetrics = store.object(forKey: Key.indicatorMetrics) == nil ? IndicatorMetric.allCases : metrics
        // Off by default: a changing number makes the status item's width jitter.
        showCPUText = store.object(forKey: Key.showCPUText) as? Bool ?? false
        refreshInterval = RefreshInterval(rawValue: store.integer(forKey: Key.refreshInterval)) ?? .oneSecond
        graphWindow = GraphWindow(rawValue: store.integer(forKey: Key.graphWindow)) ?? .oneMinute
        warningThreshold = store.object(forKey: Key.warningThreshold) as? Double ?? Self.defaultWarningThreshold
        criticalThreshold = store.object(forKey: Key.criticalThreshold) as? Double ?? Self.defaultCriticalThreshold
        hiddenSections = Set((store.stringArray(forKey: Key.hiddenSections) ?? []).compactMap(PanelSection.init(rawValue:)))
    }

    public func isVisible(_ section: PanelSection) -> Bool { !hiddenSections.contains(section) }

    public func setVisible(_ section: PanelSection, _ visible: Bool) {
        if visible { hiddenSections.remove(section) } else { hiddenSections.insert(section) }
    }

    /// Classifies a 0...1 load against the configured thresholds.
    public func level(for load: Double) -> LoadLevel {
        if load >= criticalThreshold { return .critical }
        if load >= warningThreshold { return .warning }
        return .normal
    }

    public func resetToDefaults() {
        openAtLogin = true
        indicatorMetrics = IndicatorMetric.allCases
        showCPUText = false
        refreshInterval = .oneSecond
        graphWindow = .oneMinute
        warningThreshold = Self.defaultWarningThreshold
        criticalThreshold = Self.defaultCriticalThreshold
        hiddenSections = []
    }
}

public enum LoadLevel: Sendable {
    case normal, warning, critical
}
