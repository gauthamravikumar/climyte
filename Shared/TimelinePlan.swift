//
//  TimelinePlan.swift
//  climyte
//

import Foundation

/// Chooses the instants a widget timeline should re-render at.
///
/// Lives here rather than in the extension so it can be tested: the widget
/// target is not hosted by the test bundle, and the rule this encodes — that
/// the day/night inversion lands on the city's real sunset rather than on the
/// next whole hour — is the kind that is wrong quietly.
enum TimelinePlan {

    /// Hourly between `start` and `end`, plus the exact sunrise and sunset
    /// instants that fall inside the window.
    ///
    /// The sun times are the point. Hourly entries alone would leave a city
    /// that got dark at 6:10 rendered in the daytime palette until 7.
    ///
    /// `step` is shorter for the Daylight widget, whose line for now would
    /// otherwise jump a twenty-fourth of its width once an hour.
    static func renderDates(from start: Date, to end: Date, solarDays: [SolarDay],
                            step: TimeInterval = 3600) -> [Date] {
        guard start < end else { return [start] }

        var dates: [Date] = []

        var cursor = start
        while cursor < end {
            dates.append(cursor)
            cursor = cursor.addingTimeInterval(step)
        }

        for day in solarDays {
            for instant in [day.sunrise, day.sunset] where instant > start && instant < end {
                dates.append(instant)
            }
        }

        return dates.sorted()
    }
}
