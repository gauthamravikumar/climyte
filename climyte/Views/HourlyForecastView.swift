//
//  HourlyForecastView.swift
//  climyte
//

import SwiftUI

struct HourlyForecastView: View {
    let hours: [HourlyForecast]
    let theme: WeatherTheme

    @Environment(\.unitSystem) private var units

    /// Scales with Dynamic Type so larger labels don't collide with each other.
    ///
    /// Narrower than it was: the column used to be wide enough to hold a
    /// sparkline vertex at its centre, and once the chart went the extra width
    /// was just a gap between the hours.
    @ScaledMetric(relativeTo: .caption) private var columnWidth: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionRule(label: "24h",
                        accessibilityLabel: "Next 24 hours",
                        theme: theme)

            ScrollView(.horizontal, showsIndicators: false) {
                labels
            }
        }
    }

    private var labels: some View {
        HStack(spacing: 0) {
            ForEach(hours) { hour in
                VStack(alignment: .leading, spacing: 6) {
                    Text(units.temperature(hour.temperature))
                        .font(.hourTemperature)
                        .foregroundStyle(theme.primaryText)

                    Text(hour.time)
                        .font(.hourLabel)
                        .foregroundStyle(theme.secondaryText)

                    // Only on the hours where rain is likely, and no line at
                    // all on a dry day. A dry hour keeps an empty line so the
                    // wet ones beside it stay on the same baseline.
                    if showsRain {
                        Text(Self.isLikely(hour.rainChance)
                             ? WeatherDetails.percentage(hour.rainChance ?? 0) : " ")
                            .font(.hourRain)
                            .foregroundStyle(theme.primaryText)
                    }
                }
                // Leading, not centre: centred text sets each column's left
                // edge from how wide the text happens to be, so the hour and
                // its temperature didn't line up with each other and the
                // whole strip shifted when a reading gained a digit.
                .frame(width: columnWidth, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spokenLabel(for: hour))
            }
        }
    }

    private var showsRain: Bool {
        hours.contains { Self.isLikely($0.rainChance) }
    }

    /// The Rain row's own threshold, so the strip and the row agree about
    /// which chances are worth a mention.
    static func isLikely(_ chance: Int?) -> Bool {
        (chance ?? 0) >= WeatherDetails.Threshold.rainChance
    }

    private func spokenLabel(for hour: HourlyForecast) -> String {
        let reading = String(localized: "\(hour.time), \(units.temperatureValue(hour.temperature)) degrees")
        guard Self.isLikely(hour.rainChance) else { return reading }
        return String(localized: "\(reading), \(WeatherDetails.percentage(hour.rainChance ?? 0)) chance of rain")
    }
}
