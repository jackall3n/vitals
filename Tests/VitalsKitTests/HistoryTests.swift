import Foundation
import Testing
@testable import VitalsKit

@Suite struct HistoryTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func appendsInOrderAndReportsLatest() {
        var h = History(retention: 300)
        #expect(h.isEmpty)
        #expect(h.latest == nil)
        h.append(0.1, at: t0)
        h.append(0.2, at: t0.addingTimeInterval(1))
        #expect(h.points.map(\.value) == [0.1, 0.2])
        #expect(h.latest == 0.2)
    }

    @Test func dropsPointsOlderThanRetention() {
        var h = History(retention: 10)
        for i in 0..<20 { h.append(Double(i), at: t0.addingTimeInterval(Double(i))) }
        // Newest is t0+19; cutoff is t0+9, inclusive.
        #expect(h.points.first?.value == 9)
        #expect(h.points.count == 11)
    }

    @Test func windowReturnsRecentPointsRelativeToNewest() {
        var h = History(retention: 300)
        for i in 0..<100 { h.append(Double(i), at: t0.addingTimeInterval(Double(i))) }
        let last60 = h.window(60)
        #expect(last60.count == 61)
        #expect(last60.first?.value == 39)
        #expect(last60.last?.value == 99)
        #expect(h.window(5).map(\.value) == [94, 95, 96, 97, 98, 99])
        #expect(h.window(1000).count == 100)
    }

    @Test func windowRelativeToExplicitNow() {
        var h = History(retention: 300)
        for i in 0..<10 { h.append(Double(i), at: t0.addingTimeInterval(Double(i))) }
        #expect(h.window(2, now: t0.addingTimeInterval(20)).isEmpty)
        #expect(h.window(15, now: t0.addingTimeInterval(20)).map(\.value) == [5, 6, 7, 8, 9])
    }

    @Test func maxInWindow() {
        var h = History(retention: 300)
        h.append(0.9, at: t0)
        h.append(0.2, at: t0.addingTimeInterval(100))
        h.append(0.4, at: t0.addingTimeInterval(101))
        #expect(h.max(in: 5) == 0.4)
        #expect(h.max(in: 200) == 0.9)
        #expect(History().max(in: 60) == 0)
    }
}
