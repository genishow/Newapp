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
            .modifier(KeyboardRoom())
    }
}

/// Extra room under the page while the keyboard is up, so the last lines can be
/// scrolled into view above it (Geni, 2026-11-16: the keyboard covered the bottom).
private struct KeyboardRoom: ViewModifier {
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .padding(.bottom, up ? 140 : 0)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                up = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                up = false
            }
    }
}

/// The same top row on every main page: the logo, light or dark, and the credits.
struct PageHeader: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack {
            LogoMark(size: 36)
            Spacer()
            AppearanceButton()
            Button {
                state.selectedTab = 2
                state.pendingAccountRoute = .buyCredits
            } label: {
                Pill(text: Fmt.credits(state.balance) + " " + T("credits"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("headerCredits")
        }
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
    /// How much has played, 0 to 1. Bars past it are dimmed, as on the website's player.
    var progress: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Every bar sits in an equal share of the width, so the bars always reach from
            // one side of the card to the other.
            HStack(alignment: .center, spacing: 0) {
                ForEach(0..<bars, id: \.self) { i in
                    let wave = active ? abs(sin(t * 3.1 + Double(i) * 0.55)) * abs(sin(t * 1.3 + Double(i) * 0.21)) : 0.15
                    let lit = progress.map { Double(i) / Double(max(bars, 1)) < $0 } ?? true
                    Capsule().fill(color)
                        .opacity(lit ? 1 : 0.3)
                        .frame(width: 4, height: 8 + 34 * wave)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .accessibilityHidden(true)
    }
}

/// System pickers, dressed in the brand: black selection, the Kinbir font.
enum BrandControls {
    static func apply() {
        let segmented = UISegmentedControl.appearance()
        let ink = Theme.dynamicUI(light: 0x191A23, dark: 0xF2F2F5)
        let page = Theme.dynamicUI(light: 0xFFFFFF, dark: 0x0B0B0F)
        segmented.selectedSegmentTintColor = ink
        segmented.backgroundColor = Theme.dynamicUI(light: 0xF3F3F3, dark: 0x1E1F26)
        let font = UIFont(name: "SpaceGrotesk-Medium", size: 14) ?? .systemFont(ofSize: 14, weight: .medium)
        segmented.setTitleTextAttributes([.foregroundColor: page, .font: font], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: ink, .font: font], for: .normal)
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
        ("wand.and.stars", "Fixing words, all together", "≤ 1.5"),
        ("list.bullet.rectangle", "Planning the shots of a video", "by length"),
        ("film", "Making the video", "from 2"),
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

/// One tap changes the colour mode: same as phone, light, dark (Geni: "an icon on the
/// heading so I can change it"). Shares its setting with the Appearance choice in Account.
/// "Report a problem" under a finished result: AI output can be wrong, so there
/// is always a way to tell us about one (App Review asks for this in AI apps).
struct ReportLink: View {
    let id: String

    private var url: URL {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = "support@kinbir.com"
        parts.queryItems = [URLQueryItem(name: "subject", value: "Problem with a Kinbir result (" + id + ")")]
        return parts.url ?? URL(string: "mailto:support@kinbir.com")!
    }

    var body: some View {
        MailButton(url: url) {
            Text(T("Report a problem with this result"))
                .font(Theme.small).foregroundStyle(Theme.muted)
        }
        .accessibilityIdentifier("reportLink")
    }
}

/// Opens a new email to Kinbir. On a phone with no mail app set up, a tap on a
/// plain mail link does nothing at all, so this shows the address to copy instead.
struct MailButton<Label: View>: View {
    let url: URL
    @ViewBuilder var label: () -> Label
    @Environment(\.openURL) private var openURL
    @State private var showAddress = false

    static var address: String { "support@kinbir.com" }

    var body: some View {
        Button {
            openURL(url) { opened in
                if !opened { showAddress = true }
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .alert(T("Email us"), isPresented: $showAddress) {
            Button(T("Copy address")) { UIPasteboard.general.string = MailButton.address }
            Button(T("Close"), role: .cancel) {}
        } message: {
            Text(MailButton.address)
        }
    }
}

/// Shown once work has started on the server: it is safe to leave now.
struct LeaveNote: View {
    /// The phone has not been asked about notifications yet. This is the moment
    /// they are worth something: the person is about to leave and wait.
    @State private var canAsk = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16)).foregroundStyle(Theme.black)
                Text(T("You can leave now. It will be in your Library."))
                    .font(Theme.smallMedium).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if canAsk {
                Button {
                    Task {
                        await Notifications.askNow()
                        canAsk = false
                    }
                } label: {
                    Label(T("Tell me when it is ready"), systemImage: "bell")
                        .font(Theme.smallMedium).foregroundStyle(Theme.black)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("notifyMeButton")
            }
        }
        .task { canAsk = await Notifications.canAsk() }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lime.opacity(0.45)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("leaveNote")
    }
}

struct AppearanceButton: View {
    /// Light or dark only (Geni, 2026-11-15). An old "system" reads as light.
    @AppStorage("kinbir.appearance") private var appearance = "light"

    private var isDark: Bool { appearance == "dark" }
    private var icon: String { isDark ? "moon.fill" : "sun.max.fill" }
    private var label: String { isDark ? T("Dark") : T("Light") }

    var body: some View {
        Button {
            Haptics.tap()
            appearance = isDark ? "light" : "dark"
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.black)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.grey))
                .overlay(Circle().strokeBorder(Theme.black.opacity(0.15), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("Appearance") + ", " + label)
        .accessibilityIdentifier("appearanceButton")
    }
}
