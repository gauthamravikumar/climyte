//
//  Typography.swift
//  climyte
//

import SwiftUI

extension Font {

    /// The bundled Manrope weights, addressed by PostScript name.
    ///
    /// Keeping these in one place means a font swap is a change here rather
    /// than a hunt through every view.
    enum Manrope: String {
        case regular = "Manrope-Regular"
        case medium = "Manrope-Medium"
        case semiBold = "Manrope-SemiBold"
        case bold = "Manrope-Bold"
        case extraBold = "Manrope-ExtraBold"
    }

    /// Pairs a fixed point size with a text style so the result scales with the
    /// reader's Dynamic Type setting instead of ignoring it.
    static func manrope(_ weight: Manrope, _ size: CGFloat, relativeTo style: TextStyle) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    // MARK: - Type ramp

    static let searchField = manrope(.medium, 16, relativeTo: .body)
    static let searchCancel = manrope(.semiBold, 15, relativeTo: .subheadline)
    static let searchResultCity = manrope(.bold, 18, relativeTo: .headline)
    static let searchResultRegion = manrope(.medium, 15, relativeTo: .subheadline)

    static let cityName = manrope(.bold, 28, relativeTo: .title)
    static let localTime = manrope(.medium, 18, relativeTo: .body)
    static let temperatureHero = manrope(.regular, 100, relativeTo: .largeTitle)
    static let highLow = manrope(.medium, 14, relativeTo: .caption)
    static let conditionSummary = manrope(.medium, 16, relativeTo: .body)

    static let sectionHeading = manrope(.bold, 12, relativeTo: .caption2)

    static let hourTemperature = manrope(.bold, 14, relativeTo: .caption)
    static let hourLabel = manrope(.medium, 12, relativeTo: .caption2)

    static let dayLabel = manrope(.bold, 16, relativeTo: .body)
    static let dayLowTemperature = manrope(.medium, 16, relativeTo: .body)
    static let dayHighTemperature = manrope(.bold, 16, relativeTo: .body)

    static let detailValue = manrope(.bold, 20, relativeTo: .title3)
    static let detailCaption = manrope(.medium, 14, relativeTo: .caption)

    static let stateTitle = manrope(.bold, 20, relativeTo: .title3)
    static let stateBody = manrope(.regular, 16, relativeTo: .body)
    static let stateAction = manrope(.semiBold, 15, relativeTo: .subheadline)
    static let inlineNotice = manrope(.medium, 13, relativeTo: .caption)
}
