import SwiftUI
import UIKit
import CoreText

/// The Kinbir look. These five colours are the only ones in the app.
enum Theme {
    static let lime = Color(red: 0xB9 / 255.0, green: 0xFF / 255.0, blue: 0x66 / 255.0)
    static let black = Color(red: 0x19 / 255.0, green: 0x1A / 255.0, blue: 0x23 / 255.0)
    static let grey = Color(red: 0xF3 / 255.0, green: 0xF3 / 255.0, blue: 0xF3 / 255.0)
    static let white = Color.white
    static let muted = Color(red: 0x5A / 255.0, green: 0x5B / 255.0, blue: 0x66 / 255.0)

    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14
    static let margin: CGFloat = 20
    static let gap: CGFloat = 16
    static let shadowDrop: CGFloat = 5

    /// Ethiopic letters are taller than Latin ones and need more room between lines.
    static let amharicLineSpacing: CGFloat = 8

    // Space Grotesk, the Kinbir website's typeface, for Latin text, and Noto Sans Ethiopic in
    // the same weight for Amharic, so Amharic headings look as strong as English ones.
    // Sizes follow the phone's text size setting as it was when the app opened.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular,
                     relativeTo style: Font.TextStyle = .body) -> Font {
        let suffix: String
        switch weight {
        case .bold, .semibold, .heavy, .black: suffix = "Bold"
        case .medium: suffix = "Medium"
        default: suffix = "Regular"
        }
        guard let latin = UIFont(name: "SpaceGrotesk-" + suffix, size: size) else {
            return Font.system(size: size, weight: weight)
        }
        let ethiopic = UIFontDescriptor(fontAttributes: [.name: "NotoSansEthiopic-" + suffix])
        let descriptor = latin.fontDescriptor.addingAttributes([.cascadeList: [ethiopic]])
        let combined = UIFont(descriptor: descriptor, size: size)
        return Font(UIFontMetrics(forTextStyle: uiStyle(style)).scaledFont(for: combined) as CTFont)
    }

    private static func uiStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }

    static let title = font(32, .bold, relativeTo: .title)
    static let heading = font(21, .bold, relativeTo: .title2)
    static let body = font(17, .regular, relativeTo: .body)
    static let bodyMedium = font(17, .medium, relativeTo: .body)
    static let small = font(14, .regular, relativeTo: .footnote)
    static let smallMedium = font(14, .medium, relativeTo: .footnote)
    static let button = font(17, .bold, relativeTo: .body)
}
