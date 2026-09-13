//
//  SearchResultsView.swift
//  climyte
//

import SwiftUI

struct SearchResultsView: View {
    /// SF Symbols sized in points ignore Dynamic Type entirely: at
    /// accessibility sizes this was a speck beside text three times its
    /// height. @ScaledMetric keeps the drawn size at the default setting
    /// and grows it with everything else.
    @ScaledMetric(relativeTo: .title2) private var stateIcon: CGFloat = 24

    let state: SearchState
    let theme: WeatherTheme

    let onSelect: (GeocodingResult) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch state {
            case .idle, .loading:
                // Nothing yet. Staying blank avoids flashing "No matches" at
                // someone who is still typing.
                Color.clear.frame(height: 1)

            case .results(let results):
                list(results)

            case .empty:
                message(icon: "mappin.slash", title: "No matches")

            case .failed(let reason):
                failure(reason)
            }
        }
        .padding(.horizontal, 4)
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
            Text(result.name)
                .font(.searchResultCity)
                .foregroundColor(theme.primaryText)

            Spacer()

            Text(Self.region(for: result, among: results))
                .font(.searchResultRegion)
                .foregroundColor(theme.secondaryText)
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
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: stateIcon))
                .foregroundColor(theme.secondaryText)
                .accessibilityHidden(true)

            Text(reason)
                .font(.searchResultCity)
                .foregroundColor(theme.secondaryText)
                .multilineTextAlignment(.center)

            Button(action: onRetry) {
                Text("Try again")
                    .font(.searchResultRegion)
                    .foregroundColor(theme.primaryText)
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
    private func message(icon: String, title: LocalizedStringResource) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: stateIcon))
                .foregroundColor(theme.secondaryText)
                .accessibilityHidden(true)

            Text(title)
                .font(.searchResultCity)
                .foregroundColor(theme.secondaryText)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}
