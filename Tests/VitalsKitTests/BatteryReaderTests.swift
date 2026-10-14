import Testing
@testable import VitalsKit

@Suite struct BatteryReaderTests {
    @Test func parsesChargingOnAdapter() {
        let props: [String: Any] = [
            "CurrentCapacity": 80, "MaxCapacity": 100,
            "ExternalConnected": true, "IsCharging": true, "FullyCharged": false,
            "InstantAmperage": 2000, "Voltage": 12500,
            "TimeRemaining": 45, "CycleCount": 4,
            "DesignCapacity": 6249, "AppleRawMaxCapacity": 6186,
            "PowerTelemetryData": ["SystemPowerIn": 11999],
            "AdapterDetails": ["Watts": 57],
        ]
        let s = BatteryReader.parse(props)
        #expect(s.charge == 0.8)
        #expect(s.state == .charging)
        #expect(s.externalPower)
        #expect(s.batteryPowerWatts == 25)
        #expect(abs(s.systemPowerWatts - 11.999) < 1e-9)
        #expect(s.adapterWatts == 57)
        #expect(s.minutesRemaining == 45)
        #expect(s.cycleCount == 4)
        #expect(abs(s.health - 6186.0 / 6249.0) < 1e-9)
    }

    @Test func parsesDischarging() {
        let props: [String: Any] = [
            "CurrentCapacity": 50, "MaxCapacity": 100,
            "ExternalConnected": false, "IsCharging": false,
            "InstantAmperage": -1500, "Voltage": 12000,
            "TimeRemaining": 65535,
        ]
        let s = BatteryReader.parse(props)
        #expect(s.state == .discharging)
        #expect(s.batteryPowerWatts == -18)
        #expect(s.minutesRemaining == nil)
        #expect(s.adapterWatts == nil)
        #expect(s.health == 1)
    }

    @Test func parsesFullOnAdapter() {
        let s = BatteryReader.parse(["CurrentCapacity": 100, "MaxCapacity": 100, "ExternalConnected": true, "IsCharging": false, "FullyCharged": true])
        #expect(s.state == .full)
    }

    @Test func liveSampleIsWithinBounds() throws {
        guard let s = BatteryReader().sample() else { return } // desktop Macs have no battery
        #expect((0...1).contains(s.charge))
        #expect((0...1).contains(s.health))
        #expect(s.systemPowerWatts >= 0)
        #expect(s.cycleCount >= 0)
    }
}
