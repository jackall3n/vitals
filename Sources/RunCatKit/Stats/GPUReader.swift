import Foundation
import IOKit

public struct GPUSample: Equatable, Sendable {
    /// Device utilisation, 0...1.
    public var utilization: Double
    public var rendererUtilization: Double
    public var tilerUtilization: Double
    /// Memory allocated by the GPU driver, in bytes.
    public var allocatedBytes: UInt64

    public init(utilization: Double, rendererUtilization: Double, tilerUtilization: Double, allocatedBytes: UInt64) {
        self.utilization = utilization
        self.rendererUtilization = rendererUtilization
        self.tilerUtilization = tilerUtilization
        self.allocatedBytes = allocatedBytes
    }
}

/// Reads GPU utilisation from the IOAccelerator service's `PerformanceStatistics` dictionary.
public struct GPUReader {
    public init() {}

    public func sample() -> GPUSample? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var best: GPUSample?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            let sample = Self.parse(stats)
            if best == nil || sample.utilization > best!.utilization { best = sample }
        }
        return best
    }

    static func parse(_ stats: [String: Any]) -> GPUSample {
        func pct(_ key: String) -> Double {
            min(1, max(0, (stats[key] as? NSNumber)?.doubleValue ?? 0) / 100)
        }
        return GPUSample(
            utilization: pct("Device Utilization %"),
            rendererUtilization: pct("Renderer Utilization %"),
            tilerUtilization: pct("Tiler Utilization %"),
            allocatedBytes: (stats["Alloc system memory"] as? NSNumber)?.uint64Value ?? 0
        )
    }
}
