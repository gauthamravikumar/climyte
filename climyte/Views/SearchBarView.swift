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

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(theme.secondaryText)
                    .font(.system(size: 16))
                    .accessibilityHidden(true)

                TextField("Search city", text: $query)
                    .focused($isFocused)
                    .font(.searchField)
                    .foregroundColor(theme.primaryText)
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
                    .padding(.leading, 4)
                }
            }

            ThemeDivider(theme: theme)
        }
        .padding(.horizontal, 4)
        .onChange(of: isFocused) { _, focused in
            withAnimation { isSearching = focused }
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
