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

    static let title = Font.system(size: 30, weight: .medium)
    static let heading = Font.system(size: 22, weight: .medium)
    static let body = Font.system(size: 17)
    static let small = Font.system(size: 14)
    static let button = Font.system(size: 17, weight: .medium)
}
