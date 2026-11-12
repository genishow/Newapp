import SwiftUI

// MARK: card

/// White, grey or lime fill, a 1 pt black border and a hard black shadow under it.
struct CardModifier: ViewModifier {
    var fill: Color = Theme.white
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.black)
                        .offset(y: Theme.shadowDrop)
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(fill)
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.black, lineWidth: 1)
                }
            )
            .padding(.bottom, Theme.shadowDrop)
    }
}

extension View {
    func card(fill: Color = Theme.white, padding: CGFloat = 18) -> some View {
        modifier(CardModifier(fill: fill, padding: padding))
    }
}

// MARK: buttons

/// Lime, the one main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(Theme.button)
            .foregroundStyle(isEnabled ? Theme.black : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(Theme.black)
                        .offset(y: isEnabled ? 4 : 0)
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(isEnabled ? Theme.lime : Theme.grey)
                        .offset(y: pressed ? 4 : 0)
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(isEnabled ? Theme.black : Theme.muted, lineWidth: 1)
                        .offset(y: pressed ? 4 : 0)
                }
            )
            .offset(y: 0)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
    }
}

/// Black, for the second action.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.button)
            .foregroundStyle(Theme.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(isEnabled ? Theme.black : Theme.muted)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

/// Plain underlined text.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.small.weight(.medium))
            .underline()
            .foregroundStyle(Theme.black)
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: small pieces

/// A word on a lime marker, for headings.
struct Marker: View {
    let text: String
    var font: Font = Theme.title

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Theme.black)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.lime))
    }
}

struct Pill: View {
    let text: String
    var fill: Color = Theme.lime

    var body: some View {
        Text(text)
            .font(Theme.small.weight(.medium))
            .foregroundStyle(Theme.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Theme.black, lineWidth: 1))
    }
}

/// The app icon's waveform, drawn in code.
struct LogoMark: View {
    var size: CGFloat = 44

    var body: some View {
        let heights: [CGFloat] = [0.24, 0.5, 0.66, 0.42, 0.28]
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Theme.lime)
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(Theme.black, lineWidth: 1)
            HStack(spacing: size * 0.06) {
                ForEach(0..<heights.count, id: \.self) { i in
                    Capsule().fill(Theme.black)
                        .frame(width: size * 0.09, height: size * heights[i])
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Something went wrong, said plainly. Black on grey: the palette has no red.
struct ProblemCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Problem").font(Theme.small.weight(.medium)).foregroundStyle(Theme.black)
            Text(message).font(Theme.body).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(fill: Theme.grey, padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("problemCard")
    }
}

struct NoteText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.small)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Amharic text with the looser line spacing it needs.
struct AmharicText: View {
    let text: String
    var font: Font = Theme.body

    var body: some View {
        Text(text)
            .font(font)
            .lineSpacing(Theme.amharicLineSpacing)
            .foregroundStyle(Theme.black)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The grey field look, for TextField and SecureField.
struct FieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.body)
            .foregroundStyle(Theme.black)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(Theme.grey))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Theme.black, lineWidth: 1))
    }
}

extension View {
    func field() -> some View { modifier(FieldModifier()) }

    /// The standard scrolling page: white ground, 20 pt margins.
    func page() -> some View {
        self
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, Theme.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A button label that shows a spinner while work is running.
struct BusyLabel: View {
    let title: String
    let busy: Bool

    var body: some View {
        HStack(spacing: 10) {
            if busy { ProgressView().tint(Theme.black) }
            Text(title)
        }
    }
}
