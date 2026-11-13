import SwiftUI

/// The signed-out screen: hear the voice, then start.
struct WelcomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var showSignIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    HStack(spacing: 12) {
                        LogoMark(size: 48)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Kinbir").font(Theme.heading).foregroundStyle(Theme.black)
                            Text("ቅንብር").font(Theme.small).foregroundStyle(Theme.muted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("Amharic voiceovers in"))
                            .font(Theme.title).foregroundStyle(Theme.black)
                        Marker(text: T("your own voice"))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("welcomeHeading")
                    .padding(.top, 8)

                    Text(T("Write Amharic, or paste English or a link. Kinbir writes the script and reads it aloud in a voice cloned from you."))
                        .font(Theme.body).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

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

/// Type a sentence, hear it in the built-in Kinbir voice. No account needed.
struct DemoCard: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var player = AudioPlayer()
    @State private var text = "ሰላም፣ እንኳን ወደ ቅንብር በደህና መጡ።"
    @State private var busy = false
    @State private var ready = false
    @State private var problem: String?

    private let limit = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Hear it first")).font(Theme.heading).foregroundStyle(Theme.black)

            TextField(T("Type a short Amharic sentence"), text: $text, axis: .vertical)
                .lineLimit(2...4)
                .lineSpacing(Theme.amharicLineSpacing)
                .padding(.vertical, 8)
                .field()
                .accessibilityIdentifier("demoField")
                .onChange(of: text) { _, new in
                    if new.count > limit { text = String(new.prefix(limit)) }
                    ready = false
                }

            Button {
                if ready { player.toggle() } else { Task { await play() } }
            } label: {
                BusyLabel(title: buttonTitle, busy: busy)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("demoPlayButton")

            if busy {
                NoteText(text: T("Preparing the voice. The first time can take a minute."))
            }
            if ready {
                Text(T("Ready")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("demoReady")
            }
            if let problem {
                NoteText(text: problem).accessibilityIdentifier("demoProblem")
            }
        }
        .card(fill: Theme.grey)
        .onDisappear { player.stop() }
    }

    private var buttonTitle: String {
        if busy { return T("Preparing") }
        if ready { return player.isPlaying ? T("Pause") : T("Play again") }
        return T("Play in the Kinbir voice")
    }

    private func play() async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            var ref = try await state.api.demoGenerate(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            var tries = 0
            while !ref.isDone {
                if ref.isFailed {
                    problem = ref.error ?? "The demo could not be made. Try again."
                    return
                }
                tries += 1
                if tries > 120 {
                    problem = T("This is taking too long. Try again in a moment.")
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
