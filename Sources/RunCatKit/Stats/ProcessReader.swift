import Darwin
import Foundation

public struct ProcessInfoSample: Equatable, Sendable, Identifiable {
    public var pid: pid_t
    public var name: String
    /// CPU load since the previous sample, 0...1 per core (so may exceed 1 on multi-core use).
    public var cpu: Double
    /// Physical footprint in bytes (what Activity Monitor shows as "Memory").
    public var memoryBytes: UInt64

    public var id: pid_t { pid }

    public init(pid: pid_t, name: String, cpu: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.cpu = cpu
        self.memoryBytes = memoryBytes
    }
}

public struct ProcessSample: Equatable, Sendable {
    public var topByCPU: [ProcessInfoSample]
    public var topByMemory: [ProcessInfoSample]
    public var processCount: Int

    public init(topByCPU: [ProcessInfoSample], topByMemory: [ProcessInfoSample], processCount: Int) {
        self.topByCPU = topByCPU
        self.topByMemory = topByMemory
        self.processCount = processCount
    }
}

/// Enumerates processes with `proc_listallpids` and reads CPU time and footprint via `proc_pid_rusage`.
public final class ProcessReader {
    struct Snapshot {
        var cpuTimeNanos: UInt64
        var memoryBytes: UInt64
        var name: String
    }

    private var previous: ([pid_t: Snapshot], Date)?
    private let nanosPerTick: Double
    public let limit: Int

    public init(limit: Int = 5) {
        self.limit = limit
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        nanosPerTick = Double(timebase.numer) / Double(timebase.denom)
    }

    /// Returns `nil` on the first call, when no CPU delta is available yet.
    public func sample(now: Date = Date()) -> ProcessSample? {
        let current = readAll()
        defer { previous = (current, now) }
        guard let (prev, prevTime) = previous else { return nil }
        return Self.compute(previous: prev, current: current, interval: now.timeIntervalSince(prevTime), limit: limit)
    }

    static func compute(previous: [pid_t: Snapshot], current: [pid_t: Snapshot], interval: TimeInterval, limit: Int) -> ProcessSample {
        let dtNanos = max(interval, 0.001) * 1_000_000_000
        var rows: [ProcessInfoSample] = []
        rows.reserveCapacity(current.count)
        for (pid, snap) in current {
            var cpu = 0.0
            if let prev = previous[pid], snap.cpuTimeNanos >= prev.cpuTimeNanos {
                cpu = Double(snap.cpuTimeNanos - prev.cpuTimeNanos) / dtNanos
            }
            rows.append(ProcessInfoSample(pid: pid, name: snap.name, cpu: cpu, memoryBytes: snap.memoryBytes))
        }
        let byCPU = Array(rows.sorted { $0.cpu > $1.cpu || ($0.cpu == $1.cpu && $0.pid < $1.pid) }.prefix(limit))
        let byMemory = Array(rows.sorted { $0.memoryBytes > $1.memoryBytes || ($0.memoryBytes == $1.memoryBytes && $0.pid < $1.pid) }.prefix(limit))
        return ProcessSample(topByCPU: byCPU, topByMemory: byMemory, processCount: current.count)
    }

    private func readAll() -> [pid_t: Snapshot] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride)))
        var result: [pid_t: Snapshot] = [:]
        result.reserveCapacity(count)
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        // `rusage_info_t` is `typedef void *`, so the `rusage_info_t *` parameter is really the
        // address of the struct to fill, not a pointer to a pointer. Bind the buffer accordingly.
        let bufferSize = MemoryLayout<rusage_info_v4>.size
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: MemoryLayout<rusage_info_v4>.alignment)
        defer { buffer.deallocate() }
        let rusageArg = buffer.bindMemory(to: rusage_info_t?.self, capacity: 1)
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            buffer.initializeMemory(as: UInt8.self, repeating: 0, count: bufferSize)
            guard proc_pid_rusage(pid, RUSAGE_INFO_V4, rusageArg) == 0 else { continue }
            let usage = buffer.load(as: rusage_info_v4.self)
            let ticks = usage.ri_user_time &+ usage.ri_system_time
            let nanos = UInt64(Double(ticks) * nanosPerTick)
            let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = nameLength > 0 ? String(cString: nameBuffer) : "pid \(pid)"
            result[pid] = Snapshot(cpuTimeNanos: nanos, memoryBytes: usage.ri_phys_footprint, name: name)
        }
        return result
    }
}
