import Foundation

public struct HistoryPoint: Equatable, Sendable, Identifiable {
    public var time: Date
    public var value: Double
    public var id: Date { time }

    public init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }
}

/// A time-bounded series of samples. Keeps at most `retention` seconds of history.
public struct History: Equatable, Sendable {
    public private(set) var points: [HistoryPoint] = []
    public let retention: TimeInterval

    public init(retention: TimeInterval = 300) {
        self.retention = retention
    }

    public mutating func append(_ value: Double, at time: Date = Date()) {
        points.append(HistoryPoint(time: time, value: value))
        let cutoff = time.addingTimeInterval(-retention)
        if let firstKept = points.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            points.removeFirst(firstKept)
        }
    }

    /// Points within the last `seconds`, relative to the newest point (or `now` if given).
    public func window(_ seconds: TimeInterval, now: Date? = nil) -> [HistoryPoint] {
        guard let reference = now ?? points.last?.time else { return [] }
        let cutoff = reference.addingTimeInterval(-seconds)
        guard let start = points.firstIndex(where: { $0.time >= cutoff }) else { return [] }
        return Array(points[start...])
    }

    public var latest: Double? { points.last?.value }
    public var isEmpty: Bool { points.isEmpty }

    public func max(in seconds: TimeInterval) -> Double {
        window(seconds).map(\.value).max() ?? 0
    }
}
