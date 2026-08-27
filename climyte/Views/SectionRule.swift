//
//  SectionRule.swift
//  climyte
//

import SwiftUI

/// A section marker: a rule with a short span label sitting on it.
///
/// Replaces the small-caps word headings. The label says what range of time
/// the section covers rather than naming the component, so it carries
/// information the heading didn't.
struct SectionRule: View {
    let label: LocalizedStringResource
    /// Spoken in full, since the visible label is deliberately abbreviated.
    let accessibilityLabel: LocalizedStringResource
    let theme: WeatherTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(theme.dividerColor)
                .frame(height: 1)

            Text(label)
                .font(.sectionHeading)
                .foregroundColor(theme.secondaryText)
                .padding(.horizontal, 4)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isHeader)
    }
}
