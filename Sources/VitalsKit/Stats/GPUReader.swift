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
/// The service handles are looked up once; each sample only copies the statistics property.
public final class GPUReader {
    private let services: [io_service_t]

    public init() {
        services = IOKitServices.matching("IOAccelerator")
    }

    deinit {
        services.forEach { IOObjectRelease($0) }
    }

    public func sample() -> GPUSample? {
        var best: GPUSample?
        for service in services {
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

enum IOKitServices {
    /// All services matching the class name. The caller owns the returned objects.
    static func matching(_ className: String) -> [io_service_t] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var services: [io_service_t] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            services.append(service)
        }
        return services
    }
}
