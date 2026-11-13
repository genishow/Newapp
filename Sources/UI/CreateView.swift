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

                Picker("Language", selection: $languageRaw) {
                    ForEach(Lang.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .disabled(busy)
                .accessibilityIdentifier("languagePicker")

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

                belowButton

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
                Button("Done") { editing = false }
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
            Pill(text: Fmt.credits(state.balance) + " credits")
                .accessibilityIdentifier("creditsPill")
        }
    }

    private var cloneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clone your voice first").font(Theme.heading).foregroundStyle(Theme.black)
            Text("Read a short script on camera once. After that, every voiceover is in your voice.")
                .font(Theme.body).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: Route.enroll) {
                Text("Clone my voice")
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
                Text(kindLabel).font(Theme.small.weight(.medium)).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("kindLabel")
                Spacer()
                if beforeRewrite != nil && !busy {
                    Button("Undo") {
                        if let old = beforeRewrite { text = old }
                        beforeRewrite = nil
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("undoButton")
                }
                if !text.isEmpty && !busy {
                    Button("Clear") {
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
                    Button(work == .listening ? "Stop" : "Speak") {
                        Task { await toggleSpeech() }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("speakButton")
                }
            }
            if work == .listening {
                NoteText(text: "Listening. Speak in Amharic, then tap Stop.")
            } else if work == .transcribing {
                NoteText(text: "Turning your words into text.")
            }
        }
        .card(fill: Theme.grey, padding: 14)
    }

    private var lengthRow: some View {
        HStack {
            Text("Script length").font(Theme.body).foregroundStyle(Theme.black)
            Spacer()
            Picker("Script length", selection: $targetSec) {
                Text("Automatic").tag(Int?.none)
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
            Text("Reading speed").font(Theme.small.weight(.medium)).foregroundStyle(Theme.black)
            Picker("Reading speed", selection: $voice.pace) {
                ForEach(VoiceOptions.paces, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Emphasis on pauses").font(Theme.small.weight(.medium)).foregroundStyle(Theme.black)
            Picker("Emphasis", selection: $voice.emphasis) {
                ForEach(VoiceOptions.emphases, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            if state.activeVoice?.isAmharic == true {
                NoteText(text: "This voice was cloned reading Amharic, so its English has an Amharic accent. Clone an English reading for a native sound.")
            }
        }
        .card(fill: Theme.white, padding: 14)
        .accessibilityIdentifier("englishCard")
    }

    private var refineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Change the script").font(Theme.small.weight(.medium)).foregroundStyle(Theme.black)
            TextField("Tell Kinbir what to change", text: $instruction, axis: .vertical)
                .lineLimit(1...3)
                .padding(.vertical, 8)
                .field()
                .accessibilityIdentifier("refineField")
            Button("Change it") {
                editing = false
                Task { await writeScript(refine: true) }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("refineButton")
            NoteText(text: "For example: make it shorter, or start with a question. Each change costs credits.")
        }
        .card(fill: Theme.white, padding: 14)
    }

    @ViewBuilder private var belowButton: some View {
        if action == .write, let estimate, !busy {
            NoteText(text: "Writing the Amharic script costs about \(Fmt.credits(estimate)) credits.")
                .accessibilityIdentifier("estimateNote")
        }
        if work == .writing {
            NoteText(text: "Writing your script. You can edit it when it is done.")
        }
        if let limit = state.me?.trialMaxChars, kind == .amharic, language == .am {
            let used = TextKind.ethiopicLetterCount(text)
            NoteText(text: "Free credits voice up to \(limit) Amharic characters at a time. This script has \(used).")
        }
        if let active = state.activeVoice {
            HStack(spacing: 8) {
                Text("Voice: " + (active.name ?? "My voice"))
                    .font(Theme.small).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("voiceLine")
                NavigationLink(value: Route.voices) { Text("Change") }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("changeVoiceButton")
            }
        }
    }

    private var kindLabel: String {
        switch kind {
        case .empty: return "Nothing yet"
        case .link: return "Link"
        case .english: return language == .en ? "English script" : "English text"
        case .amharic: return "Amharic script"
        }
    }

    private var buttonTitle: String {
        switch work {
        case .fetching: return "Getting the article"
        case .writing: return "Writing"
        case .starting: return "Starting"
        case .transcribing: return "One moment"
        case .idle, .listening:
            switch action {
            case .fetch: return "Get the article"
            case .write: return "Write Amharic script"
            case .nothing, .voice: return "Make voiceover"
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

    private func writeScript(refine: Bool) async {
        work = .writing
        problem = nil
        defer { work = .idle }
        let source = text
        var options = ScriptOptions(language: language, targetSec: targetSec)
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
            await state.refresh()
        } catch {
            text = source
            problem = state.report(error)
        }
    }

    private func makeVoiceover() async {
        guard state.me?.hasVoice != false else {
            problem = "Clone your voice first. Your account has no voice yet."
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
                    problem = "Nothing was heard. Try again a little closer to the phone."
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
            problem = "Kinbir needs the microphone to hear you. Allow it in Settings, then try again."
        }
    }
}
