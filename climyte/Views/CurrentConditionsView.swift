//
//  CurrentConditionsView.swift
//  climyte
//

import SwiftUI

struct CurrentConditionsView: View {
    /// SF Symbols sized in points ignore Dynamic Type entirely: at
    /// accessibility sizes this was a speck beside text three times its
    /// height. @ScaledMetric keeps the drawn size at the default setting
    /// and grows it with everything else.
    @ScaledMetric(relativeTo: .title) private var locationIcon: CGFloat = 14

    let weather: CityWeather
    let theme: WeatherTheme
    let isUsingCurrentLocation: Bool

    @Environment(\.unitSystem) private var units

    /// Separates the city from the clock, and grows with the type ramp.
    @ScaledMetric(relativeTo: .title) private var headerGap: CGFloat = 12

    /// The hero's point size, tracking Dynamic Type the same way the font
    /// does, so the optical correction below scales with the glyphs it is
    /// correcting.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 100

    /// The reading's own left side bearing, measured for the digits actually
    /// on screen rather than assumed — Manrope's vary by 3pt across the ten.
    private var heroBearing: CGFloat {
        Font.Manrope.regular.leftSideBearing(
            of: units.temperature(weather.temperature), size: heroSize
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
                .padding(.bottom, 14)
            temperature
            summary
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 8) {
                if isUsingCurrentLocation {
                    Image(systemName: "location.fill")
                        .font(.system(size: locationIcon))
                        .foregroundColor(theme.primaryText.opacity(0.8))
                        .accessibilityLabel("Current location")
                }

                Text(weather.city.name)
                    .font(.cityName)
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    // The page's identifier outranks the clock beside it. With
                    // the priority the other way round, a long name truncated
                    // to "Bandar Se…" at accessibility sizes so a secondary
                    // reading could stay full size.
                    .layoutPriority(1)
            }

            // Scales with the text, so the gap never collapses to the width of
            // a letter space and read as one run: "Sydney5:40 pm".
            Spacer(minLength: headerGap)

            // Re-renders every minute so the city's local time stays honest.
            TimelineView(.everyMinute) { context in
                Text(Self.localTime(at: context.date, in: weather.timeZone))
                    .font(.localTime)
                    .foregroundColor(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // accessibilityLabel replaces a Text's content, so naming
                    // the element here without a value would leave the time
                    // itself unspoken — the one thing this element exists for.
                    .accessibilityLabel("Local time in \(weather.city.name)")
                    .accessibilityValue(Self.localTime(at: context.date, in: weather.timeZone))
            }
        }
    }

    private var temperature: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(units.temperature(weather.temperature))
                .font(.temperatureHero)
                .foregroundColor(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // A numeral this large carries a lot of empty line box above
                // and below it. Trimmed on the glyph itself rather than on the
                // block, so it stops at the range line instead of reaching
                // through to the condition underneath.
                .padding(.vertical, -10)
                // And a lot of empty box to its left. Pulled off so the ink
                // starts on the same edge as everything else on the page,
                // whichever digit happens to lead.
                .padding(.leading, -heroBearing)

            // The day's range, set as a span rather than two labelled values.
            // Only the reading itself carries a degree sign; these inherit it.
            Text("\(units.temperatureValue(weather.minTemp))  ·  \(units.temperatureValue(weather.maxTemp))")
                .font(.temperatureRange)
                .foregroundColor(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // Terse on screen, explicit to VoiceOver — the visual shorthand
        // shouldn't cost a screen-reader user the meaning.
        .accessibilityLabel(
            """
            \(units.temperatureValue(weather.temperature)) degrees, \
            low \(units.temperatureValue(weather.minTemp)), \
            high \(units.temperatureValue(weather.maxTemp))
            """
        )
    }

    private var summary: some View {
        Text(Self.summary(
            condition: weather.condition.description,
            actual: units.temperatureValue(weather.temperature),
            apparent: units.temperatureValue(weather.feelsLike)
        ))
        .font(.conditionSummary)
        .foregroundColor(theme.secondaryText)
    }

    /// The condition line, mentioning apparent temperature only when it
    /// differs from the reading — "feels like 61°" directly under a 61°
    /// reading is noise, and it made the line easy to stop reading.
    ///
    /// Both values arrive already converted, so the difference is expressed in
    /// whatever unit is on screen; a 2°C gap is a 4°F gap and must not be
    /// reported as "2° warmer" to a Fahrenheit reader.
    static func summary(condition: String, actual: Int, apparent: Int) -> String {
        let difference = apparent - actual

        if difference > 0 {
            return String(localized: "\(condition) · feels \(difference)° warmer")
        } else if difference < 0 {
            return String(localized: "\(condition) · feels \(-difference)° cooler")
        } else {
            return condition
        }
    }

    // MARK: - Formatting

    /// Renders `date` in the city's timezone. `.shortened` picks up the
    /// reader's locale, so 12h/24h follows their device rather than a
    /// hardcoded format that dropped am/pm entirely.
    static func localTime(at date: Date, in timeZone: TimeZone) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)
        )
    }

    /// Kept for callers that only have an offset, such as tests covering the
    /// fallback used when a response carries no zone name.
    static func localTime(at date: Date, utcOffsetSeconds: Int) -> String {
        localTime(at: date, in: TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current)
    }
}
