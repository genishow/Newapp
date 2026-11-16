import AVFoundation
import SwiftUI

/// Text typed on the welcome page, carried to the Create page after sign in.
enum PendingScript {
    static let key = "kinbir.pendingScript"

    /// Hands it over once.
    static func take() -> String? {
        let text = (UserDefaults.standard.string(forKey: key) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.removeObject(forKey: key)
        return text.isEmpty ? nil : text
    }
}

/// The language a new visitor chose on the first screen. It decides the language of the
/// welcome page and the script language they start with; the rest of the interface stays
/// English with Amharic under the titles, as the owner chose.
enum WelcomeLanguage {
    static let key = "kinbir.welcomeLang"

    /// "am" or "en", or "" before anyone chose.
    static func pick(_ lang: Lang) {
        UserDefaults.standard.set(lang.rawValue, forKey: key)
        // The Create page starts in the same language, until changed there.
        UserDefaults.standard.set(lang.rawValue, forKey: "kinbir.language")
    }
}

/// English or Amharic, for text on the welcome screens only.
private func W(_ lang: Lang, _ english: String, _ amharic: String) -> String {
    lang == .am ? amharic : english
}

/// The signed-out screens: choose a language once, then a short welcome, then start.
struct WelcomeView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(WelcomeLanguage.key) private var chosen = ""
    @State private var showSignIn = false

