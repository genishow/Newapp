import SwiftUI

// MARK: card

/// A surface. Two kinds only, so screens stay calm:
/// - lime is the one "hero" on a screen: black border and the hard brand shadow;
/// - grey and white are flat groupings: no shadow, and white gets a hairline so it shows
///   on the white page.
struct CardModifier: ViewModifier {
    var fill: Color = Theme.grey
    var padding: CGFloat = 16

    private var isHero: Bool { fill == Theme.lime }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    if isHero {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .fill(Theme.black)
                            .offset(y: Theme.shadowDrop)
                    }
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(fill)
                    if isHero {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .strokeBorder(Theme.black, lineWidth: 1)
                    } else if fill == Theme.white {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .strokeBorder(Theme.grey, lineWidth: 2)
                    }
                }
            )
            .padding(.bottom, isHero ? Theme.shadowDrop : 0)
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

/// The second action on a screen: white with a black outline.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.button)
            .foregroundStyle(isEnabled ? Theme.black : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(configuration.isPressed ? Theme.grey : Theme.white))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(isEnabled ? Theme.black : Theme.muted, lineWidth: 1.5))
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

/// A clear way to put the keyboard away, shown in the page while a field is in use.
/// The keyboard's own Done bar does not always show on a device.
struct KeyboardDoneButton: View {
    var id = "hideKeyboardButton"
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "keyboard.chevron.compact.down")
                Text(T("Done"))
            }
            .font(Theme.smallMedium).foregroundStyle(Theme.black)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Capsule().fill(Theme.lime))
            .overlay(Capsule().strokeBorder(Theme.black, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
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
            .modifier(RiseIn())
    }
}

/// Every screen eases in from slightly below instead of snapping into place.
private struct RiseIn: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) { shown = true }
            }
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

// MARK: build 7

/// The main button of a screen, pinned above the tab bar so it is always in reach,
/// with any problem shown right above it where the tap happened.
struct BottomBar<Content: View>: View {
    var problem: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 10) {
            if let problem {
                ProblemCard(message: problem)
            }
            content
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.white.shadow(color: Theme.black.opacity(0.08), radius: 6, y: -2))
    }
}

/// A tappable row with an icon, a title, an optional second line and a chevron.
struct OptionRow: View {
    let icon: String
    let title: String
    var detail: String?
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.black)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.lime))
                .overlay(Circle().strokeBorder(Theme.black, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                    .multilineTextAlignment(.leading)
                if let detail {
                    Text(detail).font(Theme.small).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if let value {
                Text(value).font(Theme.small).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .frame(minHeight: 44)
        .card(fill: Theme.grey, padding: 12)
        .contentShape(Rectangle())
    }
}

/// Bars that move while something is being made or played.
struct Waveform: View {
    var active = true
    var bars = 24
    var color: Color = Theme.black

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    let wave = active ? abs(sin(t * 3.1 + Double(i) * 0.55)) * abs(sin(t * 1.3 + Double(i) * 0.21)) : 0.15
                    Capsule().fill(color)
                        .frame(width: 4, height: 8 + 34 * wave)
                }
            }
            .frame(height: 44)
        }
        .accessibilityHidden(true)
    }
}

/// System pickers, dressed in the brand: black selection, the Kinbir font.
enum BrandControls {
    static func apply() {
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(red: 0x19 / 255, green: 0x1A / 255, blue: 0x23 / 255, alpha: 1)
        segmented.backgroundColor = UIColor(red: 0xF3 / 255, green: 0xF3 / 255, blue: 0xF3 / 255, alpha: 1)
        let font = UIFont(name: "SpaceGrotesk-Medium", size: 14) ?? .systemFont(ofSize: 14, weight: .medium)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: font], for: .selected)
        segmented.setTitleTextAttributes([
            .foregroundColor: UIColor(red: 0x19 / 255, green: 0x1A / 255, blue: 0x23 / 255, alpha: 1), .font: font,
        ], for: .normal)
    }
}

/// A friendly picture and one line for a screen with nothing on it yet.
struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.lime).frame(width: 88, height: 88)
                Circle().strokeBorder(Theme.black, lineWidth: 1).frame(width: 88, height: 88)
                Image(systemName: icon).font(.system(size: 34, weight: .medium)).foregroundStyle(Theme.black)
            }
            Text(title).font(Theme.heading).foregroundStyle(Theme.black)
            Text(detail).font(Theme.body).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
    }
}

/// What credits are and what things cost, in one place, so the screens do not have to
/// repeat it in small print.
struct CreditsSheet: View {
    let balance: Double
    let onClose: () -> Void

    private static let prices: [(icon: String, what: String, cost: String)] = [
        ("waveform", "A one-minute voiceover", "≈ 2.5"),
        ("sparkles", "Kinbir writes or changes a script", "≈ 1"),
        ("wand.and.stars", "Fixing words, all together", "1.5"),
        ("film", "A finished video", "≈ 5"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(T("Your credits")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                        Text(Fmt.credits(balance)).font(Theme.font(44, .medium, relativeTo: .largeTitle))
                            .foregroundStyle(Theme.black)
                            .accessibilityIdentifier("creditsSheetBalance")
                    }
                    .card(fill: Theme.lime)

                    Text(T("What things cost")).font(Theme.heading).foregroundStyle(Theme.black)
                    VStack(spacing: 0) {
                        ForEach(Array(CreditsSheet.prices.enumerated()), id: \.offset) { index, row in
                            HStack(spacing: 12) {
                                Image(systemName: row.icon).font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Theme.black).frame(width: 28)
                                Text(T(row.what)).font(Theme.body).foregroundStyle(Theme.black)
                                Spacer()
                                Text(row.cost).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                            }
                            .frame(minHeight: 48)
                            if index < CreditsSheet.prices.count - 1 {
                                Rectangle().fill(Theme.white).frame(height: 2)
                            }
                        }
                    }
                    .card(fill: Theme.grey, padding: 14)

                    Text(T("Free: listening, finding footage, changing shots, and speaking your script. You always see the price on the button before you spend. If something fails, the credits come back."))
                        .font(Theme.small).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(T(APIError.buyingNote)).font(Theme.small).foregroundStyle(Theme.muted)
                }
                .page()
            }
            .background(Theme.white)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Done")) { onClose() }.accessibilityIdentifier("creditsDone")
                }
            }
        }
        .tint(Theme.black)
    }
}

/// The title at the top of a screen: large, bold, with a short lime stroke under it,
/// the way headings are marked on the Kinbir website.
private struct ScreenTitle: ViewModifier {
    var amharic: String?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            content
                .font(Theme.title)
                .foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
            if let amharic {
                Text(amharic)
                    .font(Theme.small)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
            .padding(.bottom, 12)
            .overlay(alignment: .bottomLeading) {
                Capsule().fill(Theme.lime)
                    .frame(width: 56, height: 6)
                    .overlay(Capsule().strokeBorder(Theme.black, lineWidth: 1))
                    .accessibilityHidden(true)
            }
    }
}

extension View {
    func screenTitle(amharic: String? = nil) -> some View { modifier(ScreenTitle(amharic: amharic)) }
}
