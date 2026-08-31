//
//  ReadingAge.swift
//  climyte
//

import Foundation

/// How old a cached reading is, and when that is old enough to admit to.
///
/// The app and the widget both show readings they did not just fetch, and both
/// have to decide when a temperature has stopped describing the weather
/// outside. Keeping the threshold in one place stops the two from disagreeing
/// about it.
enum ReadingAge {

    /// Past this, a reading is presented as old rather than as current.
    ///
    /// Three hours: the widget plans two hours ahead and retries a fetch at
    /// the end of each run, so anything older than that means several attempts
    /// have failed rather than that the schedule is simply between fetches.
    static let staleAfter: TimeInterval = 3 * 3600

    static func isStale(_ age: TimeInterval?) -> Bool {
        (age ?? 0) >= staleAfter
    }

    /// The age in the shortest form that still says it: "4h", "2d".
    ///
    /// Nil when the reading is current, so callers render nothing at all
    /// rather than a reassuring "0h". Deliberately not the app's full
    /// sentence — beside a temperature there is no room for one, and a bare
    /// duration there reads as the age of the number it sits next to.
    static func short(_ age: TimeInterval?) -> String? {
        guard let age, isStale(age) else { return nil }

        let hours = Int(age / 3600)
        return hours < 24
            ? String(localized: "\(hours)h")
            : String(localized: "\(hours / 24)d")
    }
}