    /// The UI tests start on the English welcome page, past the language question.
    private var lang: Lang? {
        if let picked = Lang(rawValue: chosen) { return picked }
        return Launch.isMock && !Launch.mockAskLanguage ? .en : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let lang {
                    welcome(lang)
                } else {
                    LanguageChoice { picked in
                        withAnimation(.easeInOut(duration: 0.25)) { WelcomeLanguage.pick(picked) }
                        chosen = picked.rawValue
                    }
                }
            }
            .navigationDestination(isPresented: $showSignIn) {
                SignInView()
            }
        }
    }

    private func welcome(_ lang: Lang) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Top bar: the brand, and the language, changeable any time.
                HStack(spacing: 10) {
                    LogoMark(size: 34)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Kinbir").font(Theme.heading).foregroundStyle(Theme.black)
                        Text("ቅንብር").font(Theme.font(12, .medium, relativeTo: .caption))
                            .foregroundStyle(Theme.muted)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer()
                    AppearanceButton()
                    LanguageSwitch(selection: Binding(
                        get: { lang },
                        set: { WelcomeLanguage.pick($0); chosen = $0.rawValue }))
                }

                hero(lang)

                if let notice = state.notice {
                    ProblemCard(message: notice)
                }

                steps(lang)

                DemoCard(lang: lang)

                VStack(alignment: .leading, spacing: 10) {
                    Text(W(lang, "Your first voiceovers are free. No card needed.",
                           "የመጀመሪያዎቹ የድምፅ ቅጂዎች ነፃ ናቸው። ካርድ አያስፈልግም።"))
                        .font(Theme.small).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 20) {
                        // Kept in English in both languages: the words people know (Geni).
                        Link("Privacy", destination: URL(string: "https://kinbir.com/privacy")!)
                        Link("Terms", destination: URL(string: "https://kinbir.com/terms")!)
                    }
                    .font(Theme.smallMedium)
                    .foregroundStyle(Theme.black)
                }
            }
            .page()
        }
        .background(Theme.white)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            BottomBar {
                Button(W(lang, "Start free", "በነፃ ይጀምሩ")) { showSignIn = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("startButton")
            }
        }
    }

    /// One promise, one sentence, the sound bars. Nothing else.
    private func hero(_ lang: Lang) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(W(lang, "AI · AMHARIC · ENGLISH", "ኤአይ · አማርኛ · እንግሊዝኛ"))
                .font(Theme.font(12, .bold, relativeTo: .caption)).kerning(1.2)
                .foregroundStyle(Theme.lime)
            VStack(alignment: .leading, spacing: 8) {
                // Sized so each line sits whole on a phone: no word left alone on a line.
                Text(W(lang, "Videos and voiceovers", "ቪዲዮና የድምፅ ቅጂ"))
                    .font(Theme.font(28, .bold, relativeTo: .title)).foregroundStyle(Theme.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Marker(text: W(lang, "in your own voice", "በራስዎ ድምፅ"),
                       font: Theme.font(28, .bold, relativeTo: .title))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("welcomeHeading")
            Text(W(lang, "Kinbir's AI writes your script, reads it in your cloned voice, and makes the video.",
                   "ቅንብር ያስገቡለትን ጽሑፎች ወደ ፕሮፌሽናል የአማርኛ ስክሪፕት ይለውጣል፤ በተፈጥሯዊ ድምፅና ከተስማሚ ቪዲዎች ጋር አቀናጅቶ ያዘጋጅልዎታል።"))
                .font(Theme.body).foregroundStyle(Theme.grey)
                .lineSpacing(lang == .am ? Theme.amharicLineSpacing : 2)
                .fixedSize(horizontal: false, vertical: true)
            Waveform(bars: 30, color: Theme.lime)
                .padding(.top, 4)
        }
        .card(fill: Theme.black, padding: 24)
    }

    /// How it works, in three short steps.
    private func steps(_ lang: Lang) -> some View {
        let rows: [(String, String, String)] = [
            ("sparkles",
             W(lang, "AI writes the script", "ኤአይ ፅሁፉን ይጽፋል"),
             W(lang, "From an idea, a link or your own words.", "ከሀሳብ፣ ከሊንክ ወይም ከራስዎ ቃላት።")),
            ("waveform",
             W(lang, "Read in your voice", "በራስዎ ድምፅ ይነበባል"),
             W(lang, "Clone your voice once, in about a minute.", "ድምፅዎን አንድ ጊዜ፣ በአንድ ደቂቃ ገደማ ይቅረጹ።")),
            ("film",
             W(lang, "A finished video", "የተጠናቀቀ ቪዲዮ"),
             W(lang, "Footage, captions, music and your AI presenter.",
               "ምስሎች፣ የፅሁፍ መግለጫ፣ ሙዚቃ እና የእርስዎ ኤአይ አቅራቢ።")),
        ]
        return VStack(alignment: .leading, spacing: 18) {
            Text(W(lang, "How it works", "እንዴት ይሰራል"))
                .font(Theme.heading).foregroundStyle(Theme.black)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .center, spacing: 14) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: row.0)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.black)
                            .frame(width: 46, height: 46)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.lime))
                        Text("\(index + 1)")
                            .font(Theme.font(11, .bold, relativeTo: .caption2))
                            .foregroundStyle(Theme.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Theme.black))
                            .offset(x: 5, y: 5)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.1).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                        Text(row.2).font(Theme.small).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("welcomeFeatures")
    }
}

/// The very first screen: which language? Two big choices, nothing else.
struct LanguageChoice: View {
    let onPick: (Lang) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 40)
            VStack(alignment: .leading, spacing: 18) {
                LogoMark(size: 56)
                Waveform(bars: 24, color: Theme.lime)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose your language").font(Theme.title).foregroundStyle(Theme.black)
                    Text("ቋንቋዎን ይምረጡ").font(Theme.heading).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 32)
            VStack(spacing: 14) {
                choice(.am, title: "አማርኛ", detail: "Amharic", id: "pickAmharic")
                choice(.en, title: "English", detail: "እንግሊዝኛ", id: "pickEnglish")
            }
            Text("You can change it any time. · በማንኛውም ጊዜ መቀየር ይችላሉ።")
                .font(Theme.small).foregroundStyle(Theme.muted)
                .padding(.top, 16)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.white)
        // keeps the two buttons findable on their own
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("languageChoice")
    }

    private func choice(_ lang: Lang, title: String, detail: String, id: String) -> some View {
        Button {
            Haptics.tap()
            onPick(lang)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(24, .bold, relativeTo: .title2)).foregroundStyle(Theme.black)
                    Text(detail).font(Theme.small).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.black)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.lime))
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.grey))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.black, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// አማ | EN, a small two-way switch for the top right corner.
struct LanguageSwitch: View {
    @Binding var selection: Lang

