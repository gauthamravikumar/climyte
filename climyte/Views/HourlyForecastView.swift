//
//  HourlyForecastView.swift
//  climyte
//

import SwiftUI

struct HourlyForecastView: View {
    let hours: [HourlyForecast]
    let theme: WeatherTheme

    /// Scales with Dynamic Type so larger labels don't collide with each other.
    @ScaledMetric(relativeTo: .caption) private var columnWidth: CGFloat = 65

    private let chartHeight: CGFloat = 45
    private let chartPadding: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HOURLY")
                .font(.sectionHeading)
                .foregroundColor(theme.secondaryText)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 12) {
                    chart
                    labels
                }
            }
        }
    }

    private var chart: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                for (index, hour) in hours.enumerated() {
                    let point = CGPoint(x: x(at: index), y: y(for: hour.temperature))
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            .stroke(theme.secondaryText.opacity(0.3), lineWidth: 1.5)

            ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                Circle()
                    .fill(theme.primaryText)
                    .frame(width: 5, height: 5)
                    .position(x: x(at: index), y: y(for: hour.temperature))
            }
        }
        .frame(width: CGFloat(hours.count) * columnWidth, height: chartHeight)
        // The line and dots restate the numbers below them.
        .accessibilityHidden(true)
    }

    private var labels: some View {
        HStack(spacing: 0) {
            ForEach(hours) { hour in
                VStack(spacing: 6) {
                    Text(CurrentConditionsView.degrees(hour.temperature))
                        .font(.hourTemperature)
                        .foregroundColor(theme.primaryText)

                    Text(hour.time)
                        .font(.hourLabel)
                        .foregroundColor(theme.secondaryText)
                }
                .frame(width: columnWidth)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(hour.time), \(Int(hour.temperature.rounded())) degrees")
            }
        }
    }

    // MARK: - Geometry

    private var minTemp: Double { hours.map(\.temperature).min() ?? 0 }

    private var tempRange: Double { max((hours.map(\.temperature).max() ?? 1) - minTemp, 1) }

    private func x(at index: Int) -> CGFloat {
        CGFloat(index) * columnWidth + (columnWidth / 2)
    }

    private func y(for temperature: Double) -> CGFloat {
        let relative = (temperature - minTemp) / tempRange
        return chartHeight - chartPadding - CGFloat(relative) * (chartHeight - 2 * chartPadding)
    }
}
