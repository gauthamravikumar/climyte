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
    static let temperatureRange = manrope(.medium, 15, relativeTo: .subheadline)
    static let conditionSummary = manrope(.medium, 16, relativeTo: .body)

    static let sectionHeading = manrope(.bold, 12, relativeTo: .caption2)

    static let hourTemperature = manrope(.bold, 14, relativeTo: .caption)
    static let hourLabel = manrope(.medium, 12, relativeTo: .caption2)

    static let dayLabel = manrope(.bold, 16, relativeTo: .body)
    static let dayLowTemperature = manrope(.medium, 16, relativeTo: .body)
    static let dayHighTemperature = manrope(.bold, 16, relativeTo: .body)

    static let weekColumnHigh = manrope(.bold, 13, relativeTo: .caption)
    static let weekColumnLow = manrope(.medium, 12, relativeTo: .caption2)
    static let weekColumnDay = manrope(.medium, 12, relativeTo: .caption2)

    static let detailRowLabel = manrope(.medium, 14, relativeTo: .subheadline)
    static let detailRowValue = manrope(.bold, 16, relativeTo: .body)
    static let detailRowCaption = manrope(.medium, 13, relativeTo: .caption)

    static let stateTitle = manrope(.bold, 20, relativeTo: .title3)
    static let stateBody = manrope(.regular, 16, relativeTo: .body)
    static let stateAction = manrope(.semiBold, 15, relativeTo: .subheadline)
    static let inlineNotice = manrope(.medium, 13, relativeTo: .caption)

    static let cityStripActive = manrope(.bold, 13, relativeTo: .caption)
    static let cityStrip = manrope(.medium, 13, relativeTo: .caption)

    // MARK: - Widget
    //
    // Smaller than the app's ramp because a small widget is 155pt square and
    // has to hold a three-digit reading at accessibility sizes.

    static let widgetCity = manrope(.semiBold, 11, relativeTo: .caption2)
    static let widgetTemperature = manrope(.regular, 42, relativeTo: .title)
    static let widgetDetail = manrope(.semiBold, 11, relativeTo: .caption2)
    static let widgetCaption = manrope(.medium, 10, relativeTo: .caption2)

    static let accessoryValue = manrope(.semiBold, 16, relativeTo: .body)
    static let accessoryLabel = manrope(.medium, 11, relativeTo: .caption2)
}

#if canImport(UIKit)
import UIKit
import CoreText

extension Font.Manrope {
    /// How far the first glyph's ink sits inside the text's layout box.
    ///
    /// Display type has to be aligned by its ink, not its box. Manrope's
    /// digits carry between 4 and 7pt of left side bearing at 100pt depending
    /// on which one leads, so the reading sat visibly inside the margin every
    /// other element hangs off — and stepped sideways as the temperature
    /// changed and the leading digit with it.
    ///
    /// Small text is left alone: at 16pt the same bearing is under a point,
    /// and text that size is conventionally aligned by its box.
    func leftSideBearing(of string: String, size: CGFloat) -> CGFloat {
        guard !string.isEmpty, let font = UIFont(name: rawValue, size: size) else { return 0 }

        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: [.font: font])
        )
        return CTLineGetBoundsWithOptions(line, .useGlyphPathBounds).origin.x
    }
}
#endif
