import Darwin
import Foundation

public struct MemorySample: Equatable, Sendable {
    public enum PressureLevel: Int, Sendable { case normal = 1, warning = 2, critical = 4 }

    public var totalBytes: UInt64
    /// App + wired + compressed, the figure Activity Monitor calls "Memory Used".
    public var usedBytes: UInt64
    public var appBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var cachedBytes: UInt64
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64
    /// 0...1, derived from the kernel's memorystatus level (fraction of memory the kernel
    /// considers available). Matches the shape of Activity Monitor's pressure graph.
    public var pressure: Double
    public var pressureLevel: PressureLevel

    public var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }

    public init(totalBytes: UInt64, usedBytes: UInt64, appBytes: UInt64, wiredBytes: UInt64, compressedBytes: UInt64,
                cachedBytes: UInt64, swapUsedBytes: UInt64, swapTotalBytes: UInt64, pressure: Double, pressureLevel: PressureLevel) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.cachedBytes = cachedBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.pressure = pressure
        self.pressureLevel = pressureLevel
    }
}

public struct MemoryReader {
    public let totalBytes: UInt64
    private let pageSize: UInt64

    public init() {
        totalBytes = UInt64(sysctlInt("hw.memsize") ?? 0)
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        pageSize = UInt64(size)
    }

    public func sample() -> MemorySample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        // "App memory" per Activity Monitor: internal (anonymous) pages minus purgeable.
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * pageSize
        let cached = UInt64(stats.external_page_count + stats.purgeable_count) * pageSize
        let used = app + wired + compressed

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        _ = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

        // kern.memorystatus_level is the percentage of memory the kernel considers available.
        let level = Double(sysctlInt("kern.memorystatus_level") ?? 100)
        let pressure = min(1, max(0, 1 - level / 100))
        let rawLevel = Int(sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1)
        let pressureLevel = MemorySample.PressureLevel(rawValue: rawLevel) ?? .normal

        return MemorySample(
            totalBytes: totalBytes,
            usedBytes: used,
            appBytes: app,
            wiredBytes: wired,
            compressedBytes: compressed,
            cachedBytes: cached,
            swapUsedBytes: swap.xsu_used,
            swapTotalBytes: swap.xsu_total,
            pressure: pressure,
            pressureLevel: pressureLevel
        )
    }
}
