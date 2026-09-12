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

    /// At accessibility sizes a label, a value and a caption cannot share one
    /// line. Squeezed onto one they lost the reading itself — "Humid" beside
    /// "dew point…" says nothing at all — so past that threshold the row
    /// becomes two lines and wraps rather than truncating.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            ForEach(WeatherDetails.build(for: weather, units: units)) { detail in
                // No spacing of its own: the row already carries 13 below it,
                // and adding to that pushed the strip away from the row it
                // belongs to.
                VStack(alignment: .leading, spacing: 0) {
                    row(detail)

                    // The next two hours belong to the Rain row rather than to
                    // a section of their own: the row already says "Rain", and
                    // two headings for one subject read as two subjects.
                    // Only when rain is actually on its way. "None" under a row
                    // that already gives the chance of rain read as a
                    // contradiction rather than a reassurance. Skipping the
                    // strip outright also keeps its padding from pushing the
                    // row away from its divider.
                    if detail.kind == .rain, let outlook = weather.rainOutlook, !outlook.isDry {
                        RainOutlookView(
                            outlook: outlook,
                            timeZone: weather.timeZone,
                            theme: theme,
                            amountIsAlreadyShown: WeatherDetails.rainRowLead(weather) == .nextTwoHours
                        )
                        .padding(.bottom, 13)
                    }
                }

                ThemeDivider(theme: theme)
            }
        }
    }

    @ViewBuilder
    private func row(_ detail: WeatherDetail) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                stackedRow(detail)
            } else {
                singleLineRow(detail)
            }
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // Spoken, the visible shorthand turns into "UV four mod" and
        // "eleven h fifteen m". The section headings already solved this by
        // carrying a separate spoken form; the rows now do the same.
        .accessibilityLabel(detail.spokenLabel)
    }

    private func singleLineRow(_ detail: WeatherDetail) -> some View {
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
    }

    private func stackedRow(_ detail: WeatherDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(detail.label)
                .font(.detailRowLabel)
                .foregroundColor(theme.secondaryText)

            Text(detail.value)
                .font(.detailRowValue)
                .foregroundColor(theme.primaryText)

            if let caption = detail.caption {
                Text(caption)
                    .font(.detailRowCaption)
                    .foregroundColor(theme.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
