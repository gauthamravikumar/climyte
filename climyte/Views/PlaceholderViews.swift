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
            Text("Couldn't load weather")
                .font(.stateTitle)
                .foregroundStyle(theme.primaryText)

            Text(message)
                .font(.stateBody)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: onRetry) {
                Text("Try again")
                    .font(.stateAction)
                    .foregroundStyle(theme.primaryText)
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
    /// SF Symbols sized in points ignore Dynamic Type entirely: at
    /// accessibility sizes this was a speck beside text three times its
    /// height. @ScaledMetric keeps the drawn size at the default setting
    /// and grows it with everything else.
    @ScaledMetric(relativeTo: .caption) private var noticeIcon: CGFloat = 13

    let message: String
    var fetchedAt: Date?
    let theme: WeatherTheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: noticeIcon))
                .accessibilityHidden(true)

            Text(displayedMessage)
                .font(.inlineNotice)

            Spacer()
        }
        .foregroundStyle(theme.secondaryText)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var displayedMessage: String {
        Self.fullMessage(message: message, fetchedAt: fetchedAt)
    }

    /// The message, then how old the readings are. With no error to lead
    /// with, the age stands alone.
    static func fullMessage(message: String, fetchedAt: Date?, now: Date = Date()) -> String {
        guard let fetchedAt else { return message }
        let age = age(of: fetchedAt, relativeTo: now)
        return message.isEmpty ? age : "\(message) \(age)"
    }

    /// Whether the page should say how old its readings are.
    ///
    /// After a failed refresh, as ever. And whenever the readings are old
    /// enough to be called stale — the threshold the widget uses — so a
    /// forecast saved days ago never passes for today's. Not while a refresh
    /// is on its way: that would flash the notice for a second on every launch
    /// after a few hours away, then take it back.
    static func isShown(errorMessage: String?, fetchedAt: Date?,
                        isRefreshing: Bool, now: Date = Date()) -> Bool {
        if errorMessage != nil { return true }
        guard let fetchedAt, !isRefreshing else { return false }
        return ReadingAge.isStale(now.timeIntervalSince(fetchedAt))
    }

    /// How old the reading on screen is, so "no internet connection" doesn't
    /// leave the user guessing whether they're looking at today's weather.
    static func age(of date: Date, relativeTo now: Date = Date()) -> String {
        // `date` comes off the cache file, where a Date decodes from any bare
        // Double — so this arithmetic is only as sane as the bytes on disk.
        let minutes = (now.timeIntervalSince(date) / 60).toInt(.towardZero)

        switch minutes {
        case ..<1:
            return String(localized: "Showing readings from just now.")
        case ..<60:
            return String(localized: "Showing readings from \(minutes)m ago.")
        case ..<(60 * 24):
            return String(localized: "Showing readings from \(minutes / 60)h ago.")
        default:
            return String(localized: "Showing readings from \(minutes / (60 * 24))d ago.")
        }
    }
}

/// Shown before anything has loaded and no error has occurred.
///
/// Type only, like every other state in the app. It used to carry a
/// multicolour cloud, the one coloured thing on any screen, and pointed at a
/// search field "above" that had since moved to the bottom.
struct NoWeatherDataView: View {
    let theme: WeatherTheme

    var body: some View {
        VStack(spacing: 12) {
            Text("No weather yet")
                .font(.stateTitle)
                .foregroundStyle(theme.primaryText)

            Text("Pull down to refresh.")
                .font(.stateBody)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 80)
        .frame(maxWidth: .infinity)
    }
}

/// A newly added city while its first forecast is on the way.
///
/// It replaces a spinner at one and a half times normal size, alone on a
/// blank page, which was the only spinner in the app. The name is known
/// already and is shown; the rest of the page stands in as shapes, pulsing
/// like the search placeholders, and holding still under Reduce Motion.
struct PageSkeleton: View {
    let cityName: String
    let theme: WeatherTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(cityName)
                    .font(.cityName)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 12)
                block(width: 74, height: 18)
            }

            VStack(alignment: .leading, spacing: 0) {
                block(width: 150, height: 84)
                    .padding(.top, 34)
                block(width: 64, height: 14)
                    .padding(.top, 16)
                block(width: 190, height: 16)
                    .padding(.top, 10)

                ThemeDivider(theme: theme)
                    .padding(.top, 30)

                HStack(spacing: 18) {
                    ForEach(0..<5, id: \.self) { _ in block(width: 38, height: 14) }
                }
                .padding(.top, 40)
            }
            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { shapes, opacity in
                shapes.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.8)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading weather for \(cityName)"))
    }

    private func block(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(theme.dividerColor)
            .frame(width: width, height: height)
    }
}
