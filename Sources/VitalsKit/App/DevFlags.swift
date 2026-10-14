import Foundation

/// Launch-argument switches used by the development hooks in `AppDelegate`.
enum DevFlags {
    /// `-Screenshot <dir>`: views are rendered offline with `ImageRenderer`, which takes a single
    /// snapshot, so behaviours that rely on later state updates or animations are bypassed.
    static let screenshotMode = UserDefaults.standard.string(forKey: "Screenshot") != nil
}
