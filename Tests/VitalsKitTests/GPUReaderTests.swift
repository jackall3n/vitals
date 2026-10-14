import Testing
@testable import VitalsKit

@Suite struct GPUReaderTests {
    @Test func parsesPerformanceStatistics() {
        let stats: [String: Any] = [
            "Device Utilization %": 31,
            "Renderer Utilization %": 28,
            "Tiler Utilization %": 7,
            "Alloc system memory": 4_430_872_576,
        ]
        let sample = GPUReader.parse(stats)
        #expect(sample.utilization == 0.31)
        #expect(sample.rendererUtilization == 0.28)
        #expect(sample.tilerUtilization == 0.07)
        #expect(sample.allocatedBytes == 4_430_872_576)
    }

    @Test func clampsOutOfRangeValues() {
        #expect(GPUReader.parse(["Device Utilization %": 140]).utilization == 1)
        #expect(GPUReader.parse(["Device Utilization %": -5]).utilization == 0)
        #expect(GPUReader.parse([:]).utilization == 0)
    }

    @Test func liveSampleIsWithinBounds() throws {
        let sample = try #require(GPUReader().sample(), "Apple silicon always exposes an IOAccelerator")
        #expect((0...1).contains(sample.utilization))
        #expect((0...1).contains(sample.rendererUtilization))
        #expect((0...1).contains(sample.tilerUtilization))
    }
}
