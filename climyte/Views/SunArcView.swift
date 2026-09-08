//
//  SunArcView.swift
//  climyte
//

import SwiftUI

/// The day's arc, with the sun on it.
///
/// Replaces the separate Sunrise and Sunset rows: two numbers you had to read
/// and subtract become one shape you glance at. It answers the question those
/// rows never did — how much of the day is left — and it shares its arithmetic
/// with the light on the background, so the two always agree.
struct SunArcView: View {
    let weather: CityWeather
    let theme: WeatherTheme

    @ScaledMetric(relativeTo: .caption) private var arcHeight: CGFloat = 58

    var body: some View {
        TimelineView(.everyMinute) { context in
            let days = weather.solarDays
            let progress = SolarPosition.daylightProgress(at: context.date, in: days)

            VStack(alignment: .leading, spacing: 6) {
                SectionRule(label: "Sun",
                            accessibilityLabel: "Today's daylight",
                            theme: theme)
                    .padding(.bottom, 10)

                arc(progress: progress)
                    .frame(height: arcHeight)

                HStack(alignment: .firstTextBaseline) {
                    Text(weather.sunriseFormatted)
                    Spacer(minLength: 12)
                    Text(trailingLabel(at: context.date, days: days))
                }
                .font(.hourLabel)
                .foregroundColor(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel(at: context.date, days: days))
        }
    }

    private func arc(progress: Double?) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let baseline = geometry.size.height - 8
            let peak: CGFloat = 6
            let control = peak - (baseline - peak)

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: baseline))
                    path.addLine(to: CGPoint(x: width, y: baseline))
                }
                .stroke(theme.dividerColor, lineWidth: 1)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: baseline))
                    path.addQuadCurve(to: CGPoint(x: width, y: baseline),
                                      control: CGPoint(x: width / 2, y: control))
                }
                .stroke(theme.secondaryText.opacity(progress == nil ? 0.3 : 0.55),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                if let progress {
                    let y = quadratic(progress, from: baseline, control: control)
                    Circle()
                        .fill(theme.primaryText)
                        .frame(width: 9, height: 9)
                        .position(x: width * progress, y: y)
                } else {
                    // Below the horizon: set, or not yet risen.
                    Circle()
                        .strokeBorder(theme.secondaryText, lineWidth: 1.5)
                        .frame(width: 9, height: 9)
                        .position(x: hasRisenToday ? width : 0, y: baseline + 6)
                }
            }
        }
    }

    /// The curve the stroke follows, so the sun sits exactly on the line
    /// rather than near it.
    private func quadratic(_ t: Double, from baseline: CGFloat, control: CGFloat) -> CGFloat {
        let inverse = 1 - t
        return inverse * inverse * baseline + 2 * inverse * t * control + t * t * baseline
    }

    private var hasRisenToday: Bool {
        guard let day = SolarPosition.day(containing: Date(), in: weather.solarDays) else { return false }
        return Date() > day.sunrise
    }

    /// While the sun is up this counts down, which is the thing worth knowing.
    /// Once it is down there is nothing to count, so it names sunset instead.
    private func trailingLabel(at date: Date, days: [SolarDay]) -> String {
        guard let remaining = SolarPosition.remainingDaylight(at: date, in: days) else {
            return weather.sunsetFormatted
        }
        let minutes = (remaining / 60).toInt()
        guard minutes >= 60 else { return String(localized: "\(minutes) min of light left") }
        return String(localized: "\(minutes / 60)h \(minutes % 60)m of light left")
    }

    private func spokenLabel(at date: Date, days: [SolarDay]) -> String {
        guard let remaining = SolarPosition.remainingDaylight(at: date, in: days) else {
            return String(localized: "The sun is down. Sunrise \(weather.sunriseFormatted), sunset \(weather.sunsetFormatted).")
        }
        let minutes = (remaining / 60).toInt()
        return String(localized: "\(minutes / 60) hours \(minutes % 60) minutes of daylight left, sunset \(weather.sunsetFormatted)")
    }
}
