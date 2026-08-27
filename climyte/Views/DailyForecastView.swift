//
//  DailyForecastView.swift
//  climyte
//

import SwiftUI

struct DailyForecastView: View {
    let forecasts: [DailyForecast]
    let theme: WeatherTheme

    @Environment(\.unitSystem) private var units

    /// At accessibility sizes seven columns cannot fit across the screen, so
    /// the chart is dropped and the week falls back to a plain list.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isCompactLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    private let chartHeight: CGFloat = 68

    /// A day whose high and low are close would otherwise collapse the band
    /// into what looks like one thick line.
    private let minimumBandThickness: CGFloat = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionRule(label: "7d",
                        accessibilityLabel: "Next 7 days",
                        theme: theme)

            if isCompactLayout {
                compactList
            } else {
                ribbon
                columns
            }
        }
    }

    // MARK: - Ribbon

    /// The week as one shape: a band between the high and low lines. The
    /// numbers live below rather than on the curve, so they can't collide
    /// with it where the band narrows.
    private var ribbon: some View {
        GeometryReader { geo in
            let xs = xPositions(width: geo.size.width)
            let highs = forecasts.map { y(for: $0.maxTemp) }
            let lows = zip(highs, forecasts.map { y(for: $0.minTemp) })
                .map { high, low in max(low, high + minimumBandThickness) }

            ZStack {
                band(xs: xs, highs: highs, lows: lows)
                    .fill(theme.dividerColor)

                line(xs: xs, ys: highs)
                    .stroke(theme.primaryText, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))

                line(xs: xs, ys: lows)
                    .stroke(theme.secondaryText, style: .init(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: chartHeight)
        .accessibilityHidden(true)
    }

    private func band(xs: [CGFloat], highs: [CGFloat], lows: [CGFloat]) -> Path {
        Path { path in
            guard let firstX = xs.first else { return }
            path.move(to: CGPoint(x: firstX, y: highs[0]))
            for index in xs.indices {
                path.addLine(to: CGPoint(x: xs[index], y: highs[index]))
            }
            for index in xs.indices.reversed() {
                path.addLine(to: CGPoint(x: xs[index], y: lows[index]))
            }
            path.closeSubpath()
        }
    }

    private func line(xs: [CGFloat], ys: [CGFloat]) -> Path {
        Path { path in
            guard let firstX = xs.first else { return }
            path.move(to: CGPoint(x: firstX, y: ys[0]))
            for index in xs.indices.dropFirst() {
                path.addLine(to: CGPoint(x: xs[index], y: ys[index]))
            }
        }
    }

    /// Vertices sit at the centre of each column below, so the shape and the
    /// numbers line up.
    private func xPositions(width: CGFloat) -> [CGFloat] {
        let step = width / CGFloat(max(forecasts.count, 1))
        return forecasts.indices.map { step * (CGFloat($0) + 0.5) }
    }

    private func y(for temperature: Double) -> CGFloat {
        let inset: CGFloat = 3
        let usable = chartHeight - inset * 2 - minimumBandThickness
        let range = max(weekMax - weekMin, 1)
        let fraction = (temperature - weekMin) / range
        return inset + usable * CGFloat(1 - fraction)
    }

    // MARK: - Numbers

    private var columns: some View {
        HStack(spacing: 0) {
            ForEach(forecasts) { forecast in
                VStack(spacing: 3) {
                    Text(units.temperature(forecast.maxTemp))
                        .font(.weekColumnHigh)
                        .foregroundColor(theme.primaryText)

                    Text(units.temperature(forecast.minTemp))
                        .font(.weekColumnLow)
                        .foregroundColor(theme.secondaryText)

                    Text(forecast.day)
                        .font(.weekColumnDay)
                        .foregroundColor(theme.secondaryText)
                        .padding(.top, 2)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(forecast.day), low \(units.temperatureValue(forecast.minTemp)), high \(units.temperatureValue(forecast.maxTemp)) degrees"
                )
            }
        }
    }

    // MARK: - Accessibility-size fallback

    private var compactList: some View {
        VStack(spacing: 0) {
            ForEach(forecasts) { forecast in
                HStack(spacing: 8) {
                    Text(forecast.day)
                        .font(.dayLabel)
                        .foregroundColor(theme.primaryText)

                    Spacer(minLength: 8)

                    Text(units.temperature(forecast.minTemp))
                        .font(.dayLowTemperature)
                        .foregroundColor(theme.secondaryText)

                    Text(units.temperature(forecast.maxTemp))
                        .font(.dayHighTemperature)
                        .foregroundColor(theme.primaryText)
                }
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(forecast.day), low \(units.temperatureValue(forecast.minTemp)), high \(units.temperatureValue(forecast.maxTemp)) degrees"
                )

                ThemeDivider(theme: theme)
            }
        }
    }

    private var weekMin: Double { forecasts.map(\.minTemp).min() ?? 0 }

    private var weekMax: Double { forecasts.map(\.maxTemp).max() ?? 100 }
}
