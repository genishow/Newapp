import SwiftUI

/// The Kinbir look. These five colours are the only ones in the app.
enum Theme {
    static let lime = Color(red: 0xB9 / 255.0, green: 0xFF / 255.0, blue: 0x66 / 255.0)
    static let black = Color(red: 0x19 / 255.0, green: 0x1A / 255.0, blue: 0x23 / 255.0)
    static let grey = Color(red: 0xF3 / 255.0, green: 0xF3 / 255.0, blue: 0xF3 / 255.0)
    static let white = Color.white
    static let muted = Color(red: 0x5A / 255.0, green: 0x5B / 255.0, blue: 0x66 / 255.0)

    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 14
    static let margin: CGFloat = 20
    static let gap: CGFloat = 16
    static let shadowDrop: CGFloat = 5

    /// Ethiopic letters are taller than Latin ones and need more room between lines.
    static let amharicLineSpacing: CGFloat = 8

// Space Grotesk, the Kinbir website's typeface, for Latin text. Amharic falls through to
    // the system's Ethiopic face automatically. Sizes follow the user's text size setting.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular,
                     relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .bold, .semibold, .heavy, .black: name = "SpaceGrotesk-Bold"
        case .medium: name = "SpaceGrotesk-Medium"
        default: name = "SpaceGrotesk-Regular"
        }
        return Font.custom(name, size: size, relativeTo: style)
    }

    static let title = font(30, .medium, relativeTo: .title)
    static let heading = font(22, .medium, relativeTo: .title2)
    static let body = font(17, .regular, relativeTo: .body)
    static let bodyMedium = font(17, .medium, relativeTo: .body)
    static let small = font(14, .regular, relativeTo: .footnote)
    static let smallMedium = font(14, .medium, relativeTo: .footnote)
    static let button = font(17, .medium, relativeTo: .body)
}
