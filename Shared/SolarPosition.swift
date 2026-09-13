//
//  SolarPosition.swift
//  climyte
//

import Foundation

/// Where the sun is in the city's own day.
///
/// Drives the sun arc, and decides day from night when a forecast's own sun
/// times have run out. Kept out of the views because it is the kind of
/// arithmetic that is wrong quietly — an off-by-one at midnight puts the sun
/// on the wrong side of the arc and nothing crashes.
nonisolated enum SolarPosition {

    /// How far from sunrise to sunset, 0 to 1. Nil while the sun is down.
    static func daylightProgress(at date: Date, in days: [SolarDay]) -> Double? {
        guard let day = day(containing: date, in: days),
              date >= day.sunrise, date <= day.sunset else { return nil }

        let span = day.sunset.timeIntervalSince(day.sunrise)
        guard span > 0 else { return nil }
        return date.timeIntervalSince(day.sunrise) / span
    }

    /// Daylight still to come, or nil once the sun is down.
    static func remainingDaylight(at date: Date, in days: [SolarDay]) -> TimeInterval? {
        guard let day = day(containing: date, in: days),
              date >= day.sunrise, date <= day.sunset else { return nil }
        return day.sunset.timeIntervalSince(date)
    }

    /// Whether the sun is above the horizon here at `date`, from the sun itself
    /// rather than from a forecast's sun times.
    ///
    /// Those cover only the forecast's own days. A saved forecast old enough
    /// for every one of them to have passed left the page judging today
    /// against a sunset a week gone, and dark all day. This needs nothing but
    /// where the city is.
    static func isSunUp(at date: Date, latitude: Double, longitude: Double) -> Bool {
        altitude(at: date, latitude: latitude, longitude: longitude) > -0.833
    }

    /// The sun's height above the horizon in degrees, by NOAA's method: the
    /// equation of time and the declination for the moment, then the hour
    /// angle from true solar time. Good to a fraction of a degree, which is a
    /// minute or two either side of sunrise and sunset.
    private static func altitude(at date: Date, latitude: Double, longitude: Double) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let minutes = date.timeIntervalSince(calendar.startOfDay(for: date)) / 60
        let g = 2 * .pi / 365 * (day - 1 + (minutes / 60 - 12) / 24)

        let equationOfTime = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g)
                                       - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let hourAngle = ((minutes + equationOfTime + 4 * longitude) / 4 - 180) * .pi / 180

        let phi = latitude * .pi / 180
        let delta = declination(fractionalYear: g)
        let cosZenith = sin(phi) * sin(delta) + cos(phi) * cos(delta) * cos(hourAngle)
        return 90 - acos(min(max(cosZenith, -1), 1)) * 180 / .pi
    }

    /// How far north or south of the equator the sun stands, in radians, at a
    /// point in the year given as an angle. Spencer's series: good to a few
    /// hundredths of a degree.
    private static func declination(fractionalYear g: Double) -> Double {
        0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g)
            - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g)
            - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
    }

    /// The day `date` falls in, so an evening and the following morning are
    /// measured against their own sun times rather than one shared pair.
    static func day(containing date: Date, in days: [SolarDay]) -> SolarDay? {
        days.last { $0.sunrise <= date } ?? days.first
    }
}
