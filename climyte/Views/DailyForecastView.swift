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
        VStack(alignment: .leading, spacing: 16) {
            SectionRule(label: "7d",
                        accessibilityLabel: "Next 7 days",
                        theme: theme)

            if isCompactLayout {
                compactList
            } else {
                chart
            }
        }
    }

    // MARK: - Ribbon

    /// The shape is drawn over the section rather than stacked above the row,
    /// so it can take its vertices from where the highs actually landed. The
    /// layout decides the spacing; the shape follows, at any type size and
    /// whatever the numbers happen to be.
    private var chart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Color.clear
                .frame(height: chartHeight)
                .accessibilityHidden(true)

            columns
        }
        .overlayPreferenceValue(HighLabelCentres.self) { anchors in
            GeometryReader { geo in
                ribbon(vertices: anchors.map { geo[$0].x }, width: geo.size.width)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The week as one shape: a band between the high and low lines. The
    /// numbers live below rather than on the curve, so they can't collide
    /// with it where the band narrows.
    ///
    /// `measured` is empty on the first pass, before the row has been laid
    /// out; an even grid stands in until the real positions arrive.
    @ViewBuilder
    private func ribbon(vertices measured: [CGFloat], width: CGFloat) -> some View {
        let vertices = measured.count == forecasts.count
            ? measured
            : xPositions(width: width)
        let rawHighs = forecasts.map { y(for: $0.maxTemp) }
        let rawLows = zip(rawHighs, forecasts.map { y(for: $0.minTemp) })
            .map { high, low in max(low, high + minimumBandThickness) }

        // The band reaches both margins like every other full-width element on
        // the page, while its vertices stay above the days they belong to. The
        // half-column at each end continues the slope of the segment beside it
        // — the week does not stop at Monday, and a flat shoulder would say it
        // did.
        let xs = [0] + vertices + [width]
        let highs = extendedToEdges(rawHighs, at: vertices, width: width)
        let lows = extendedToEdges(rawLows, at: vertices, width: width)

        ZStack {
            band(xs: xs, highs: highs, lows: lows)
                .fill(theme.dividerColor)

            line(xs: xs, ys: highs)
                .stroke(theme.primaryText, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))

            line(xs: xs, ys: lows)
                .stroke(theme.secondaryText, style: .init(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
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

    /// Continues the first and last segments out to the frame's edges.
    /// Clamped to the drawable band, so a steep end cannot push the shape out
    /// of its own frame and into the rule above it.
    private func extendedToEdges(_ ys: [CGFloat], at xs: [CGFloat], width: CGFloat) -> [CGFloat] {
        guard ys.count >= 2, xs.count == ys.count else { return ys }

        let inset: CGFloat = 3
        func clamped(_ y: CGFloat) -> CGFloat {
            min(max(y, inset), chartHeight - inset)
        }

        let leadSlope = (ys[1] - ys[0]) / max(xs[1] - xs[0], 1)
        let tailSlope = (ys[ys.count - 1] - ys[ys.count - 2]) / max(xs[xs.count - 1] - xs[xs.count - 2], 1)

        return [clamped(ys[0] - leadSlope * xs[0])]
            + ys
            + [clamped(ys[ys.count - 1] + tailSlope * (width - xs[xs.count - 1]))]
    }

    /// Vertices sit at the centre of each column below. The five middle days
    /// are centred in their columns, so those sit under their own numbers;
    /// the two end days are pulled out to the margins and read half a column
    /// wide of theirs, which is the price of the row starting and ending on
    /// the page's edges.
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

    /// The week spans margin to margin, like the ribbon above it and every
    /// other full-width element on the page: the first day hangs off the left
    /// edge, the last ends on the right one. Leading-aligning all seven left
    /// the last day sitting at the start of its own column, which put ~31pt of
    /// dead space on the right against 22pt on the left.
    private var columns: some View {
        WeekColumnsLayout {
            ForEach(forecasts) { forecast in
                VStack(alignment: .leading, spacing: 3) {
                    Text(units.temperature(forecast.maxTemp))
                        .font(.weekColumnHigh)
                        .foregroundColor(theme.primaryText)
                        .anchorPreference(key: HighLabelCentres.self, value: .center) { [$0] }

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
                .fixedSize()
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

/// Where each day's high sits on screen, so the ribbon can put its vertices
/// over the numbers they belong to instead of over an assumed grid.
private struct HighLabelCentres: PreferenceKey {
    static let defaultValue: [Anchor<CGPoint>] = []

    static func reduce(value: inout [Anchor<CGPoint>], nextValue: () -> [Anchor<CGPoint>]) {
        value.append(contentsOf: nextValue())
    }
}
