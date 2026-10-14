import Foundation
import Testing
@testable import RunCatKit

@Suite struct SettingsTests {
    /// A throwaway defaults domain so tests never touch the real preferences.
    private func freshStore() -> UserDefaults {
        let name = "runcat.tests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    @Test func defaultsWhenNothingStored() {
        let s = Settings(store: freshStore())
        #expect(s.openAtLogin)
        #expect(s.indicatorMetrics == [.cpu, .memory, .gpu])
        #expect(s.showCPUText)
        #expect(s.refreshInterval == .oneSecond)
        #expect(s.graphWindow == .oneMinute)
        #expect(s.warningThreshold == 0.6)
        #expect(s.criticalThreshold == 0.85)
        #expect(s.hiddenSections.isEmpty)
        #expect(PanelSection.allCases.allSatisfy { s.isVisible($0) })
    }

    @Test func changesPersistAcrossInstances() {
        let store = freshStore()
        let a = Settings(store: store)
        a.openAtLogin = false
        a.indicatorMetrics = [.gpu, .cpu]
        a.showCPUText = false
        a.refreshInterval = .fiveSeconds
        a.graphWindow = .fiveMinutes
        a.warningThreshold = 0.5
        a.criticalThreshold = 0.9
        a.setVisible(.battery, false)
        a.setVisible(.disk, false)

        let b = Settings(store: store)
        #expect(!b.openAtLogin)
        #expect(b.indicatorMetrics == [.gpu, .cpu])
        #expect(!b.showCPUText)
        #expect(b.refreshInterval == .fiveSeconds)
        #expect(b.graphWindow == .fiveMinutes)
        #expect(b.warningThreshold == 0.5)
        #expect(b.criticalThreshold == 0.9)
        #expect(b.hiddenSections == [.battery, .disk])
        #expect(!b.isVisible(.battery))
        #expect(b.isVisible(.cpu))
    }

    @Test func emptyIndicatorListIsPreserved() {
        let store = freshStore()
        Settings(store: store).indicatorMetrics = []
        #expect(Settings(store: store).indicatorMetrics.isEmpty)
    }

    @Test func ignoresCorruptStoredValues() {
        let store = freshStore()
        store.set(["cpu", "bogus"], forKey: Settings.Key.indicatorMetrics)
        store.set(7, forKey: Settings.Key.refreshInterval)
        store.set(["nope"], forKey: Settings.Key.hiddenSections)
        let s = Settings(store: store)
        #expect(s.indicatorMetrics == [.cpu])
        #expect(s.refreshInterval == .oneSecond)
        #expect(s.hiddenSections.isEmpty)
    }

    @Test func classifiesLoadAgainstThresholds() {
        let s = Settings(store: freshStore())
        #expect(s.level(for: 0) == .normal)
        #expect(s.level(for: 0.59) == .normal)
        #expect(s.level(for: 0.6) == .warning)
        #expect(s.level(for: 0.84) == .warning)
        #expect(s.level(for: 0.85) == .critical)
        #expect(s.level(for: 1) == .critical)
    }

    @Test func resetRestoresDefaults() {
        let store = freshStore()
        let s = Settings(store: store)
        s.openAtLogin = false
        s.refreshInterval = .twoSeconds
        s.setVisible(.gpu, false)
        s.resetToDefaults()
        #expect(s.openAtLogin)
        #expect(s.refreshInterval == .oneSecond)
        #expect(s.hiddenSections.isEmpty)
        #expect(Settings(store: store).openAtLogin)
    }
}
