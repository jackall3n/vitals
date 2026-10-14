import Testing
@testable import VitalsKit

@Suite struct CPUReaderTests {
    typealias Ticks = CPUReader.CoreTicks

    @Test func computesPerCoreAndLevelLoads() {
        let topology = CPUTopology(coreCount: 4, levels: [
            .init(name: "Performance", coreRange: 2..<4),
            .init(name: "Efficiency", coreRange: 0..<2),
        ])
        let before = [Ticks(user: 0, system: 0, idle: 100, nice: 0),
                      Ticks(user: 0, system: 0, idle: 100, nice: 0),
                      Ticks(user: 0, system: 0, idle: 100, nice: 0),
                      Ticks(user: 0, system: 0, idle: 100, nice: 0)]
        let after = [Ticks(user: 0, system: 0, idle: 200, nice: 0),       // idle
                     Ticks(user: 50, system: 0, idle: 150, nice: 0),      // 50%
                     Ticks(user: 100, system: 0, idle: 100, nice: 0),     // 100%
                     Ticks(user: 25, system: 25, idle: 150, nice: 0)]     // 50%
        let sample = CPUReader.compute(previous: before, current: after, topology: topology)
        #expect(sample.perCore == [0, 0.5, 1, 0.5])
        #expect(sample.total == 0.5)
        #expect(sample.levels.map(\.name) == ["Performance", "Efficiency"])
        #expect(sample.levels[0].load == 0.75)
        #expect(sample.levels[1].load == 0.25)
    }

    @Test func handlesCounterWraparound() {
        let before = [Ticks(user: UInt32.max - 10, system: 0, idle: 0, nice: 0)]
        let after = [Ticks(user: 10, system: 0, idle: 10, nice: 0)]
        let sample = CPUReader.compute(previous: before, current: after, topology: CPUTopology(coreCount: 1, levels: [.init(name: "All", coreRange: 0..<1)]))
        #expect(abs(sample.perCore[0] - 21.0 / 31.0) < 1e-9)
    }

    @Test func zeroDeltaIsZeroLoad() {
        let t = [Ticks(user: 5, system: 5, idle: 5, nice: 0)]
        let sample = CPUReader.compute(previous: t, current: t, topology: CPUTopology(coreCount: 1, levels: [.init(name: "All", coreRange: 0..<1)]))
        #expect(sample.total == 0)
        #expect(sample.perCore == [0])
    }

    @Test func liveTopologyCoversEveryCoreExactlyOnce() {
        let topology = CPUTopology.current()
        #expect(topology.coreCount == Int(sysctlInt("hw.logicalcpu") ?? -1))
        let covered = topology.levels.flatMap { Array($0.coreRange) }.sorted()
        #expect(covered == Array(0..<topology.coreCount))
        #expect(!topology.levels.isEmpty)
        #expect(topology.levels.allSatisfy { !$0.name.isEmpty })
    }

    @Test func liveSampleIsWithinBounds() async throws {
        let reader = CPUReader()
        #expect(reader.sample() == nil, "first call has no delta")
        try await Task.sleep(for: .milliseconds(200))
        let sample = try #require(reader.sample())
        #expect(sample.perCore.count == reader.topology.coreCount)
        #expect((0...1).contains(sample.total))
        #expect(sample.perCore.allSatisfy { (0...1).contains($0) })
        #expect(sample.levels.allSatisfy { (0...1).contains($0.load) })
    }

    @Test func sysctlHelpersReadKnownKeys() {
        #expect((sysctlInt("hw.ncpu") ?? 0) > 0)
        #expect((sysctlInt("hw.memsize") ?? 0) > 1 << 30)
        #expect(sysctlString("kern.ostype") == "Darwin")
        #expect(sysctlInt("no.such.key") == nil)
    }
}
