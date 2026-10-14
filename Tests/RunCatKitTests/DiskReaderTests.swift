import Foundation
import Testing
@testable import RunCatKit

@Suite struct DiskReaderTests {
    @Test func computesRatesAndCapacity() {
        let before = DiskReader.Counters(read: 100, write: 200)
        let after = DiskReader.Counters(read: 1100, write: 2200)
        let sample = DiskReader.compute(previous: before, current: after, interval: 1, total: 1000, free: 250)
        #expect(sample.readRate == 1000)
        #expect(sample.writeRate == 2000)
        #expect(sample.usedBytes == 750)
        #expect(sample.usedFraction == 0.75)
    }

    @Test func liveSampleIsConsistent() async throws {
        let reader = DiskReader()
        #expect(reader.sample() == nil)
        try await Task.sleep(for: .milliseconds(100))
        let sample = try #require(reader.sample())
        #expect(sample.totalBytes > 0)
        #expect(sample.freeBytes <= sample.totalBytes)
        #expect(sample.readRate >= 0)
        #expect(sample.writeRate >= 0)
        #expect(sample.totalReadBytes > 0, "block storage statistics should be readable without privileges")
    }
}
