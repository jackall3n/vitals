import Darwin
import Foundation

/// A snapshot of CPU load, split by performance level (e.g. "Performance" / "Efficiency").
public struct CPUSample: Equatable, Sendable {
    /// Total load across all cores, 0...1.
    public var total: Double
    /// Per-core load, 0...1, in kernel core order.
    public var perCore: [Double]
    /// Load per performance level, keyed by level name, 0...1.
    public var levels: [CPULevel]

    public init(total: Double, perCore: [Double], levels: [CPULevel]) {
        self.total = total
        self.perCore = perCore
        self.levels = levels
    }
}

public struct CPULevel: Equatable, Sendable {
    public var name: String
    public var coreRange: Range<Int>
    public var load: Double

    public init(name: String, coreRange: Range<Int>, load: Double) {
        self.name = name
        self.coreRange = coreRange
        self.load = load
    }
}

/// Describes the CPU topology: which core indices belong to which performance level.
public struct CPUTopology: Equatable, Sendable {
    public struct Level: Equatable, Sendable {
        public var name: String
        public var coreRange: Range<Int>
    }

    public var coreCount: Int
    /// Ordered from highest-performance level to lowest.
    public var levels: [Level]

    public init(coreCount: Int, levels: [Level]) {
        self.coreCount = coreCount
        self.levels = levels
    }

    /// Reads the topology from sysctl. Apple silicon enumerates the lowest-performance
    /// level's cores first (CPU 0..n are efficiency cores), so levels are laid out in
    /// reverse perflevel order.
    public static func current() -> CPUTopology {
        let coreCount = Int(sysctlInt("hw.logicalcpu") ?? 1)
        let levelCount = Int(sysctlInt("hw.nperflevels") ?? 1)
        guard levelCount > 1 else {
            return CPUTopology(coreCount: coreCount, levels: [Level(name: "All cores", coreRange: 0..<coreCount)])
        }
        var levels: [Level] = []
        // perflevel0 is the fastest; its cores have the highest indices.
        var end = coreCount
        for i in 0..<levelCount {
            let count = Int(sysctlInt("hw.perflevel\(i).logicalcpu") ?? 0)
            let name = sysctlString("hw.perflevel\(i).name") ?? "Level \(i)"
            let start = max(0, end - count)
            levels.append(Level(name: name, coreRange: start..<end))
            end = start
        }
        return CPUTopology(coreCount: coreCount, levels: levels)
    }
}

/// Reads CPU load via `host_processor_info`, computing deltas between successive calls.
public final class CPUReader {
    public let topology: CPUTopology
    private var previous: [CoreTicks]?

    struct CoreTicks: Equatable {
        var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32

        /// Per-field wrapping deltas; the kernel's counters are 32-bit and roll over.
        func delta(since p: CoreTicks) -> (busy: UInt64, total: UInt64) {
            let busy = UInt64(user &- p.user) + UInt64(system &- p.system) + UInt64(nice &- p.nice)
            return (busy, busy + UInt64(idle &- p.idle))
        }
    }

    public init(topology: CPUTopology = .current()) {
        self.topology = topology
    }

    /// Returns `nil` on the first call (no delta available yet) or if the kernel call fails.
    public func sample() -> CPUSample? {
        guard let current = readTicks() else { return nil }
        defer { previous = current }
        guard let previous, previous.count == current.count else { return nil }
        return Self.compute(previous: previous, current: current, topology: topology)
    }

    static func compute(previous: [CoreTicks], current: [CoreTicks], topology: CPUTopology) -> CPUSample {
        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)
        var busySum: UInt64 = 0, totalSum: UInt64 = 0
        for (p, c) in zip(previous, current) {
            let (busy, total) = c.delta(since: p)
            busySum += busy
            totalSum += total
            perCore.append(total == 0 ? 0 : Double(busy) / Double(total))
        }
        let levels = topology.levels.map { level -> CPULevel in
            let range = level.coreRange.clamped(to: 0..<perCore.count)
            let slice = perCore[range]
            let load = slice.isEmpty ? 0 : slice.reduce(0, +) / Double(slice.count)
            return CPULevel(name: level.name, coreRange: range, load: load)
        }
        return CPUSample(
            total: totalSum == 0 ? 0 : Double(busySum) / Double(totalSum),
            perCore: perCore,
            levels: levels
        )
    }

    private func readTicks() -> [CoreTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        var ticks: [CoreTicks] = []
        ticks.reserveCapacity(Int(cpuCount))
        for i in 0..<Int(cpuCount) {
            let base = i * stride
            ticks.append(CoreTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ))
        }
        return ticks
    }
}

// MARK: - sysctl helpers

func sysctlInt(_ name: String) -> Int64? {
    var value: Int64 = 0
    var size = MemoryLayout<Int64>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    switch size {
    case 4: return Int64(Int32(truncatingIfNeeded: value))
    default: return value
    }
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
}
