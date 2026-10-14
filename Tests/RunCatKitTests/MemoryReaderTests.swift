import Testing
@testable import RunCatKit

@Suite struct MemoryReaderTests {
    @Test func liveSampleIsConsistent() throws {
        let reader = MemoryReader()
        let sample = try #require(reader.sample())
        #expect(sample.totalBytes == UInt64(sysctlInt("hw.memsize") ?? 0))
        #expect(sample.totalBytes > 0)
        #expect(sample.usedBytes > 0)
        #expect(sample.usedBytes <= sample.totalBytes)
        #expect(sample.usedBytes == sample.appBytes + sample.wiredBytes + sample.compressedBytes)
        #expect((0...1).contains(sample.usedFraction))
        #expect((0...1).contains(sample.pressure))
        #expect(sample.swapUsedBytes <= sample.swapTotalBytes)
        #expect([.normal, .warning, .critical].contains(sample.pressureLevel))
    }

    @Test func pressureLevelRawValuesMatchKernel() {
        #expect(MemorySample.PressureLevel(rawValue: 1) == .normal)
        #expect(MemorySample.PressureLevel(rawValue: 2) == .warning)
        #expect(MemorySample.PressureLevel(rawValue: 4) == .critical)
        #expect(MemorySample.PressureLevel(rawValue: 3) == nil)
    }
}
