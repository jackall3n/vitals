import Foundation
import Testing
@testable import RunCatKit

@Suite struct NetworkReaderTests {
    @Test func computesRatesFromCounterDeltas() {
        let before = NetworkReader.Counters(received: 1000, sent: 500)
        let after = NetworkReader.Counters(received: 3000, sent: 1500)
        let sample = NetworkReader.compute(previous: before, current: after, interval: 2)
        #expect(sample.downloadRate == 1000)
        #expect(sample.uploadRate == 500)
        #expect(sample.totalReceivedBytes == 3000)
        #expect(sample.totalSentBytes == 1500)
    }

    @Test func counterResetYieldsZeroNotNegative() {
        let before = NetworkReader.Counters(received: 5000, sent: 5000)
        let after = NetworkReader.Counters(received: 10, sent: 10)
        let sample = NetworkReader.compute(previous: before, current: after, interval: 1)
        #expect(sample.downloadRate == 0)
        #expect(sample.uploadRate == 0)
    }

    @Test func liveSamplesAreNonNegative() async throws {
        let reader = NetworkReader()
        #expect(reader.sample() == nil)
        try await Task.sleep(for: .milliseconds(100))
        let sample = try #require(reader.sample())
        #expect(sample.downloadRate >= 0)
        #expect(sample.uploadRate >= 0)
        #expect(sample.totalReceivedBytes > 0)
    }
}
