//
//  SearchResultsView.swift
//  climyte
//

import SwiftUI

struct SearchResultsView: View {
    let state: SearchState
    let theme: WeatherTheme

    let onSelect: (GeocodingResult) -> Void
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            switch state {
            case .idle:
                Color.clear.frame(height: 1)

            case .loading:
                placeholders

            case .results(let results):
                list(results)

            case .empty:
                message("No matches")

            case .failed(let reason):
                failure(reason)
            }
        }
        .padding(.horizontal, 4)
    }

    /// Rows in the shape of results, while the search is out.
    ///
    /// A blank screen for that second gave no sign anything was happening.
    /// Shapes rather than words, so nothing flashes "No matches" at someone
    /// still typing.
    private var placeholders: some View {
        VStack(spacing: 0) {
            ForEach(Array(zip([110, 80, 96] as [CGFloat], [170, 150, 130] as [CGFloat])), id: \.0) { name, region in
                HStack {
                    RoundedRectangle(cornerRadius: 6).frame(width: name, height: 18)
                    Spacer()
                    RoundedRectangle(cornerRadius: 6).frame(width: region, height: 14)
                }
                .padding(.vertical, 22)

                ThemeDivider(theme: theme)
            }
        }
        .foregroundStyle(theme.dividerColor)
        // Holds still when the reader has asked for less motion.
        .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { rows, opacity in
            rows.opacity(opacity)
        } animation: { _ in
            .easeInOut(duration: 0.8)
        }
        .accessibilityElement()
        .accessibilityLabel("Searching")
    }

    private func list(_ results: [GeocodingResult]) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(results) { result in
                    Button {
                        onSelect(result)
                    } label: {
                        row(for: result, among: results)
                    }

                    ThemeDivider(theme: theme)
                }
            }
        }
    }

    private func row(for result: GeocodingResult, among results: [GeocodingResult]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            // A Button centres a label's wrapped lines, so a long name such as
            // "Seattle International Raceway" broke into two centred lines.
            // The name reads from the left and the region from the right.
            Text(result.name)
                .font(.searchResultCity)
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.leading)

            Spacer()

            Text(Self.region(for: result, among: results))
                .font(.searchResultRegion)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Where a result is, as short as still tells it apart.
    ///
    /// Two places can share a name, a state and a country — Oslo, Minnesota
    /// is two towns in two counties — and "Minnesota, United States" on both
    /// rows left the reader guessing which one they were adding. The county
    /// goes in front only then; anywhere else it is noise.
    static func region(for result: GeocodingResult, among results: [GeocodingResult]) -> String {
        let hasNamesake = results.contains {
            $0.id != result.id && $0.name == result.name
                && $0.admin1 == result.admin1 && $0.country == result.country
        }
        let county = hasNamesake && result.admin2 != result.admin1 ? result.admin2 : nil

        return [county, result.admin1, result.country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func failure(_ reason: String) -> some View {
        VStack(spacing: 12) {
            Text(reason)
                .font(.searchResultCity)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)

            Button(action: onRetry) {
                Text("Try again")
                    .font(.searchResultRegion)
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .overlay(Capsule().stroke(theme.dividerColor, lineWidth: 1))
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    /// `title` is a LocalizedStringResource, not a String. Passed as a String
    /// it bound to Text's non-localizing overload, so "No matches" never
    /// reached the catalog — Xcode's extractor could not see it either.
    private func message(_ title: LocalizedStringResource) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.searchResultCity)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}
