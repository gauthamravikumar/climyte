//
//  DaylightWidgetView.swift
//  climyteWidget
//

import SwiftUI
import WidgetKit

// MARK: - Daylight

/// The city's day from midnight to midnight, as one slim bar under the
/// reading: solid for the hours of light, faint for the night, and a ring at
/// now.
///
/// A first version made the bar the whole widget, full bleed, and on a phone
/// it read as a flag: a large empty white slab with the reading squeezed into
/// a dark corner. At this size the idea stays and the widget reads as a
/// Climyte page, turning dark at night like the app.
struct DaylightWidgetView: View {
    let entry: WeatherEntry

    @Environment(\.widgetRenderingMode) private var renderingMode
    private var isAccented: Bool { renderingMode == .accented }

    private var primary: Color { isAccented ? .primary : entry.theme.primaryText }
    private var secondary: Color { isAccented ? .secondary : entry.theme.secondaryText }

    private let tube: CGFloat = 12
    private let bead: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.city?.name ?? "Climyte")
                .font(.widgetCity)
                .foregroundStyle(primary)
                .lineLimit(1)

            // The reading at poster scale, and what qualifies it beside it.
            HStack(alignment: .top, spacing: 12) {
                Text(entry.weather.map { entry.units.temperature($0.temperature) } ?? "--")
                    .font(.widgetHero)
                    .tracking(-4)
                    .foregroundStyle(primary)
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    // A numeral this size carries a deep line box above and
                    // below it, and the widget has no room for it: the reading
                    // shrank to fit instead. Trimmed on the glyph, as the
                    // app's own hero is.
                    .padding(.vertical, -14)

                Spacer(minLength: 0)

                if let weather = entry.weather {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(weather.conditionDescription(at: entry.date))
                            .font(.widgetHeadline)
                            .foregroundStyle(primary)
                        if let low = weather.minTemp, let high = weather.maxTemp {
                            Text("\(entry.units.temperatureValue(low)) · \(entry.units.temperatureValue(high))")
                                .font(.widgetDetail)
                                .foregroundStyle(secondary)
                        }
                        if let line = countdown(weather) {
                            Text(line)
                                .font(.widgetDetail)
                                .foregroundStyle(secondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 148, alignment: .leading)
                    .padding(.top, 10)
                }
            }

            Spacer(minLength: 4)

            if let weather = entry.weather,
               let day = LightClock.day(at: entry.date, in: weather.solarDays, timeZone: weather.timeZone) {
                bar(day, timeZone: weather.timeZone)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .widgetURL(entry.city.flatMap(CityLink.url))
    }

    private func summary(_ weather: CityWeather) -> String {
        let condition = weather.conditionDescription(at: entry.date)
        guard let low = weather.minTemp, let high = weather.maxTemp else { return condition }
        return "\(condition) · \(entry.units.temperatureValue(low)) · \(entry.units.temperatureValue(high))"
    }

    /// The bar and the two sun times beneath it, each under its own end of
    /// the light. A short winter day has no room for both side by side, so
    /// there sunset sits under sunrise.
    private func bar(_ day: LightClock.Day, timeZone: TimeZone) -> some View {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)
        let sunrise = day.sunrise.formatted(style).lowercased()
        let sunset = day.sunset.formatted(style).lowercased()

        return GeometryReader { geo in
            let width = geo.size.width
            let start = width * day.sunriseFraction
            let end = width * day.sunsetFraction
            let now = min(max(width * day.nowFraction, bead / 2), width - bead / 2)
            let roomy = end - start >= 110

            ZStack(alignment: .topLeading) {
                GlassGroove(isNight: entry.isNight, isAccented: isAccented)
                    .frame(height: tube)

                GlassFill(isNight: entry.isNight, isAccented: isAccented)
                    .frame(width: max(end - start, tube), height: tube)
                    .offset(x: start)

                GlassBead(isNight: entry.isNight, isAccented: isAccented)
                    .frame(width: bead, height: bead)
                    .offset(x: now - bead / 2, y: (tube - bead) / 2)

                Group {
                    if roomy {
                        Text(sunrise)
                            .fixedSize()
                            .offset(x: start, y: tube + 6)
                        Text(sunset)
                            .fixedSize()
                            .frame(width: end, alignment: .trailing)
                            .offset(y: tube + 6)
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sunrise)
                            Text(sunset)
                        }
                        .fixedSize()
                        .offset(x: start, y: tube + 6)
                    }
                }
                .font(.widgetCaption)
                .foregroundStyle(secondary)
            }
            // Keeps the tinted bead's cut-out to the bar, not the widget.
            .compositingGroup()
        }
        .frame(height: tube + 30)
    }

    /// While the sun is up, the light left; after dark, the wait for the
    /// next sunrise. The same wording as the app's sun arc.
    private func countdown(_ weather: CityWeather) -> String? {
        if let left = SolarPosition.remainingDaylight(at: entry.date, in: weather.solarDays), left > 0 {
            let minutes = (left / 60).toInt(.up)
            return minutes < 60
                ? String(localized: "\(minutes) min of light left")
                : String(localized: "\(minutes / 60)h \(minutes % 60)m of light left")
        }
        if let next = weather.solarDays.first(where: { $0.sunrise > entry.date }) {
            let minutes = (next.sunrise.timeIntervalSince(entry.date) / 60).toInt(.up)
            return minutes < 60
                ? String(localized: "\(minutes) min to sunrise")
                : String(localized: "\(minutes / 60)h \(minutes % 60)m to sunrise")
        }
        return nil
    }

    private var spokenLabel: String {
        let name = entry.city?.name ?? "Climyte"
        guard let weather = entry.weather else { return String(localized: "\(name), no reading yet") }
        let reading = entry.units.temperatureValue(weather.temperature)
        let base = String(localized: "\(name), \(reading) degrees, \(weather.conditionDescription(at: entry.date)).")
        let sun = String(localized: "Sunrise \(weather.sunriseFormatted), sunset \(weather.sunsetFormatted).")
        guard let line = countdown(weather) else { return "\(base) \(sun)" }
        return "\(base) \(line). \(sun)"
    }
}
