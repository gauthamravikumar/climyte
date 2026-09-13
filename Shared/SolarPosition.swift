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

    /// How long dusk lasts at this latitude on this date: from sunset until
    /// the sun is six degrees below the horizon, where civil twilight ends.
    ///
    /// The horizon keeps its warm band for exactly this long, because the
    /// theme inverts the moment the sun sets — without it the screen would go
    /// dark and the light vanish in the same instant. How long that is depends
    /// on how steeply the sun sets: nearly straight down at the equator, about
    /// 21 minutes; on a long slant towards the poles, far longer. A fixed half
    /// hour was right only in between — it outlived Singapore's dusk by ten
    /// minutes and was gone an hour early in Oslo in June.
    ///
    /// Nil when the sun never sinks six degrees at all — Reykjavík in June —
    /// so dusk runs straight into dawn.
    static func civilTwilight(latitude: Double, on date: Date) -> TimeInterval? {
        guard let sunset = hourAngle(of: -0.833, latitude: latitude, on: date),
              let dusk = hourAngle(of: -6, latitude: latitude, on: date) else { return nil }
        return (dusk - sunset) / (2 * .pi) * 86_400
    }

    /// Where the light on the horizon is, and how strong, from 0 to 1 across
    /// the width of the screen. Nil between the end of dusk and the start of
    /// dawn.
    static func horizonLight(at date: Date, in days: [SolarDay],
                             latitude: Double) -> (position: Double, intensity: Double)? {
        if let progress = daylightProgress(at: date, in: days) {
            return (progress, 1)
        }
        guard let night = night(containing: date, in: days),
              date >= night.sunset, date < night.sunrise else { return nil }

        // A night the sun never sinks six degrees into never gets dark, so it
        // keeps its glow: drifting from west to east as the sun passes under
        // the pole, dimmest at the deepest point and only as dim as the sky.
        guard let dusk = civilTwilight(latitude: latitude, on: night.sunset) else {
            let span = night.sunrise.timeIntervalSince(night.sunset)
            let progress = min(max(date.timeIntervalSince(night.sunset) / span, 0), 1)
            let floor = deepestGlow(latitude: latitude, on: night.sunset)
            return (1 - progress, floor + (1 - floor) * abs(progress - 0.5) * 2)
        }

        // Just past sunset: the light stays in the west and fades.
        let sinceSunset = date.timeIntervalSince(night.sunset)
        if sinceSunset < dusk {
            return (1, 1 - sinceSunset / dusk)
        }

        // Before sunrise it gathers in the east, over that morning's own dawn.
        let dawn = civilTwilight(latitude: latitude, on: night.sunrise) ?? dusk
        let untilSunrise = night.sunrise.timeIntervalSince(date)
        if untilSunrise < dawn {
            return (0, 1 - untilSunrise / dawn)
        }
        return nil
    }

    /// The night `date` falls in, from the sunset before it to the sunrise
    /// after — each from its own day. Measuring the morning against the
    /// previous day's sunrise, which had already passed, left every dawn after
    /// the first one in the data without a glow.
    ///
    /// Where the data runs out on one side, the other day's time stands in a
    /// day away: sun times move by minutes from one day to the next.
    static func night(containing date: Date, in days: [SolarDay]) -> (sunset: Date, sunrise: Date)? {
        let before = days.last { $0.sunset <= date }
        let after = days.first { $0.sunrise > date }
        switch (before, after) {
        case let (before?, after?): return (before.sunset, after.sunrise)
        case let (before?, nil): return (before.sunset, before.sunrise.addingTimeInterval(86_400))
        case let (nil, after?): return (after.sunset.addingTimeInterval(-86_400), after.sunrise)
        case (nil, nil): return nil
        }
    }

    /// How bright the glow stays at the deepest point of a night that never
    /// gets dark: in proportion to where the sun then is between the horizon
    /// and the six degrees below it where dusk would have ended. At that point
    /// it stands |latitude + declination| − 90 degrees up.
    private static func deepestGlow(latitude: Double, on date: Date) -> Double {
        let lowest = abs(latitude + declination(on: date) * 180 / .pi) - 90
        return min(max((lowest + 6) / (6 - 0.833), 0), 1)
    }

    /// The hour angle, in radians, at which the sun stands `altitude` degrees
    /// up on this date. Nil if it never sinks that low.
    private static func hourAngle(of altitude: Double, latitude: Double, on date: Date) -> Double? {
        let phi = latitude * .pi / 180
        let delta = declination(on: date)
        let cosine = (sin(altitude * .pi / 180) - sin(phi) * sin(delta)) / (cos(phi) * cos(delta))
        guard cosine >= -1 else { return nil }
        return acos(min(cosine, 1))
    }

    /// How far north or south of the equator the sun stands on this date, in
    /// radians. Spencer's series: good to a few hundredths of a degree, which
    /// is a minute or so of dusk.
    private static func declination(on date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let g = 2 * .pi / 365 * (day - 1)
        return 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g)
            - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g)
            - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
    }

    /// The day `date` falls in, so an evening and the following morning are
    /// measured against their own sun times rather than one shared pair.
    static func day(containing date: Date, in days: [SolarDay]) -> SolarDay? {
        days.last { $0.sunrise <= date } ?? days.first
    }
}
