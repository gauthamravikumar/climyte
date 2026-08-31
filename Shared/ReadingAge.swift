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

    /// Below this, a cached reading is new enough that fetching again would
    /// return the same numbers.
    static let refetchAfter: TimeInterval = 15 * 60

    /// Whether a reading of this age is worth going to the network for.
    ///
    /// The widget reloads for two quite different reasons and only one of them
    /// wants a fetch. Its own schedule comes round every couple of hours, by
    /// which point the reading genuinely is old. But the app also asks for a
    /// reload the moment it caches a reading of its own — and answering that
    /// with a fetch means the app and every placed widget each request the
    /// same city seconds apart, which is the opposite of what asking for the
    /// reload was for.
    ///
    /// No reading at all always needs one.
    static func needsRefetch(_ age: TimeInterval?) -> Bool {
        guard let age else { return true }
        return age >= refetchAfter
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
