//
//  SearchResultsView.swift
//  climyte
//

import SwiftUI

struct SearchResultsView: View {
    let results: [GeocodingResult]
    let theme: WeatherTheme
    let onSelect: (GeocodingResult) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if results.isEmpty {
                noMatches
            } else {
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
                .frame(maxHeight: 400)
            }
        }
        .padding(.horizontal, 4)
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
    }

    private func region(for result: GeocodingResult) -> String {
        [result.admin1, result.country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var noMatches: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 24))
                .foregroundColor(theme.secondaryText)
                .accessibilityHidden(true)

            Text("No matches")
                .font(.searchResultCity)
                .foregroundColor(theme.secondaryText)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}
