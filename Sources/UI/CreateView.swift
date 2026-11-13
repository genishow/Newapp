import SwiftUI

/// The home of the app: a script box and one button.
struct CreateView: View {
    @EnvironmentObject private var state: AppState
    @Binding var text: String
    @Binding var path: [Route]

    private enum Work: Equatable {
        case idle, fetching, writing, starting, listening, transcribing
    }

    /// What the main button does with the text as it stands.
    private enum Action: Equatable {
        case nothing, fetch, write, voice
    }

    @State private var work: Work = .idle
    @State private var problem: String?
    @State private var estimate: Double?
    /// The text from before Kinbir wrote or changed the script, for Undo.
    @State private var beforeRewrite: String?
    /// Ties the voiceover to the script Kinbir wrote, while the text is unchanged.
    @State private var draftId: String?
    @State private var draftText: String?
    @State private var targetSec: Int?
    @State private var instruction = ""
    @State private var voice = VoiceOptions()
    @State private var seededVoice = false
    @StateObject private var recorder = SpeechRecorder()
    @FocusState private var editing: Bool
    @AppStorage("kinbir.language") private var languageRaw = Lang.am.rawValue

    private var language: Lang { Lang(rawValue: languageRaw) ?? .am }
    private var kind: TextKind { TextKind.detect(text) }
    private var busy: Bool { work != .idle }

