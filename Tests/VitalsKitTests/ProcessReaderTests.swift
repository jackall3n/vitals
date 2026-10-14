import Foundation
import Testing
@testable import VitalsKit

@Suite struct ProcessReaderTests {
    typealias Snap = ProcessReader.Snapshot

    @Test func ranksByCPUAndMemory() {
        let before: [pid_t: Snap] = [
            1: Snap(cpuTimeNanos: 0, memoryBytes: 100, name: "a"),
            2: Snap(cpuTimeNanos: 0, memoryBytes: 300, name: "b"),
            3: Snap(cpuTimeNanos: 0, memoryBytes: 200, name: "c"),
        ]
        let after: [pid_t: Snap] = [
            1: Snap(cpuTimeNanos: 500_000_000, memoryBytes: 100, name: "a"),   // 50% over 1s
            2: Snap(cpuTimeNanos: 1_000_000_000, memoryBytes: 300, name: "b"), // 100%
            3: Snap(cpuTimeNanos: 0, memoryBytes: 200, name: "c"),
            4: Snap(cpuTimeNanos: 9_000_000_000, memoryBytes: 50, name: "new"), // no previous → 0
        ]
        let sample = ProcessReader.compute(previous: before, current: after, interval: 1, limit: 2)
        #expect(sample.processCount == 4)
        #expect(sample.topByCPU.map(\.name) == ["b", "a"])
        #expect(sample.topByCPU[0].cpu == 1)
        #expect(sample.topByCPU[1].cpu == 0.5)
        #expect(sample.topByMemory.map(\.name) == ["b", "c"])
    }

    @Test func liveSampleIncludesSelfWithRealisticCPU() async throws {
        let reader = ProcessReader(limit: 2000)
        #expect(reader.sample() == nil)

        // Burn one core for a short while so our own pid has a measurable load.
        let stop = Date().addingTimeInterval(0.3)
        let burner = Thread { while Date() < stop { _ = sin(1.0) } }
        burner.start()
        try await Task.sleep(for: .milliseconds(320))

        let sample = try #require(reader.sample())
        let me = try #require(sample.topByCPU.first { $0.pid == getpid() })
        #expect(me.cpu > 0.5, "spun a core for ~100% of the interval, got \(me.cpu)")
        #expect(me.cpu < 3, "timebase conversion must not inflate CPU time")
        #expect(me.memoryBytes > 1 << 20)
        #expect(!me.name.isEmpty)
        #expect(sample.processCount > 50)
    }
}
