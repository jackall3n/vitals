import Darwin
import Foundation
import IOKit

public struct DiskSample: Equatable, Sendable {
    /// Bytes per second across all block storage devices.
    public var readRate: Double
    public var writeRate: Double
    public var totalReadBytes: UInt64
    public var totalWriteBytes: UInt64
    /// Boot volume capacity.
    public var totalBytes: UInt64
    public var freeBytes: UInt64

    public var usedBytes: UInt64 { totalBytes >= freeBytes ? totalBytes - freeBytes : 0 }
    public var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }

    public init(readRate: Double, writeRate: Double, totalReadBytes: UInt64, totalWriteBytes: UInt64, totalBytes: UInt64, freeBytes: UInt64) {
        self.readRate = readRate
        self.writeRate = writeRate
        self.totalReadBytes = totalReadBytes
        self.totalWriteBytes = totalWriteBytes
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
    }
}

/// Reads throughput from `IOBlockStorageDriver` statistics and capacity from `statfs`.
public final class DiskReader {
    struct Counters: Equatable {
        var read: UInt64
        var write: UInt64
    }

    private var previous: (Counters, Date)?
    public let volumePath: String

    public init(volumePath: String = "/") {
        self.volumePath = volumePath
    }

    /// Returns `nil` on the first call, when no rate can be derived yet.
    public func sample(now: Date = Date()) -> DiskSample? {
        guard let current = readCounters(), let (total, free) = readCapacity() else { return nil }
        defer { previous = (current, now) }
        guard let (prev, prevTime) = previous else { return nil }
        return Self.compute(previous: prev, current: current, interval: now.timeIntervalSince(prevTime), total: total, free: free)
    }

    static func compute(previous: Counters, current: Counters, interval: TimeInterval, total: UInt64, free: UInt64) -> DiskSample {
        let dt = max(interval, 0.001)
        let rd = current.read >= previous.read ? current.read - previous.read : 0
        let wr = current.write >= previous.write ? current.write - previous.write : 0
        return DiskSample(
            readRate: Double(rd) / dt,
            writeRate: Double(wr) / dt,
            totalReadBytes: current.read,
            totalWriteBytes: current.write,
            totalBytes: total,
            freeBytes: free
        )
    }

    private func readCapacity() -> (UInt64, UInt64)? {
        var fs = statfs()
        guard statfs(volumePath, &fs) == 0 else { return nil }
        let block = UInt64(fs.f_bsize)
        return (UInt64(fs.f_blocks) * block, UInt64(fs.f_bavail) * block)
    }

    private func readCounters() -> Counters? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var counters = Counters(read: 0, write: 0)
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            counters.read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            counters.write &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return counters
    }
}
