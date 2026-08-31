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

    /// A cap that grows with the reader's type size.
    ///
    /// Pinned at 420pt it sliced a row horizontally through the middle of
    /// its letters at accessibility sizes while half the screen sat empty —
    /// which reads as a rendering fault rather than as a scroll edge. The
    /// enclosing stack still bounds this to the space actually available.
    @ScaledMetric(relativeTo: .body) private var maxListHeight: CGFloat = 420
    let canRemove: Bool
    let onSelect: (CityEntry) -> Void
    let onDelete: (IndexSet) -> Void

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
        .frame(maxHeight: maxListHeight)
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
                // Per row, not from the environment: each city in this list
                // may be shown in different units.
                Text(entry.city.unitSystem.temperature(weather.temperature))
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
        // The arrow is hidden from VoiceOver and the row combines its
        // children, so without this the located entry and a saved city of the
        // same name are indistinguishable when read aloud.
        .accessibilityLabel(entry.isCurrentLocation
                            ? Text("\(entry.city.name), current location")
                            : Text(entry.city.name))
        .accessibilityAddTraits(entry.id == selectedKey ? [.isSelected, .isButton] : .isButton)
    }
}