    var body: some View {
        HStack(spacing: 2) {
            option(.am, "አማ")
            option(.en, "EN")
        }
        .padding(3)
        .background(Capsule().fill(Theme.grey))
        .overlay(Capsule().strokeBorder(Theme.black.opacity(0.15), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("languageSwitch")
    }

    private func option(_ lang: Lang, _ label: String) -> some View {
        Button {
            guard selection != lang else { return }
            Haptics.tap()
            selection = lang
        } label: {
            Text(label)
                .font(Theme.font(13, .bold, relativeTo: .footnote))
                .foregroundStyle(selection == lang ? Theme.white : Theme.black)
                .frame(minWidth: 40, minHeight: 30)
                .background(Capsule().fill(selection == lang ? Theme.black : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang == .am ? "Amharic" : "English")
        .accessibilityAddTraits(selection == lang ? .isSelected : [])
        .accessibilityIdentifier("lang-" + lang.rawValue)
    }
}

/// Type a sentence, or tap a sample, and hear it in the built-in Kinbir voice. No account needed.
struct DemoCard: View {
    var lang: Lang = .en
    @EnvironmentObject private var state: AppState
    @StateObject private var player = AudioPlayer()
    // Starts empty: their own words are the point, and a sample is one tap away.
    @State private var text = ""
    @State private var busy = false
    @State private var reading = false
    @State private var ready = false
    @State private var problem: String?
    @State private var quiet = false
    /// Typed listens before sign in (the samples are free and do not count).
    @AppStorage("kinbir.demoTries") private var tries = 0
    @FocusState private var typing: Bool

    static let freeTries = 5
    private var usedUp: Bool { !Launch.isMock && tries >= Self.freeTries }

    private var clean: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var over: Bool { DemoRules.isOver(clean) }
    private var isSample: Bool { clean == DemoRules.sampleAmharic || clean == DemoRules.sampleEnglish }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(W(lang, "Hear it first", "መጀመሪያ ያዳምጡ")).font(Theme.heading).foregroundStyle(Theme.black)

            TextField(W(lang, "Type a sentence, or tap a sample below",
                        "አንድ ዓረፍተ ነገር ይጻፉ፣ ወይም ከታች ያለውን ናሙና ይንኩ"),
                      text: $text, axis: .vertical)
                .lineLimit(3...6)
                .lineSpacing(Theme.amharicLineSpacing)
                .padding(.vertical, 8)
                .field()
                .focused($typing)
                .disabled(busy)
                .opacity(busy ? 0.5 : 1)
                .accessibilityIdentifier("demoField")
                .onChange(of: text) { _, new in
                    if new.count > DemoRules.maxChars { text = String(new.prefix(DemoRules.maxChars)) }
                    ready = false
                    // Waits on the Create page after sign in, so nothing is typed twice.
                    UserDefaults.standard.set(text, forKey: PendingScript.key)
                }

            // A clear way to put the keyboard away, right under the field.
            if typing {
                HStack {
                    Spacer()
                    KeyboardDoneButton(id: "demoKeyboardDone") { typing = false }
                }
            }

            ChipRow {
                // The chosen language's sample first.
                if lang == .am {
                    Chip(title: "የአማርኛ ናሙና") { useSample(DemoRules.sampleAmharic) }
                        .accessibilityIdentifier("demoSampleAm")
                    Chip(title: "English sample") { useSample(DemoRules.sampleEnglish) }
                        .accessibilityIdentifier("demoSampleEn")
                } else {
                    Chip(title: "English sample") { useSample(DemoRules.sampleEnglish) }
                        .accessibilityIdentifier("demoSampleEn")
                    Chip(title: "Amharic sample") { useSample(DemoRules.sampleAmharic) }
                        .accessibilityIdentifier("demoSampleAm")
                }
            }
            .disabled(busy)
            .opacity(busy ? 0.4 : 1)

            Button {
                typing = false
                if ready { player.toggle() } else { Task { await play() } }
            } label: {
                BusyLabel(title: buttonTitle, busy: busy)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(busy || clean.isEmpty || over || (usedUp && !ready && !isSample))
            .accessibilityIdentifier("demoPlayButton")

            NoteText(text: T(DemoRules.meta(clean))).accessibilityIdentifier("demoMeta")
            status
        }
        .card(fill: Theme.grey)
        .onDisappear { player.stop() }
    }

    @ViewBuilder private var status: some View {
        if busy {
            // No clock (Geni): a moving bar and one short line.
            VStack(alignment: .leading, spacing: 6) {
                ProgressView().progressViewStyle(.linear).tint(Theme.black)
                Text(W(lang, "The first one takes a few minutes. After that, seconds.",
                       "የመጀመሪያው ጥቂት ደቂቃ ይወስዳል። ከዚያ በኋላ በሰከንዶች።"))
                    .font(Theme.small).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("demoProgress")
        }
        if quiet {
            NoteText(text: W(lang, "Turn up your phone volume to hear it.",
                             "ለመስማት የስልክዎን ድምፅ ይጨምሩ።"))
                .accessibilityIdentifier("demoVolumeNote")
        }
        if usedUp {
            NoteText(text: W(lang, "That was your 5 free tries. Tap Start free to make your own.",
                             "5 ነፃ ሙከራዎችዎን ጨርሰዋል። የራስዎን ለመስራት በነፃ ይጀምሩ የሚለውን ይንኩ።"))
                .accessibilityIdentifier("demoUsedUp")
        }
        if ready {
            Text(T("Ready")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                .accessibilityIdentifier("demoReady")
            NoteText(text: W(lang, "That is the Kinbir voice. Clone yours and your videos speak as you.",
                             "ይህ የቅንብር ድምፅ ነው። የራስዎን ይቅረጹ፣ ቪዲዮዎችዎም በእርስዎ ድምፅ ይናገራሉ።"))
        }
        if let problem {
            NoteText(text: problem).accessibilityIdentifier("demoProblem")
        }
    }

    private var buttonTitle: String {
        if busy { return reading ? T("Reading your text") : T("Waking the voice") }
        if ready { return player.isPlaying ? "Stop" : "Play" }
        return W(lang, "Hear it in the Kinbir voice", "በቅንብር ድምፅ ያዳምጡ")
    }

    /// The official samples are read through the same demo call as typed text. The server
    /// renders each once and keeps it, so they come back at once.
    private func useSample(_ sample: String) {
        guard !busy else { return }
        typing = false
        player.stop()
        text = sample
        Task { await play(sample) }
    }

    private func play(_ fixed: String? = nil) async {
        let words = fixed ?? clean
        guard !words.isEmpty, !DemoRules.isOver(words) else { return }
        let typed = fixed == nil && words != DemoRules.sampleAmharic && words != DemoRules.sampleEnglish
        if typed && usedUp { return }
        busy = true
        reading = false
        quiet = false
        problem = nil
        defer { busy = false }
        do {
            var ref = try await state.api.demoGenerate(text: words)
            var tries = 0
            while !ref.isDone {
                if ref.isFailed {
                    problem = ref.error.map(APIError.sentenceCase) ?? T("Could not read it this time. Try again.")
                    return
                }
                if ref.status == "running" { reading = true }
                tries += 1
                if tries > 120 {
                    problem = T("The voice is taking too long right now. Try again in a minute.")
                    return
                }
                try await Task.sleep(nanoseconds: UInt64(Launch.demoPollSeconds * 1_000_000_000))
                ref = try await state.api.demoStatus(id: ref.demoId)
            }
            let url = try await state.api.demoAudio(id: ref.demoId)
            if player.load(url: url) {
                ready = true
                if typed { tries += 1 }
                // A phone on low volume plays it unheard, so say so.
                quiet = !Launch.isMock && AVAudioSession.sharedInstance().outputVolume < 0.2
                player.toggle()
            } else {
                problem = T("The audio could not be played. Try again.")
            }
        } catch {
            problem = APIError.wrap(error).message
        }
    }
}
