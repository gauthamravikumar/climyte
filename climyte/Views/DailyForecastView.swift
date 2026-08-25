//
//  DailyForecastView.swift
//  climyte
//

import SwiftUI

struct DailyForecastView: View {
    let forecasts: [DailyForecast]
    let theme: WeatherTheme

    @ScaledMetric(relativeTo: .body) private var dayColumnWidth: CGFloat = 60
    @ScaledMetric(relativeTo: .body) private var tempColumnWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var barWidth: CGFloat = 120

    /// At accessibility sizes the scaled columns plus the bar are wider than
    /// the screen, which would push the whole layout off-viewport. Drop the
    /// bar and let the text size itself instead — the numbers still carry it.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isCompactLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("THIS WEEK")
                .font(.sectionHeading)
                .foregroundColor(theme.secondaryText)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(forecasts) { forecast in
                    row(for: forecast)
                    ThemeDivider(theme: theme)
                }
            }
        }
    }

    private func row(for forecast: DailyForecast) -> some View {
        HStack(spacing: 8) {
            Text(forecast.day)
                .font(.dayLabel)
                .foregroundColor(theme.primaryText)
                .lineLimit(1)
                .frame(minWidth: isCompactLayout ? nil : dayColumnWidth, alignment: .leading)

            Spacer(minLength: 8)

            Text(CurrentConditionsView.degrees(forecast.minTemp))
                .font(.dayLowTemperature)
                .foregroundColor(theme.secondaryText)
                .lineLimit(1)
                .frame(minWidth: isCompactLayout ? nil : tempColumnWidth, alignment: .trailing)

            if !isCompactLayout {
                Spacer(minLength: 8)

                TempBarView(
                    minTemp: forecast.minTemp,
                    maxTemp: forecast.maxTemp,
                    weekMin: weekMin,
                    weekMax: weekMax,
                    theme: theme
                )
                .frame(width: barWidth)

                Spacer(minLength: 8)
            }

            Text(CurrentConditionsView.degrees(forecast.maxTemp))
                .font(.dayHighTemperature)
                .foregroundColor(theme.primaryText)
                .lineLimit(1)
                .frame(minWidth: isCompactLayout ? nil : tempColumnWidth, alignment: .trailing)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(forecast.day), low \(Int(forecast.minTemp.rounded())), high \(Int(forecast.maxTemp.rounded())) degrees"
        )
    }

    private var weekMin: Double { forecasts.map(\.minTemp).min() ?? 0 }

    private var weekMax: Double { forecasts.map(\.maxTemp).max() ?? 100 }
}

/// Horizontal bar showing where a day's range sits within the week's range.
struct TempBarView: View {
    let minTemp: Double
    let maxTemp: Double
    let weekMin: Double
    let weekMax: Double
    let theme: WeatherTheme

    var body: some View {
        GeometryReader { geo in
            let range = max(weekMax - weekMin, 1)
            let left = CGFloat((minTemp - weekMin) / range) * geo.size.width
            let right = CGFloat((maxTemp - weekMin) / range) * geo.size.width
            let width = max(right - left, 3)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.dividerColor)
                    .frame(height: 4)

                Capsule()
                    .fill(theme.primaryText)
                    .frame(width: width, height: 4)
                    .offset(x: left)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 4)
        // The row already announces both temperatures.
        .accessibilityHidden(true)
    }
}
