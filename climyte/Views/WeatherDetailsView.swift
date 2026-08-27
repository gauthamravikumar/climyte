//
//  WeatherDetailsView.swift
//  climyte
//

import SwiftUI

struct WeatherDetailsView: View {
    let weather: CityWeather
    let theme: WeatherTheme

    @Environment(\.unitSystem) private var units

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                DetailCell(icon: "sun.max", title: "SUNRISE", value: weather.sunriseFormatted,
                           alignment: .leading, theme: theme)

                Rectangle()
                    .fill(theme.dividerColor)
                    .frame(width: 1, height: 45)
                    .padding(.horizontal, 16)

                DetailCell(icon: "moon.fill", title: "SUNSET", value: weather.sunsetFormatted,
                           alignment: .trailing, theme: theme)
            }
            .padding(.vertical, 18)

            ThemeDivider(theme: theme)

            HStack(alignment: .top) {
                DetailCell(icon: "wind", title: "WIND",
                           value: units.windSpeed(weather.windSpeed),
                           caption: Self.windDescription(weather.windSpeed),
                           alignment: .leading, theme: theme)

                DetailCell(icon: "drop.fill", title: "HUMIDITY",
                           value: "\(weather.humidity)%",
                           alignment: .trailing, theme: theme) {
                    HumidityBar(humidity: weather.humidity, theme: theme)
                }
            }
            .padding(.vertical, 18)

            ThemeDivider(theme: theme)

            HStack {
                DetailCell(icon: "sun.max", title: "UV INDEX",
                           value: Self.uvIndex(weather.uvIndex),
                           alignment: .leading, theme: theme)

                DetailCell(icon: "eye", title: "VISIBILITY",
                           value: units.visibility(weather.visibility),
                           alignment: .trailing, theme: theme)
            }
            .padding(.vertical, 18)
        }
    }

    // MARK: - Formatting

    static func uvIndex(_ value: Double) -> String {
        let category: String
        switch value {
        case ..<2.5: category = String(localized: "Low", comment: "UV index category")
        case ..<5.5: category = String(localized: "Mod", comment: "UV index category, abbreviated 'Moderate'")
        case ..<7.5: category = String(localized: "High", comment: "UV index category")
        case ..<10.5: category = String(localized: "Very High", comment: "UV index category")
        default: category = String(localized: "Extreme", comment: "UV index category")
        }
        return "\(Int(value.rounded())) \(category)"
    }

    /// Beaufort-style description of the wind speed, in km/h.
    static func windDescription(_ speed: Double) -> LocalizedStringResource {
        switch speed {
        case ..<5: return "Light air"
        case 5..<12: return "Light breeze"
        case 12..<20: return "Gentle breeze"
        case 20..<29: return "Moderate breeze"
        case 29..<39: return "Fresh breeze"
        case 39..<50: return "Strong breeze"
        default: return "High wind"
        }
    }
}

// MARK: - Cell

/// One labelled reading. Leading cells read icon-then-title; trailing cells
/// mirror that so the pair frames the row.
private struct DetailCell<Accessory: View>: View {
    let icon: String
    /// LocalizedStringResource rather than String or LocalizedStringKey:
    /// `Text(String)` skips translation lookup entirely, and unlike a
    /// LocalizedStringKey a resource can also be resolved back to a String
    /// for the accessibility label below.
    let title: LocalizedStringResource
    let value: String
    var caption: LocalizedStringResource?
    let alignment: HorizontalAlignment
    let theme: WeatherTheme
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            HStack(spacing: 6) {
                if alignment == .leading {
                    Image(systemName: icon).font(.system(size: 14))
                    heading
                } else {
                    heading
                    Image(systemName: icon).font(.system(size: 14))
                }
            }
            .foregroundColor(theme.secondaryText)

            Text(value)
                .font(.detailValue)
                .foregroundColor(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let caption {
                Text(caption)
                    .font(.detailCaption)
                    .foregroundColor(theme.secondaryText)
            }

            accessory()
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let heading = String(localized: title).capitalized
        guard let caption else { return "\(heading), \(value)" }
        return "\(heading), \(value), \(String(localized: caption))"
    }

    /// Shrinks rather than wrapping — "VISIBILITY" breaking to "VISIBILIT/Y"
    /// at accessibility sizes looks broken.
    private var heading: some View {
        Text(title)
            .font(.sectionHeading)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

extension DetailCell where Accessory == EmptyView {
    init(icon: String, title: LocalizedStringResource, value: String,
         caption: LocalizedStringResource? = nil,
         alignment: HorizontalAlignment, theme: WeatherTheme) {
        self.init(icon: icon, title: title, value: value, caption: caption,
                  alignment: alignment, theme: theme) { EmptyView() }
    }
}

// MARK: - Humidity

private struct HumidityBar: View {
    let humidity: Int
    let theme: WeatherTheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.dividerColor)
                Capsule()
                    .fill(theme.primaryText)
                    .frame(width: geo.size.width * CGFloat(humidity) / 100.0)
            }
        }
        .frame(width: 80, height: 4)
        .padding(.top, 4)
        .accessibilityHidden(true)
    }
}
