import Darwin
import Foundation

public struct NetworkSample: Equatable, Sendable {
    /// Bytes per second.
    public var downloadRate: Double
    public var uploadRate: Double
    public var totalReceivedBytes: UInt64
    public var totalSentBytes: UInt64

    public init(downloadRate: Double, uploadRate: Double, totalReceivedBytes: UInt64, totalSentBytes: UInt64) {
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
        self.totalReceivedBytes = totalReceivedBytes
        self.totalSentBytes = totalSentBytes
    }
}

/// Reads interface byte counters via `getifaddrs` and derives rates between calls.
public final class NetworkReader {
    struct Counters: Equatable {
        var received: UInt64
        var sent: UInt64
    }

    private var previous: (Counters, Date)?

    public init() {}

    /// Returns `nil` on the first call, when no rate can be derived yet.
    public func sample(now: Date = Date()) -> NetworkSample? {
        guard let current = readCounters() else { return nil }
        defer { previous = (current, now) }
        guard let (prev, prevTime) = previous else { return nil }
        return Self.compute(previous: prev, current: current, interval: now.timeIntervalSince(prevTime))
    }

    static func compute(previous: Counters, current: Counters, interval: TimeInterval) -> NetworkSample {
        let dt = max(interval, 0.001)
        let rx = current.received >= previous.received ? current.received - previous.received : 0
        let tx = current.sent >= previous.sent ? current.sent - previous.sent : 0
        return NetworkSample(
            downloadRate: Double(rx) / dt,
            uploadRate: Double(tx) / dt,
            totalReceivedBytes: current.received,
            totalSentBytes: current.sent
        )
    }

    /// Sums counters over all non-loopback link-layer interfaces.
    private func readCounters() -> Counters? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var counters = Counters(received: 0, sent: 0)
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            // Skip loopback and virtual interfaces that would double-count traffic.
            if name.hasPrefix("lo") || name.hasPrefix("utun") || name.hasPrefix("awdl") || name.hasPrefix("llw")
                || name.hasPrefix("bridge") || name.hasPrefix("gif") || name.hasPrefix("stf") || name.hasPrefix("ap") {
                continue
            }
            counters.received &+= UInt64(data.pointee.ifi_ibytes)
            counters.sent &+= UInt64(data.pointee.ifi_obytes)
        }
        return counters
    }
}
