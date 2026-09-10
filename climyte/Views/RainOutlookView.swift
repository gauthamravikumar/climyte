//
//  RainOutlookView.swift
//  climyte
//

import SwiftUI

/// Rain over the next two hours, as one bar per quarter hour.
///
/// Bars rather than a curve because a bar *is* a quarter hour: the model gives
/// eight buckets, and a line drawn through them would imply a continuity it
/// does not claim.
struct RainOutlookView: View {
    let cityName: String
    let outlook: RainOutlook
    let timeZone: TimeZone
    let theme: WeatherTheme

    @Environment(\.unitSystem) private var units
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Tall enough that a bar reads as a bar. At 46 the eight of them were
    /// wider than they were high and read as blocks.
    @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 68

    /// At accessibility sizes eight bars stop being readable and the sentences
    /// carry it alone — the same trade `DailyForecastView` makes with its
    /// columns.
    private var isCompactLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionRule(label: "Rain",
                        accessibilityLabel: "Rain in the next 2 hours",
                        theme: theme)

            if outlook.isDry {
                Text("None in the next 2 hours")
                    .font(.conditionSummary)
                    .foregroundColor(theme.secondaryText)
            } else {
                wet
            }
        }
    }

    private var wet: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                leadLine
                    .font(.conditionSummary)
                    .foregroundColor(theme.primaryText)

                amountLine
                    .font(.detailRowCaption)
                    .foregroundColor(theme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)

            if !isCompactLayout {
                bars
                axis
            }
        }
    }

    // MARK: - The sentences

    private var leadLine: Text {
        guard let arrival = outlook.arrival else {
            return Text("Rain in the next 2 hours")
        }

        // A first step already wet means it is falling now, not that it is
        // about to: the first bucket is the quarter hour in progress.
        guard arrival.time != outlook.steps.first?.time else {
            return Text("Raining in \(cityName) now")
        }

        let clock = arrival.time
            .formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
            .lowercased()
        return Text("Rain reaching \(cityName) at \(clock)")
    }

    /// How much, and how hard. The total answers "will I get wet"; the rate
    /// answers "how badly", and they are different questions — two hours of
    /// drizzle and ten minutes of downpour can total the same.
    private var amountLine: Text {
        let total = units.precipitation(outlook.total)
        let rate = units.precipitation(outlook.peakRatePerHour)
        return Text("\(total) total · up to \(rate) an hour")
    }

    // MARK: - The bars

    private var bars: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(outlook.steps.enumerated()), id: \.offset) { _, step in
                let fraction = min(step.millimetres / outlook.scale, 1)

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    // Height already carries the amount; the weight reinforces
                    // it, so a heavy quarter-hour reads before it is measured.
                    .fill(theme.primaryText.opacity(0.3 + 0.7 * fraction))
                    // A dry step keeps a stub rather than vanishing, so the row
                    // reads as a timeline with gaps in it rather than as bars
                    // floating unanchored.
                    .frame(height: max(chartHeight * fraction, 3))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: chartHeight, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private var axis: some View {
        HStack {
            Text("now")
            Spacer(minLength: 8)
            Text("+1h")
            Spacer(minLength: 8)
            Text("+2h")
        }
        .font(.hourLabel)
        .foregroundColor(theme.secondaryText)
        .accessibilityHidden(true)
    }
}
