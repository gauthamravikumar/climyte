//
//  ThemeDivider.swift
//  climyte
//

import SwiftUI

/// A hairline in the theme's divider colour.
///
/// `Divider().background(_:)` doesn't reliably tint on all platforms, and the
/// rule was being hand-rolled as a `Rectangle` in several places already.
struct ThemeDivider: View {
    let theme: WeatherTheme

    var body: some View {
        Rectangle()
            .fill(theme.dividerColor)
            .frame(height: 1)
    }
}
