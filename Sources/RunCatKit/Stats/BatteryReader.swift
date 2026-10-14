import Foundation
import IOKit

public struct BatterySample: Equatable, Sendable {
    public enum State: Sendable { case charging, discharging, full, acNotCharging }

    /// 0...1
    public var charge: Double
    public var state: State
    public var externalPower: Bool
    /// Positive when charging, negative when discharging. Watts.
    public var batteryPowerWatts: Double
    /// Total system power draw in watts, from the SMC's power telemetry.
    public var systemPowerWatts: Double
    /// Rated wattage of the attached adapter, if any.
    public var adapterWatts: Double?
    /// Minutes to full or to empty, depending on state. `nil` when unknown.
    public var minutesRemaining: Int?
    public var cycleCount: Int
    /// 0...1, current max capacity relative to design capacity.
    public var health: Double

    public init(charge: Double, state: State, externalPower: Bool, batteryPowerWatts: Double, systemPowerWatts: Double,
                adapterWatts: Double?, minutesRemaining: Int?, cycleCount: Int, health: Double) {
        self.charge = charge
        self.state = state
        self.externalPower = externalPower
        self.batteryPowerWatts = batteryPowerWatts
        self.systemPowerWatts = systemPowerWatts
        self.adapterWatts = adapterWatts
        self.minutesRemaining = minutesRemaining
        self.cycleCount = cycleCount
        self.health = health
    }
}

/// Reads the `AppleSmartBattery` registry entry. Returns `nil` on machines without a battery.
public struct BatteryReader {
    public init() {}

    public func sample() -> BatterySample? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return Self.parse(dict)
    }

    static func parse(_ p: [String: Any]) -> BatterySample {
        func num(_ key: String) -> Double? { (p[key] as? NSNumber)?.doubleValue }
        func bool(_ key: String) -> Bool { (p[key] as? NSNumber)?.boolValue ?? false }

        let current = num("CurrentCapacity") ?? 0
        let max = num("MaxCapacity") ?? 100
        let charge = max > 0 ? min(1, current / max) : 0
        let external = bool("ExternalConnected")
        let charging = bool("IsCharging")
        let fullyCharged = bool("FullyCharged")

        let state: BatterySample.State
        if charging { state = .charging }
        else if !external { state = .discharging }
        else if fullyCharged || charge >= 0.99 { state = .full }
        else { state = .acNotCharging }

        // Amperage is signed mA (negative while discharging); Voltage is mV.
        let amps = (num("InstantAmperage") ?? num("Amperage") ?? 0) / 1000
        let volts = (num("Voltage") ?? 0) / 1000
        let batteryPower = amps * volts

        let telemetry = p["PowerTelemetryData"] as? [String: Any]
        let systemPowerMilliwatts = (telemetry?["SystemPowerIn"] as? NSNumber)?.doubleValue ?? 0
        let adapter = p["AdapterDetails"] as? [String: Any]
        let adapterWatts = (adapter?["Watts"] as? NSNumber)?.doubleValue
        let rawMinutes = Int(num("TimeRemaining") ?? 65535)
        let minutes = rawMinutes == 65535 || rawMinutes < 0 ? nil : rawMinutes

        let design = num("DesignCapacity") ?? 0
        let rawMax = num("AppleRawMaxCapacity") ?? 0
        let health = design > 0 && rawMax > 0 ? min(1, rawMax / design) : 1

        return BatterySample(
            charge: charge,
            state: state,
            externalPower: external,
            batteryPowerWatts: batteryPower,
            systemPowerWatts: systemPowerMilliwatts / 1000,
            adapterWatts: adapterWatts.flatMap { $0 > 0 ? $0 : nil },
            minutesRemaining: minutes,
            cycleCount: Int(num("CycleCount") ?? 0),
            health: health
        )
    }
}
