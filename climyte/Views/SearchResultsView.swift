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

    /// A cap that grows with the reader's type size.
    ///
    /// Pinned at 400pt it sliced a row horizontally through the middle of
    /// its letters at accessibility sizes while half the screen sat empty —
    /// which reads as a rendering fault rather than as a scroll edge. The
    /// enclosing stack still bounds this to the space actually available.
    @ScaledMetric(relativeTo: .body) private var maxListHeight: CGFloat = 400
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
                        row(for: result)
                    }

                    ThemeDivider(theme: theme)
                }
            }
        }
        .frame(maxHeight: maxListHeight)
    }

    private func row(for result: GeocodingResult) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(result.name)
                .font(.searchResultCity)
                .foregroundColor(theme.primaryText)

            Spacer()

            Text(region(for: result))
                .font(.searchResultRegion)
                .foregroundColor(theme.secondaryText)
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func region(for result: GeocodingResult) -> String {
        [result.admin1, result.country]
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
