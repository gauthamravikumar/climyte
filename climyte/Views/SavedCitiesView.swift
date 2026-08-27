//
//  SavedCitiesView.swift
//  climyte
//

import SwiftUI

/// The saved cities, shown when the search field is focused but empty.
///
/// Reuses the search surface rather than adding a management screen: this is
/// where someone already is when they want to switch or remove a city.
struct SavedCitiesView: View {
    let entries: [CityEntry]
    let selectedKey: String
    let theme: WeatherTheme
    let canRemove: Bool
    let onSelect: (CityEntry) -> Void
    let onDelete: (IndexSet) -> Void

    @Environment(\.unitSystem) private var units

    var body: some View {
        List {
            ForEach(entries) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    row(for: entry)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                .listRowSeparatorTint(theme.dividerColor)
                .deleteDisabled(!canRemove)
            }
            .onDelete(perform: onDelete)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxHeight: 420)
    }

    private func row(for entry: CityEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if entry.isCurrentLocation {
                Image(systemName: "location.fill")
                    .font(.system(size: 11))
                    .foregroundColor(theme.secondaryText)
                    .accessibilityHidden(true)
            }

            Text(entry.city.name)
                .font(.searchResultCity)
                .foregroundColor(entry.id == selectedKey ? theme.primaryText : theme.secondaryText)

            Spacer()

            if let weather = entry.weather {
                Text(units.temperature(weather.temperature))
                    .font(.searchResultCity)
                    .foregroundColor(theme.primaryText)
            }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        // Without this, rows with the location icon get their separator
        // indented past it while the others start at the edge.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(entry.id == selectedKey ? [.isSelected, .isButton] : .isButton)
    }
}
