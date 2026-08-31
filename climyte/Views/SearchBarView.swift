//
//  SearchBarView.swift
//  climyte
//

import SwiftUI

struct SearchBarView: View {
    @Binding var query: String
    @Binding var isSearching: Bool
    let theme: WeatherTheme

    @FocusState private var isFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(theme.secondaryText)
                    .font(.system(size: 16))
                    .accessibilityHidden(true)

                // No string title: an empty literal is still extracted as a
                // localizable key, and an empty row in the catalog is a
                // question for whoever translates it. The label is supplied
                // by accessibilityLabel below, and the visible placeholder by
                // the overlay.
                TextField(text: $query) { EmptyView() }
                    .focused($isFocused)
                    .font(.searchField)
                    .foregroundColor(theme.primaryText)
                    // The built-in placeholder takes its colour from the
                    // device's light/dark appearance rather than from the
                    // theme, so on a night-themed city it rendered near-black
                    // on near-black — measured at 1.13:1. Drawing it here ties
                    // it to the same palette as everything else on screen.
                    .overlay(alignment: .leading) {
                        if query.isEmpty {
                            Text("Search city")
                                .font(.searchField)
                                .foregroundColor(theme.secondaryText)
                                // At accessibility sizes this truncated to
                                // "Searc…", leaving an unexplained empty field
                                // for exactly the readers who need the hint.
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("Search city")
                    .accentColor(theme.primaryText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(theme.secondaryText)
                            .font(.system(size: 16, weight: .medium))
                            // A 16pt glyph is roughly 13pt of actual ink. The
                            // frame and hit shape give it the 44pt target the
                            // glyph alone never had.
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Clear search")
                }

                if isSearching {
                    Button("Cancel") {
                        query = ""
                        isFocused = false
                    }
                    .font(.searchCancel)
                    .foregroundColor(theme.primaryText)
                    // A control label is not prose: broken across two lines it
                    // rendered as "Canc" / "el", which reads as a fault rather
                    // than as a button.
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 4)
                }
            }

            ThemeDivider(theme: theme)
        }
        .padding(.horizontal, 4)
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
}
