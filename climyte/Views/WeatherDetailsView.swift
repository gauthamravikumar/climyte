//
//  WeatherDetailsView.swift
//  climyte
//

import SwiftUI

/// The details section: one row per thing worth saying.
///
/// Rows rather than a tile grid, because the number of details varies with the
/// weather and a grid would orphan a cell on odd counts. Rows also let a value
/// carry its full phrase — "9.5 mm over 7h" does not fit a tile.
struct WeatherDetailsView: View {
    let weather: CityWeather
    let theme: WeatherTheme

    @Environment(\.unitSystem) private var units

    var body: some View {
        VStack(spacing: 0) {
            ForEach(WeatherDetails.build(for: weather, units: units)) { detail in
                row(detail)
                ThemeDivider(theme: theme)
            }
        }
    }

    private func row(_ detail: WeatherDetail) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(detail.label)
                .font(.detailRowLabel)
                .foregroundColor(theme.secondaryText)

            Spacer(minLength: 12)

            Text(detail.value)
                .font(.detailRowValue)
                .foregroundColor(theme.primaryText)

            if let caption = detail.caption {
                Text(caption)
                    .font(.detailRowCaption)
                    .foregroundColor(theme.secondaryText)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}
