//
//  SearchBarView.swift
//  climyte
//

import SwiftUI

/// The search field, in the bottom bar where the button that opened it was.
///
/// It used to open at the top of the screen: the magnifier sat under the
/// thumb and the field it opened was as far from it as the screen allows.
/// Here it rides just above the keyboard, and the results take the space
/// above it.
struct SearchBarView: View {
    /// SF Symbols sized in points ignore Dynamic Type entirely: at
    /// accessibility sizes this was a speck beside text three times its
    /// height. @ScaledMetric keeps the drawn size at the default setting
    /// and grows it with everything else.
    @ScaledMetric(relativeTo: .body) private var icon: CGFloat = 16

    @Binding var query: String
    @Binding var isSearching: Bool
    let theme: WeatherTheme

    @FocusState private var isFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            field
            closeButton
        }
        // The bar is only built once search is open, and it is opened by a
        // button elsewhere on screen — so it has to take focus itself. Without
        // this, tapping the magnifier gave you a field you then had to tap
        // again before you could type into it.
        .onAppear { isFocused = true }
        .onChange(of: isFocused) { _, focused in
            withAnimation(reduceMotion ? nil : .default) { isSearching = focused }
        }
        // The parent dismisses search by setting the binding (after picking a
        // city, say). Without this, focus stays on the field while isSearching
        // is false, and the next tap can't change isFocused — so onChange never
        // fires and the search bar goes dead until relaunch.
        .onChange(of: isSearching) { _, searching in
            if !searching { isFocused = false }
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryText)
                .font(.system(size: icon))
                .accessibilityHidden(true)

            // No string title: an empty literal is still extracted as a
            // localizable key, and an empty row in the catalog is a
            // question for whoever translates it. The label is supplied
            // by accessibilityLabel below, and the visible placeholder by
            // the overlay.
            TextField(text: $query) { EmptyView() }
                .focused($isFocused)
                .font(.searchField)
                .foregroundStyle(theme.primaryText)
                // The built-in placeholder takes its colour from the
                // device's light/dark appearance rather than from the
                // theme, so on a night-themed city it rendered near-black
                // on near-black — measured at 1.13:1. Drawing it here ties
                // it to the same palette as everything else on screen.
                .overlay(alignment: .leading) {
                    Text("Search city")
                        .font(.searchField)
                        .foregroundStyle(theme.secondaryText)
                        // At accessibility sizes this truncated to
                        // "Searc…", leaving an unexplained empty field
                        // for exactly the readers who need the hint.
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsHitTesting(false)
                        .opacity(query.isEmpty ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("Search city")
                .tint(theme.primaryText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)

            // Always in the row, and only shown once there is something to
            // clear. Added and removed with the first letter, it changed the
            // shape of what sits on the glass, and the glass rebuilt the field
            // beneath it: the keyboard dropped and came back, and the letters
            // typed in between were lost.
            Button {
                query = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.secondaryText)
                    .font(.system(size: icon))
                    // The frame and hit shape give the glyph the 44pt
                    // target it never had on its own — as a floor, not a
                    // fixed size, since past AX-L the glyph outgrows it.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Clear search")
            .opacity(query.isEmpty ? 0 : 1)
            .disabled(query.isEmpty)
            .accessibilityHidden(query.isEmpty)
        }
        .padding(.leading, 18)
        .padding(.trailing, 4)
        .frame(minHeight: 52)
        .glassBackground(in: Capsule())
    }

    /// Leaves search. A round button of its own beside the field, where the
    /// system's own search puts it, rather than the word "Cancel".
    private var closeButton: some View {
        Button {
            query = ""
            isFocused = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: icon, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .frame(minWidth: 52, minHeight: 52)
                .contentShape(Circle())
        }
        .glassBackground(in: Circle())
        .accessibilityLabel("Close search")
    }
}
