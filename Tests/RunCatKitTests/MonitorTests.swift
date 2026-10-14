import Foundation
import Testing
@testable import RunCatKit

@Suite @MainActor struct MonitorTests {
    @Test func synchronousSamplesPopulateSnapshotAndHistories() async throws {
        let monitor = Monitor(interval: 1)
        #expect(!monitor.isRunning)
        #expect(monitor.histories.cpuLevels.count == monitor.topology.levels.count)

        monitor.sampleNow() // primes the delta-based readers
        #expect(monitor.snapshot.memory != nil)
        #expect(monitor.snapshot.gpu != nil)
        #expect(monitor.snapshot.cpu == nil)

        try await Task.sleep(for: .milliseconds(150))
        monitor.sampleNow()
        let cpu = try #require(monitor.snapshot.cpu)
        #expect((0...1).contains(cpu.total))
        #expect(monitor.snapshot.network != nil)
        #expect(monitor.snapshot.disk != nil)
        #expect(monitor.snapshot.processes?.topByCPU.count == 5)
        #expect(monitor.histories.cpuTotal.points.count == 1)
        #expect(monitor.histories.memoryPressure.points.count == 2)
        #expect(monitor.histories.gpu.points.count == 2)
        #expect(monitor.histories.cpuLevels.allSatisfy { $0.points.count == 1 })
    }

    @Test func keepsLastGoodValueWhenAReaderReturnsNil() async throws {
        let monitor = Monitor(interval: 1)
        monitor.sampleNow()
        try await Task.sleep(for: .milliseconds(50))
        monitor.sampleNow()
        let before = try #require(monitor.snapshot.cpu)
        // A third immediate sample can legitimately produce a zero-delta CPU sample, but never nil
        // once primed, so the merged snapshot must still carry a CPU value.
        monitor.sampleNow()
        #expect(monitor.snapshot.cpu != nil)
        #expect(monitor.snapshot.cpu?.perCore.count == before.perCore.count)
    }

    @Test func timerDeliversSamplesOnMainActor() async throws {
        let monitor = Monitor(interval: 1)
        monitor.start()
        #expect(monitor.isRunning)
        monitor.start() // idempotent
        try await Task.sleep(for: .milliseconds(1400))
        monitor.stop()
        #expect(!monitor.isRunning)
        #expect(monitor.histories.memoryPressure.points.count >= 2, "expected the immediate tick plus one more")
        #expect(monitor.snapshot.cpu != nil)
    }
}
