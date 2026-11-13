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
            .font(Theme.smallMedium)
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
            .font(Theme.smallMedium)
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
            Text(T("Problem")).font(Theme.smallMedium).foregroundStyle(Theme.black)
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

// MARK: build 5: progress, chips, haptics

/// A light tap or a success or failure buzz. Sparing, and never while recording.
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func failure() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UISelectionFeedbackGenerator().selectionChanged() }
}

/// A small rounded button for quick choices: ideas, rewrites, speeds.
struct Chip: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(Theme.smallMedium)
                .foregroundStyle(Theme.black)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Capsule().fill(selected ? Theme.lime : Theme.white))
                .overlay(Capsule().strokeBorder(Theme.black, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A row of chips that scrolls sideways.
struct ChipRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content }
                .padding(.vertical, 2)
        }
    }
}

/// Long work shown as named steps with ticks, the time so far, and a rough estimate.
/// People wait far more calmly when they can see where things are.
struct StepList: View {
    let steps: [String]
    /// Index of the step in progress. Equal to `steps.count` when everything is done.
    let current: Int
    var detail: String?
    var estimate: String?

    @State private var started = Date()
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(index < current ? Theme.black : (index == current ? Theme.lime : Theme.white))
                        Circle().strokeBorder(Theme.black, lineWidth: 1)
                        if index < current {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.white)
                        } else if index == current {
                            ProgressView().controlSize(.mini).tint(Theme.black)
                        }
                    }
                    .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(index == current ? Theme.bodyMedium : Theme.body)
                            .foregroundStyle(index > current ? Theme.muted : Theme.black)
                        if index == current, let detail {
                            Text(detail).font(Theme.small).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            HStack {
                Text(Fmt.clock(now.timeIntervalSince(started)))
                    .font(Theme.smallMedium).foregroundStyle(Theme.black)
                    .monospacedDigit()
                if let estimate {
                    Text("· " + estimate).font(Theme.small).foregroundStyle(Theme.muted)
                }
            }
        }
        .card(fill: Theme.grey)
        .onReceive(clock) { now = $0 }
        .accessibilityElement(children: .combine)
    }
}
