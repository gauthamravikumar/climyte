//
//  PlaceholderViews.swift
//  climyte
//

import SwiftUI

/// Shown when a fetch failed and there is nothing to fall back on.
struct WeatherErrorView: View {
    let message: String
    let theme: WeatherTheme
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundColor(theme.secondaryText)
                .accessibilityHidden(true)

            Text("Couldn't load weather")
                .font(.stateTitle)
                .foregroundColor(theme.primaryText)

            Text(message)
                .font(.stateBody)
                .foregroundColor(theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: onRetry) {
                Text("Try again")
                    .font(.stateAction)
                    .foregroundColor(theme.primaryText)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .overlay(Capsule().stroke(theme.dividerColor, lineWidth: 1))
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 80)
        .frame(maxWidth: .infinity)
    }
}

/// Shown when a refresh failed but previously loaded weather is still visible.
struct StaleDataNotice: View {
    let message: String
    let theme: WeatherTheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13))
                .accessibilityHidden(true)

            Text(message)
                .font(.inlineNotice)

            Spacer()
        }
        .foregroundColor(theme.secondaryText)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shown before anything has loaded and no error has occurred.
struct NoWeatherDataView: View {
    let theme: WeatherTheme

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cloud.sun.rain.fill")
                .font(.system(size: 60))
                .symbolRenderingMode(.multicolor)
                .accessibilityHidden(true)

            Text("No weather data available")
                .font(.stateTitle)
                .foregroundColor(theme.primaryText)

            Text("Try searching for a city above to get started.")
                .font(.stateBody)
                .foregroundColor(theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 80)
        .frame(maxWidth: .infinity)
        .background(theme.primaryText.opacity(0.02))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(theme.dividerColor, lineWidth: 1)
        )
    }
}
