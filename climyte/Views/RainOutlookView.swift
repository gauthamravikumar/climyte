//
//  RainOutlookView.swift
//  climyte
//

import SwiftUI

/// The next two hours of rain, as one bar per quarter hour.
///
/// Sits under the Rain row in the details block rather than standing as its own
/// section: the row already says "Rain", and two headings for one subject read
/// as two subjects.
///
/// Bars rather than a curve because a bar *is* a quarter hour. The model gives
/// eight buckets, and a line drawn through them would imply a continuity it
/// does not claim.
struct RainOutlookView: View {
    let outlook: RainOutlook
    let timeZone: TimeZone
    let theme: WeatherTheme

    /// True when the row above already carries the two-hour amount, so the line
    /// here need only say when — and, on a dry outlook, need not appear at all.
    let amountIsAlreadyShown: Bool

    @Environment(\.unitSystem) private var units
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Tall enough that a bar reads as a bar. At 46 the eight of them were
    /// wider than they were high and read as blocks.
    @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 68

    /// At accessibility sizes eight bars stop being readable and the sentence
    /// carries it alone — the same trade `DailyForecastView` makes with its
    /// columns.
    private var isCompactLayout: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let line = summary {
                line
                    .font(.detailRowCaption)
                    .foregroundColor(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !outlook.isDry && !isCompactLayout {
                bars
                axis
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenSummary)
    }

    // MARK: - The sentence

    /// Nil when the row above has already said everything there is to say,
    /// which is the dry outlook on a day that was never likely to rain.
    private var summary: Text? {
        guard !outlook.isDry else {
            return amountIsAlreadyShown ? nil : Text("None in the next 2 hours")
        }

        let timing = timingPhrase
        guard !amountIsAlreadyShown else { return Text(timing) }

        let total = units.precipitation(outlook.total)
        return Text("\(timing) · \(total) in the next 2 hours")
    }

    /// The first bucket is the quarter hour in progress, so rain in it is
    /// falling now rather than on its way.
    private var timingPhrase: String {
        guard let arrival = outlook.arrival else { return String(localized: "Expected") }
        guard arrival.time != outlook.steps.first?.time else {
            return String(localized: "Falling now")
        }

        let clock = arrival.time
            .formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
            .lowercased()
        return String(localized: "Starts \(clock)")
    }

    /// The bars carry nothing to a reader who cannot see them, so the spoken
    /// form says the shape in words.
    private var spokenSummary: Text {
        guard !outlook.isDry else { return Text("No rain in the next 2 hours") }

        let total = units.precipitation(outlook.total)
        let rate = units.precipitation(outlook.peakRatePerHour)
        return Text("\(timingPhrase). \(total) in the next 2 hours, up to \(rate) an hour.")
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
