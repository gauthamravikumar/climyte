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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @ScaledMetric(relativeTo: .headline) private var removeIcon: CGFloat = 20

    /// Removing and reordering, made visible. Swiping a row was the only way
    /// to remove a city, and nothing on screen said so; holding to drag was
    /// as hidden.
    @State private var isEditing = false

    /// The row whose remove mark was tapped, asking once before it goes.
    @State private var pendingRemoval: String?

    var body: some View {
        VStack(spacing: 0) {
            // Nothing to edit with one city: it can't be removed, and there is
            // nothing to reorder it against.
            if entries.count > 1 {
                editButton
            }

            List {
                if locationAccessRefused {
                    locationNotice
                }

                ForEach(entries) { entry in
                    Group {
                        if isEditing {
                            editingRow(for: entry)
                        } else {
                            Button {
                                onSelect(entry)
                            } label: {
                                row(for: entry)
                            }
                            // A swipe action rather than the list's own delete.
                            // With `onDelete` on the list, turning Edit on slid
                            // the system's red delete circles onto the rows as
                            // they faded into the editing ones; and its swipe
                            // button was the one red thing in the app.
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if canRemove {
                                    Button(role: .destructive) {
                                        remove(entry)
                                    } label: {
                                        Text("Remove")
                                    }
                                    .tint(theme.swipeFill)
                                }
                            }
                        }
                    }
                    // The page's own ground rather than clear: a row lifted to
                    // be dragged keeps its background, and a clear one let the
                    // system's light-grey card show through on the night theme.
                    .listRowBackground(theme.background)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                    .listRowSeparatorTint(theme.dividerColor)
                }
                .onMove(perform: onMove)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            // Drag handles appear only while editing; holding to drag still
            // works either way.
            .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        }
        .onChange(of: entries.count) { _, count in
            pendingRemoval = nil
            if count < 2 { isEditing = false }
        }
    }

    private var editButton: some View {
        HStack {
            Spacer()
            Button(isEditing ? "Done" : "Edit") {
                withAnimation(reduceMotion ? nil : .default) {
                    isEditing.toggle()
                    pendingRemoval = nil
                }
            }
            .font(.searchCancel)
            .foregroundStyle(theme.primaryText)
            .lineLimit(1)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 4)
    }

    /// A row while editing: a remove mark, the name, and a confirmation in
    /// place of the reading once the mark is tapped.
    private func editingRow(for entry: CityEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if canRemove {
                Button {
                    withAnimation(reduceMotion ? nil : .default) {
                        pendingRemoval = pendingRemoval == entry.id ? nil : entry.id
                    }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: removeIcon))
                        .foregroundStyle(theme.primaryText)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove \(entry.city.name)"))
            }

            Text(entry.city.name)
                .font(.searchResultCity)
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if pendingRemoval == entry.id {
                Button {
                    remove(entry)
                } label: {
                    Text("Remove")
                        .font(.searchCancel)
                        .foregroundStyle(theme.background)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(theme.primaryText))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
    }

    private func remove(_ entry: CityEntry) {
        guard canRemove, let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        pendingRemoval = nil
        withAnimation(reduceMotion ? nil : .default) {
            onDelete(IndexSet(integer: index))
        }
    }

    private var locationNotice: some View {
        Button {
            guard let settings = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(settings)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "location.slash")
                    .font(.system(size: locationIcon))
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityHidden(true)

                Text("Location is off for Climyte")
                    .font(.searchResultCity)
                    .foregroundStyle(theme.secondaryText)
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
        // And to the trailing margin, where the list otherwise stops short of
        // the rule under the search results.
        .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
        .deleteDisabled(true)
        .moveDisabled(true)
        .accessibilityHint("Opens Settings")
    }

    private func row(for entry: CityEntry) -> some View {
        // At accessibility sizes the reading beside the name left it too
        // little room, and "Melbourne" broke across two lines mid-word. There
        // the reading goes under the name instead.
        let stacked = typeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if entry.isCurrentLocation {
                    Image(systemName: "location.fill")
                        .font(.system(size: locationIcon))
                        .foregroundStyle(theme.secondaryText)
                        .accessibilityHidden(true)
                }

                Text(entry.city.name)
                    .font(.searchResultCity)
                    .foregroundStyle(entry.id == selectedKey ? theme.primaryText : theme.secondaryText)
                    // As in the search results: a Button centres a long name's
                    // wrapped lines.
                    .multilineTextAlignment(.leading)

                Spacer()

                if !stacked { reading(for: entry) }
            }

            if stacked { reading(for: entry) }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        // Without this, rows with the location icon get their separator
        // indented past it while the others start at the edge.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        // And to the trailing margin, where the list otherwise stops short of
        // the rule under the search results.
        .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
        .accessibilityElement(children: .combine)
        // The arrow is hidden from VoiceOver and the row combines its
        // children, so without this the located entry and a saved city of the
        // same name are indistinguishable when read aloud.
        .accessibilityLabel(CityNameStrip.spokenName(entry.city.name,
                                                     isCurrentLocation: entry.isCurrentLocation))
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

    @ViewBuilder
    private func reading(for entry: CityEntry) -> some View {
        if let weather = entry.weather {
            // Per row, not from the environment: each city in this list
            // may be shown in different units.
            Text(entry.city.unitSystem.temperature(weather.temperature))
                .font(.searchResultCity)
                .foregroundStyle(theme.primaryText)
        }
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
