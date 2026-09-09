//
//  SavedCitiesView.swift
//  climyte
//

import SwiftUI
import UIKit

/// The saved cities, shown when the search field is focused but empty.
///
/// Reuses the search surface rather than adding a management screen: this is
/// where someone already is when they want to switch or remove a city.
struct SavedCitiesView: View {
    /// SF Symbols sized in points ignore Dynamic Type entirely: at
    /// accessibility sizes this was a speck beside text three times its
    /// height. @ScaledMetric keeps the drawn size at the default setting
    /// and grows it with everything else.
    @ScaledMetric(relativeTo: .headline) private var locationIcon: CGFloat = 11

    let entries: [CityEntry]
    let selectedKey: String
    let theme: WeatherTheme

    let canRemove: Bool
    /// Shown as a row rather than an alert: this is where someone looks when
    /// their own city is missing from the list.
    let locationAccessRefused: Bool
    let onSelect: (CityEntry) -> Void
    let onDelete: (IndexSet) -> Void
    let onMove: (IndexSet, Int) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            if locationAccessRefused {
                locationNotice
            }

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
            .onMove(perform: onMove)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var locationNotice: some View {
        Button {
            guard let settings = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(settings)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "location.slash")
                    .font(.system(size: locationIcon))
                    .foregroundColor(theme.secondaryText)
                    .accessibilityHidden(true)

                Text("Location is off for Climyte")
                    .font(.searchResultCity)
                    .foregroundColor(theme.secondaryText)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        .listRowSeparatorTint(theme.dividerColor)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .deleteDisabled(true)
        .moveDisabled(true)
        .accessibilityHint("Opens Settings")
    }

    private func row(for entry: CityEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if entry.isCurrentLocation {
                Image(systemName: "location.fill")
                    .font(.system(size: locationIcon))
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
        // Swipe-to-delete is the only way to remove a city, and combining the
        // row's children can swallow the action the list would otherwise
        // expose. Stated explicitly, it also stops being a hidden gesture.
        .accessibilityAction(named: Text("Delete \(entry.city.name)")) {
            guard canRemove, let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
            onDelete(IndexSet(integer: index))
        }
        // A drag is invisible to VoiceOver and unreachable by switch control,
        // so the same reordering is offered as two named actions.
        .accessibilityAction(named: Text("Move up")) { move(entry, by: -1) }
        .accessibilityAction(named: Text("Move down")) { move(entry, by: 1) }
    }

    /// `onMove`'s destination is an insertion point, not an index: moving down
    /// has to clear the row being vacated, which is why the two directions
    /// aren't symmetrical.
    private func move(_ entry: CityEntry, by offset: Int) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let target = index + offset
        guard entries.indices.contains(target) else { return }
        onMove(IndexSet(integer: index), offset < 0 ? target : target + 1)
    }
}
