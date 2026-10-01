//
//  LightClock.swift
//  climyte
//

import Foundation

/// The city's day from midnight to midnight, as fractions of a width.
///
/// For the Daylight widget, whose picture is the day itself: light from
/// sunrise to sunset, dark either side, and a line for now. A day is not
/// always 24 hours long, so the fractions are of the day the city's clocks
/// actually keep.
nonisolated enum LightClock {

    struct Day: Equatable {
        let sunrise: Date
        let sunset: Date

        /// 0 at the city's midnight, 1 at the next.
        let sunriseFraction: Double
        let sunsetFraction: Double
        let nowFraction: Double
    }

    /// Nil when the forecast has no sun times for the city's date at `date`,
    /// which is a polar day or night, or a forecast whose days have passed.
    static func day(at date: Date, in days: [SolarDay], timeZone: TimeZone) -> Day? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start),
              let solar = days.first(where: { calendar.isDate($0.sunrise, inSameDayAs: date) }) else {
            return nil
        }

        let length = end.timeIntervalSince(start)
        func fraction(_ instant: Date) -> Double {
            min(max(instant.timeIntervalSince(start) / length, 0), 1)
        }

        return Day(sunrise: solar.sunrise, sunset: solar.sunset,
                   sunriseFraction: fraction(solar.sunrise),
                   sunsetFraction: fraction(solar.sunset),
                   nowFraction: fraction(date))
    }
}
