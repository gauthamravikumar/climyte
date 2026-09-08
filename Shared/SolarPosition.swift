//
//  SolarPosition.swift
//  climyte
//

import Foundation

/// Where the sun is in the city's own day.
///
/// Drives both the arc and the light on the background, so the two can never
/// disagree about where the sun is. Kept out of the views because it is the
/// kind of arithmetic that is wrong quietly — an off-by-one at midnight puts
/// the light on the wrong side of the screen and nothing crashes.
nonisolated enum SolarPosition {

    /// How far from sunrise to sunset, 0 to 1. Nil while the sun is down.
    static func daylightProgress(at date: Date, in days: [SolarDay]) -> Double? {
        guard let day = day(containing: date, in: days),
              date >= day.sunrise, date <= day.sunset else { return nil }

        let span = day.sunset.timeIntervalSince(day.sunrise)
        guard span > 0 else { return nil }
        return date.timeIntervalSince(day.sunrise) / span
    }

    /// How high the sun is, 0 at either horizon and 1 at the middle of the
    /// day. Zero whenever it is down.
    ///
    /// Not true astronomical elevation — a parabola through the day is close
    /// enough for deciding how warm and how strong the light should be, and it
    /// needs no location beyond the sun times we already have.
    static func elevation(at date: Date, in days: [SolarDay]) -> Double {
        guard let progress = daylightProgress(at: date, in: days) else { return 0 }
        return 1 - abs(progress - 0.5) * 2
    }

    /// Daylight still to come, or nil once the sun is down.
    static func remainingDaylight(at date: Date, in days: [SolarDay]) -> TimeInterval? {
        guard let day = day(containing: date, in: days),
              date >= day.sunrise, date <= day.sunset else { return nil }
        return day.sunset.timeIntervalSince(date)
    }

    /// How long the horizon keeps its warm band after the sun has gone.
    ///
    /// Roughly civil twilight. It matters because the theme inverts the moment
    /// the sun sets: without this the screen would go dark and the light would
    /// vanish in the same instant, which is not what dusk looks like and not
    /// what the design is for.
    static let twilight: TimeInterval = 32 * 60

    /// Where the light on the horizon is, and how strong, from 0 to 1 across
    /// the width of the screen. Nil in the middle of the night.
    static func horizonLight(at date: Date, in days: [SolarDay]) -> (position: Double, intensity: Double)? {
        if let progress = daylightProgress(at: date, in: days) {
            return (progress, 1)
        }
        guard let day = day(containing: date, in: days) else { return nil }

        // Just past sunset: the light stays in the west and fades.
        let sinceSunset = date.timeIntervalSince(day.sunset)
        if sinceSunset >= 0, sinceSunset < twilight {
            return (1, 1 - sinceSunset / twilight)
        }

        // Just before sunrise: it gathers in the east.
        let untilSunrise = day.sunrise.timeIntervalSince(date)
        if untilSunrise > 0, untilSunrise < twilight {
            return (0, 1 - untilSunrise / twilight)
        }
        return nil
    }

    /// The day `date` falls in, so an evening and the following morning are
    /// measured against their own sun times rather than one shared pair.
    static func day(containing date: Date, in days: [SolarDay]) -> SolarDay? {
        days.last { $0.sunrise <= date } ?? days.first
    }
}
