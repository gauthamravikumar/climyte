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
                        .foregroundColor(theme.primaryText)

                    Text(hour.time)
                        .font(.hourLabel)
                        .foregroundColor(theme.secondaryText)
                }
                // Leading, not centre: centred text sets each column's left
                // edge from how wide the text happens to be, so the hour and
                // its temperature didn't line up with each other and the
                // whole strip shifted when a reading gained a digit.
                .frame(width: columnWidth, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(hour.time), \(units.temperatureValue(hour.temperature)) degrees")
            }
        }
    }
}
