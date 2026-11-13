import SwiftUI

/// The signed-out screen: hear the voice, then start.
struct WelcomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var showSignIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    // The first thing anyone sees: dark, with the lime sound bars moving.
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            LogoMark(size: 48)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Kinbir").font(Theme.heading).foregroundStyle(Theme.white)
                                Text("ቅንብር").font(Theme.small).foregroundStyle(Theme.grey)
                            }
                        }

                        Waveform(bars: 30, color: Theme.lime)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(T("Amharic voiceovers in"))
                                .font(Theme.title).foregroundStyle(Theme.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Marker(text: T("your own voice"))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("welcomeHeading")

                        Text(T("Write Amharic, or paste English or a link. Kinbir writes the script and reads it aloud in a voice cloned from you."))
                            .font(Theme.body).foregroundStyle(Theme.grey)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .card(fill: Theme.black, padding: 22)

                    if let notice = state.notice {
                        ProblemCard(message: notice)
                    }

                    DemoCard()

                    NoteText(text: T("Your first voiceovers are free. No card needed."))

                    HStack(spacing: 20) {
                        Link(T("Privacy"), destination: URL(string: "https://kinbir.com/privacy")!)
                        Link(T("Terms"), destination: URL(string: "https://kinbir.com/terms")!)
                    }
                    .font(Theme.smallMedium)
                    .foregroundStyle(Theme.black)
                    .padding(.top, 4)
                }
                .page()
            }
            .background(Theme.white)
            .safeAreaInset(edge: .bottom) {
                BottomBar {
                    Button(T("Start free")) { showSignIn = true }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("startButton")
                }
            }
            .navigationDestination(isPresented: $showSignIn) {
                SignInView()
            }
        }
    }
}

/// Type a sentence, or tap a sample, and hear it in the built-in Kinbir voice. No account needed.
struct DemoCard: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var player = AudioPlayer()
    // Starts empty: their own words are the point, and a sample is one tap away.
    @State private var text = ""
    @State private var busy = false
    @State private var reading = false
    @State private var ready = false
    @State private var problem: String?

    private var clean: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var over: Bool { DemoRules.isOver(clean) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Hear it first")).font(Theme.heading).foregroundStyle(Theme.black)

            TextField(T("የራስዎን ፅሁፍ በአማርኛ እዚህ ይጻፉ… Type your own Amharic or English here, or tap a sample below"),
                      text: $text, axis: .vertical)
                .lineLimit(3...6)
                .lineSpacing(Theme.amharicLineSpacing)
                .padding(.vertical, 8)
                .field()
                .accessibilityIdentifier("demoField")
                .onChange(of: text) { _, new in
                    if new.count > DemoRules.maxChars { text = String(new.prefix(DemoRules.maxChars)) }
                    ready = false
                }

            ChipRow {
                Chip(title: T("Amharic sample")) { useSample(DemoRules.sampleAmharic) }
                    .accessibilityIdentifier("demoSampleAm")
                Chip(title: T("English sample")) { useSample(DemoRules.sampleEnglish) }
                    .accessibilityIdentifier("demoSampleEn")
            }
            .disabled(busy)

            Button {
                if ready { player.toggle() } else { Task { await play() } }
            } label: {
                BusyLabel(title: buttonTitle, busy: busy)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(busy || clean.isEmpty || over)
            .accessibilityIdentifier("demoPlayButton")

            NoteText(text: T(DemoRules.meta(clean))).accessibilityIdentifier("demoMeta")
            status
        }
        .card(fill: Theme.grey)
        .onDisappear { player.stop() }
    }

    @ViewBuilder private var status: some View {
        if busy {
            NoteText(text: reading
                     ? T("Almost there, the voice is reading your words.")
                     : T("Starting the voice engine. The first listen of the day can take about two minutes, after that it is quick."))
        }
        if ready {
            Text(T("Ready")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                .accessibilityIdentifier("demoReady")
            NoteText(text: T("That is the Kinbir voice. Clone yours and your videos speak as you."))
        }
        if let problem {
            NoteText(text: problem).accessibilityIdentifier("demoProblem")
        }
    }

    private var buttonTitle: String {
        if busy { return reading ? T("Reading your text") : T("Waking the voice") }
        if ready { return player.isPlaying ? T("Pause") : T("Play again") }
        return T("Hear it in the Kinbir voice")
    }

    /// The official samples are read through the same demo call as typed text. The server
    /// renders each once and keeps it, so they come back at once.
    private func useSample(_ sample: String) {
        guard !busy else { return }
        player.stop()
        text = sample
        Task { await play(sample) }
    }

    private func play(_ fixed: String? = nil) async {
        let words = fixed ?? clean
        guard !words.isEmpty, !DemoRules.isOver(words) else { return }
        busy = true
        reading = false
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
                player.toggle()
            } else {
                problem = T("The audio could not be played. Try again.")
            }
        } catch {
            problem = APIError.wrap(error).message
        }
    }
}