    /// English text in an Amharic project is source material; in an English project it is the script.
    private var action: Action {
        switch kind {
        case .empty: return .nothing
        case .link: return .fetch
        case .english: return language == .en ? .voice : .write
        case .amharic: return .voice
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                header

                if state.me != nil && state.me?.hasVoice == false {
                    cloneCard
                }

                Picker(T("Language"), selection: $languageRaw) {
                    ForEach(Lang.allCases) { Text(T($0.title)).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .disabled(busy)
                .accessibilityIdentifier("languagePicker")

                if kind == .empty && !busy {
                    ideaRow
                }

                scriptCard

                if action == .write || action == .fetch {
                    lengthRow
                }
                if language == .en && action == .voice {
                    englishCard
                }

                if let problem {
                    ProblemCard(message: problem)
                }

                Button {
                    editing = false
                    Task { await mainAction() }
                } label: {
                    BusyLabel(title: buttonTitle, busy: busy && work != .listening)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || action == .nothing)
                .accessibilityIdentifier("mainActionButton")

                if looksLikeAnIdea && !busy {
                    Button(T("Write the script from this idea")) {
                        editing = false
                        Task { await writeScript(refine: false, fromIdea: true) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("writeFromIdeaButton")
                }

                belowButton

                if let me = state.me, me.hasVoice, me.balance < 3 {
                    Text(Tf("You have %@ credits left, enough for about one short voiceover.", Fmt.credits(me.balance)) + " " + T(APIError.buyingNote))
                        .font(Theme.small).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                        .card(fill: Theme.grey, padding: 14)
                        .accessibilityIdentifier("lowBalanceCard")
                }

                if action == .voice && !busy {
                    refineCard
                }
            }
            .page()
        }
        .background(Theme.white)
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(T("Done")) { editing = false }
                    .accessibilityIdentifier("keyboardDone")
            }
        }
        .onChange(of: text) { _, new in
            state.saveDraft(new)
            if new != draftText { draftId = nil }
        }
        .onChange(of: state.me) { _, me in seedVoice(from: me) }
        .onChange(of: languageRaw) { _, _ in
            voice.language = language
            problem = nil
        }
        .task(id: estimateKey) { await loadEstimate() }
        .task {
            voice.language = language
            await state.refresh()
        }
    }

    // MARK: pieces

    private var header: some View {
        HStack {
            LogoMark(size: 36)
            Text("Kinbir").font(Theme.heading).foregroundStyle(Theme.black)
            Spacer()
            Pill(text: Fmt.credits(state.balance) + " " + T("credits"))
                .accessibilityIdentifier("creditsPill")
        }
    }

    private var cloneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Clone your voice first")).font(Theme.heading).foregroundStyle(Theme.black)
            Text(T("Read a short script on camera once. After that, every voiceover is in your voice."))
                .font(Theme.body).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: Route.enroll) {
                Text(T("Clone my voice"))
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("cloneVoiceButton")
        }
        .card(fill: Theme.lime)
    }

    private var placeholder: String {
        language == .en ? "Write or paste your English script, or paste a link."
                        : "Write Amharic, or paste English or a link."
    }

    private var scriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(Theme.body).foregroundStyle(Theme.muted)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(Theme.body)
                    .lineSpacing(Theme.amharicLineSpacing)
                    .foregroundStyle(Theme.black)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 200)
                    .focused($editing)
                    .disabled(work == .writing || work == .transcribing)
                    .accessibilityIdentifier("scriptEditor")
            }

            HStack(spacing: 12) {
                Text(kindLabel).font(Theme.smallMedium).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("kindLabel")
                Spacer()
                if beforeRewrite != nil && !busy {
                    Button(T("Undo")) {
                        if let old = beforeRewrite { text = old }
                        beforeRewrite = nil
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("undoButton")
                }
                if !text.isEmpty && !busy {
                    Button(T("Clear")) {
                        text = ""
                        beforeRewrite = nil
                        problem = nil
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("clearButton")
                }
                if text.isEmpty && !busy {
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first {
                            DispatchQueue.main.async { text = first }
                        }
                    }
                    .labelStyle(.titleOnly)
                    .tint(Theme.black)
                    .buttonBorderShape(.capsule)
                }
                // Speech to text understands Amharic only.
                if language == .am && (work == .idle || work == .listening) {
                    Button(work == .listening ? T("Stop") : T("Speak")) {
                        Task { await toggleSpeech() }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("speakButton")
                }
            }
            if work == .listening {
                NoteText(text: T("Listening. Speak in Amharic, then tap Stop."))
            } else if work == .transcribing {
                NoteText(text: T("Turning your words into text."))
            }
        }
        .card(fill: Theme.grey, padding: 14)
    }

    private var lengthRow: some View {
        HStack {
            Text(T("Script length")).font(Theme.body).foregroundStyle(Theme.black)
            Spacer()
            Picker(T("Script length"), selection: $targetSec) {
                Text(T("Automatic")).tag(Int?.none)
                ForEach(ScriptOptions.lengths, id: \.self) { sec in
                    Text(Fmt.length(Double(sec))).tag(Int?.some(sec))
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.black)
            .accessibilityIdentifier("lengthPicker")
        }
        .card(fill: Theme.white, padding: 12)
    }

    private var englishCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Reading speed")).font(Theme.smallMedium).foregroundStyle(Theme.black)
            Picker(T("Reading speed"), selection: $voice.pace) {
                ForEach(VoiceOptions.paces, id: \.self) { Text(T($0.capitalized)).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(T("Emphasis on pauses")).font(Theme.smallMedium).foregroundStyle(Theme.black)
            Picker(T("Emphasis"), selection: $voice.emphasis) {
                ForEach(VoiceOptions.emphases, id: \.self) { Text(T($0.capitalized)).tag($0) }
            }
            .pickerStyle(.segmented)
            if state.activeVoice?.isAmharic == true {
                NoteText(text: T("This voice was cloned reading Amharic, so its English has an Amharic accent. Clone an English reading for a native sound."))
            }
        }
        .card(fill: Theme.white, padding: 14)
        .accessibilityIdentifier("englishCard")
    }

    /// A short line in the project's language is more likely an idea than a finished script.
    private var looksLikeAnIdea: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return action == .voice && trimmed.count >= 4 && trimmed.count <= 160
    }

    private static let ideas: [(title: String, am: String, en: String)] = [
        ("News", "ስለ ዛሬው ዋና ዜና አጭር ማብራሪያ ቪዲዮ", "A short explainer about today's top news story"),
        ("History", "ስለ አድዋ ድል አጭር ታሪክ", "A short history of the Battle of Adwa"),
        ("Motivation", "ጠዋት ለመነሳት የሚያነሳሳ አጭር መልእክት", "A short motivational message for the morning"),
        ("Business", "ለአዲስ የቡና መሸጫ ማስታወቂያ", "An ad for a new coffee shop"),
        ("How to", "ገንዘብ ለመቆጠብ ሦስት ቀላል መንገዶች", "Three easy ways to save money"),
    ]

    private var ideaRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("Need an idea? Tap one, then change it to yours."))
                .font(Theme.small).foregroundStyle(Theme.muted)
            ChipRow {
                ForEach(CreateView.ideas, id: \.title) { idea in
                    Chip(title: T(idea.title)) {
                        text = language == .en ? idea.en : idea.am
                    }
                }
            }
        }
        .accessibilityIdentifier("ideaRow")
    }

    private static let rewrites: [(title: String, instruction: String)] = [
        ("Shorter", "Make it shorter. Keep the main point."),
        ("Longer", "Make it longer with one more example."),
        ("More dramatic", "Make it more dramatic and gripping, with a stronger opening line."),
        ("Simpler", "Use simpler, everyday words and shorter sentences."),
        ("Stronger opening", "Rewrite only the first sentence as a hook that makes people keep watching."),
    ]

    private var refineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Change the script")).font(Theme.smallMedium).foregroundStyle(Theme.black)
            ChipRow {
                ForEach(CreateView.rewrites, id: \.title) { item in
                    Chip(title: T(item.title)) {
                        instruction = item.instruction
                        editing = false
                        Task { await writeScript(refine: true) }
                    }
                }
            }
            TextField(T("Tell Kinbir what to change"), text: $instruction, axis: .vertical)
                .lineLimit(1...3)
                .padding(.vertical, 8)
                .field()
                .accessibilityIdentifier("refineField")
            Button(T("Change it")) {
                editing = false
                Task { await writeScript(refine: true) }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("refineButton")
            NoteText(text: T("For example: make it shorter, or start with a question. Each change costs credits."))
        }
        .card(fill: Theme.white, padding: 14)
    }

    @ViewBuilder private var belowButton: some View {
        if action == .write, let estimate, !busy {
            NoteText(text: Tf("Writing the Amharic script costs about %@ credits.", Fmt.credits(estimate)))
                .accessibilityIdentifier("estimateNote")
        }
        if work == .writing {
            NoteText(text: T("Writing your script. You can edit it when it is done."))
        }
        if let limit = state.me?.trialMaxChars, kind == .amharic, language == .am {
            let used = TextKind.ethiopicLetterCount(text)
            NoteText(text: Tf("Free credits voice up to %@ Amharic characters at a time. This script has %@.", "\(limit)", "\(used)"))
        }
        if let active = state.activeVoice {
            HStack(spacing: 8) {
                Text(T("Voice: ") + (active.name ?? T("My voice")))
                    .font(Theme.small).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("voiceLine")
                NavigationLink(value: Route.voices) { Text(T("Change")) }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("changeVoiceButton")
            }
        }
    }

    private var kindLabel: String {
        switch kind {
        case .empty: return T("Nothing yet")
        case .link: return T("Link")
        case .english: return language == .en ? T("English script") : T("English text")
        case .amharic: return T("Amharic script")
        }
    }

    private var buttonTitle: String {
        switch work {
        case .fetching: return T("Getting the article")
        case .writing: return T("Writing")
        case .starting: return T("Starting")
        case .transcribing: return T("One moment")
        case .idle, .listening:
            switch action {
            case .fetch: return T("Get the article")
            case .write: return T("Write Amharic script")
            case .nothing, .voice: return T("Make voiceover")
            }
        }
    }

    /// Changes only when an estimate is worth asking for again.
    private var estimateKey: String {
        action == .write && work == .idle ? text + "|\(targetSec ?? 0)" : ""
    }

    // MARK: actions

    /// Preselects the English speed and emphasis used last time.
    private func seedVoice(from me: WhoAmI?) {
        guard !seededVoice, let me else { return }
        seededVoice = true
        if let pace = me.enPace, VoiceOptions.paces.contains(pace) { voice.pace = pace }
        if let emphasis = me.enEmphasis, VoiceOptions.emphases.contains(emphasis) {
            voice.emphasis = emphasis
        }
    }

    private func loadEstimate() async {
        estimate = nil
        let snapshot = text
        guard action == .write else { return }
        // Wait for typing to pause before asking the server.
        try? await Task.sleep(nanoseconds: 800_000_000)
        if Task.isCancelled { return }
        estimate = try? await state.api.rewriteEstimate(
            text: snapshot, options: ScriptOptions(language: language, targetSec: targetSec))
    }

    private func mainAction() async {
        problem = nil
        switch action {
        case .nothing:
            return
        case .fetch:
            await fetchArticle()
        case .write:
            await writeScript(refine: false)
        case .voice:
            await makeVoiceover()
        }
    }

    private func fetchArticle() async {
        work = .fetching
        defer { work = .idle }
        do {
            let link = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let article = try await state.api.extract(url: link)
            beforeRewrite = link
            text = article.text
        } catch {
            problem = state.report(error)
        }
    }

    private func writeScript(refine: Bool, fromIdea: Bool = false) async {
        work = .writing
        problem = nil
        defer { work = .idle }
        let source = text
        var options = ScriptOptions(language: language, targetSec: targetSec)
        options.fromIdea = fromIdea
        if refine {
            options.refineInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            // The editor fills with the script as it arrives.
            text = ""
            let result = try await state.api.rewrite(text: source, options: options) { piece in
                text += piece
            }
            let final = (result.amharic ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
            beforeRewrite = source
            draftText = final
            text = final
            draftId = result.draftId
            if refine { instruction = "" }
            Haptics.success()
            await state.refresh()
        } catch {
            text = source
            problem = state.report(error)
        }
    }

    private func makeVoiceover() async {
        guard state.me?.hasVoice != false else {
            problem = T("Clone your voice first. Your account has no voice yet.")
            return
        }
        work = .starting
        defer { work = .idle }
        do {
            let script = text.trimmingCharacters(in: .whitespacesAndNewlines)
            var options = voice
            options.language = language
            let submit = try await state.api.generate(text: script, draftId: draftId, voice: options)
            await state.refresh()
            path.append(.job(submit.jobId))
        } catch {
            problem = state.report(error)
        }
    }

    private func toggleSpeech() async {
        problem = nil
        if work == .listening {
            guard let file = recorder.stop() else {
                work = .idle
                return
            }
            work = .transcribing
            defer { work = .idle }
            do {
                let heard = try await state.api.transcribe(audioURL: file)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if heard.isEmpty {
                    problem = T("Nothing was heard. Try again a little closer to the phone.")
                } else {
                    text = text.isEmpty ? heard : text + " " + heard
                }
            } catch {
                problem = state.report(error)
            }
            return
        }
        editing = false
        if await recorder.start() {
            work = .listening
        } else {
            problem = T("Kinbir needs the microphone to hear you. Allow it in Settings, then try again.")
        }
    }
}
