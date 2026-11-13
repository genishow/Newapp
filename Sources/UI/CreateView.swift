import SwiftUI

/// The script page, in the website's three steps: your script, your voice, make the voiceover.
struct CreateView: View {
    @EnvironmentObject private var state: AppState
    /// The finished script: what the voice will read.
    @Binding var text: String
    @Binding var path: [Route]

    /// Where the script comes from. The same four choices as the website.
    private enum Tab: String, CaseIterable, Identifiable {
        case script, idea, source, link
        var id: String { rawValue }
    }

    private enum Work: Equatable {
        case idle, fetching, writing, starting, listening, transcribing
    }

    private enum WriteKind { case idea, source, refine }

    @State private var tab: Tab = .script
    @State private var work: Work = .idle
    @State private var problem: String?
    /// The idea, the text to rewrite, or the link, depending on the tab.
    @State private var idea = ""
    @State private var source = ""
    @State private var link = ""
    @State private var ownsLink = false
    @State private var faithful = false
    @State private var targetSec: Int? = 60
    @State private var estimate: Double?
    /// The script from before Kinbir wrote or changed it, for Undo.
    @State private var beforeRewrite: String?
    @State private var draftId: String?
    @State private var draftText: String?
    @State private var instruction = ""
    @State private var voice = VoiceOptions()
    @State private var seededVoice = false
    @State private var recent: [SavedScript] = []
    @StateObject private var recorder = SpeechRecorder()
    @FocusState private var editing: Bool
    @AppStorage("kinbir.language") private var languageRaw = Lang.am.rawValue

    private var language: Lang { Lang(rawValue: languageRaw) ?? .am }
    private var busy: Bool { work != .idle }
    private var script: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Reading time, by the website's own rule of thumb: about 7 syllables a second for
    /// Amharic and a little over 2 words a second for English.
    private var seconds: Double {
        ScriptMath.seconds(script, language: language)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                header

                stepTitle(1, T("Your script"))
                scriptStep

                stepTitle(2, T("Your voice"))
                voiceStep

                stepTitle(3, T("Make the voiceover"))
                makeStep

                if !recent.isEmpty {
                    recentList
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
        // A script is ready and a voice exists: wake the voice engine now, so the
        // voiceover does not start with its two minute warm-up.
        .task(id: script.isEmpty) {
            if !script.isEmpty, state.me?.hasVoice == true { await state.api.warmEngine() }
        }
        .task {
            voice.language = language
            await state.refresh()
            recent = (try? await state.api.recentScripts()) ?? []
        }
    }

    // MARK: frame

    private var header: some View {
        HStack {
            LogoMark(size: 36)
            Text("Kinbir").font(Theme.heading).foregroundStyle(Theme.black)
            Spacer()
            Pill(text: Fmt.credits(state.balance) + " " + T("credits"))
                .accessibilityIdentifier("creditsPill")
        }
    }

    private func stepTitle(_ number: Int, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(Theme.smallMedium).foregroundStyle(Theme.black)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.lime))
                .overlay(Circle().strokeBorder(Theme.black, lineWidth: 1))
            Text(title).font(Theme.heading).foregroundStyle(Theme.black)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: step 1

    private func title(for tab: Tab) -> String {
        switch tab {
        case .script: return language == .en ? T("English script") : T("Amharic text")
        case .idea: return T("Ask Kinbir")
        case .source: return language == .en ? T("Text to rewrite") : T("English text")
        case .link: return T("Article link")
        }
    }

    private var scriptStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(T("Language"), selection: $languageRaw) {
                ForEach(Lang.allCases) { Text(T($0.title)).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .disabled(busy)
            .accessibilityIdentifier("languagePicker")

            ChipRow {
                ForEach(Tab.allCases) { item in
                    Chip(title: title(for: item), selected: tab == item) {
                        tab = item
                        problem = nil
                    }
                    .accessibilityIdentifier("tab-" + item.rawValue)
                }
            }
            .disabled(busy)

            switch tab {
            case .script: scriptTab
            case .idea: ideaTab
            case .source: sourceTab
            case .link: linkTab
            }

            if let problem {
                ProblemCard(message: problem)
            }
        }
    }

    private var scriptTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language == .en ? T("Your English script. Type in it to edit.")
                                 : T("Your Amharic script. Type in it to edit."))
                .font(Theme.small).foregroundStyle(Theme.muted)
            editor($text, placeholder: language == .en ? T("Write or paste your script here.")
                                                         : T("Write or paste your Amharic script here."),
                   id: "scriptEditor")
                .disabled(work == .writing || work == .transcribing)

            HStack(spacing: 14) {
                if !script.isEmpty {
                    Text(Tf("About %@", Fmt.length(max(1, seconds))))
                        .font(Theme.smallMedium).foregroundStyle(Theme.black)
                        .accessibilityIdentifier("scriptCounter")
                }
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
            } else if work == .writing {
                NoteText(text: T("Writing your script. You can edit it when it is done."))
            }

            if !script.isEmpty && !busy {
                Text(T("Ask for a change")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                ChipRow {
                    ForEach(CreateView.rewrites, id: \.title) { item in
                        Chip(title: T(item.title)) {
                            instruction = item.instruction
                            editing = false
                            Task { await write(.refine) }
                        }
                    }
                }
                HStack(spacing: 10) {
                    TextField(T("Tell Kinbir what to change"), text: $instruction)
                        .field()
                        .accessibilityIdentifier("refineField")
                    Button(T("Apply")) {
                        editing = false
                        Task { await write(.refine) }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("refineButton")
                }
                NoteText(text: T("Each change costs credits. Undo brings the old script back."))
            }
        }
        .card(fill: Theme.grey, padding: 14)
    }

    private var ideaTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Say what the video is about. Kinbir writes the whole script."))
                .font(Theme.small).foregroundStyle(Theme.muted)
            TextField(T("For example: the history of Ethiopian coffee"), text: $idea, axis: .vertical)
                .lineLimit(2...5)
                .padding(.vertical, 8)
                .field()
                .accessibilityIdentifier("ideaField")
            ChipRow {
                ForEach(CreateView.ideas, id: \.title) { item in
                    Chip(title: T(item.title)) { idea = language == .en ? item.en : item.am }
                }
            }
            lengthRow
            writeButton(disabled: idea.trimmingCharacters(in: .whitespacesAndNewlines).count < 4, kind: .idea)
        }
        .card(fill: Theme.grey, padding: 14)
    }

    private var sourceTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language == .en ? T("Paste any text. Kinbir rewrites it as a video script.")
                                 : T("Paste English text. Kinbir writes it as a natural Amharic script."))
                .font(Theme.small).foregroundStyle(Theme.muted)
            editor($source, placeholder: T("Paste the text here."), id: "sourceEditor")
            Picker(T("Style"), selection: $faithful) {
                Text(T("Video style")).tag(false)
                Text(T("Close to the original")).tag(true)
            }
            .pickerStyle(.segmented)
            NoteText(text: faithful ? T("Keeps the original order and wording as much as possible.")
                                    : T("Recommended. Rebuilt to hold attention, at the length you choose."))
            if !faithful { lengthRow }
            writeButton(disabled: source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, kind: .source)
        }
        .card(fill: Theme.grey, padding: 14)
    }

    private var linkTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Paste a link to an article. Kinbir reads it and brings the text here."))
                .font(Theme.small).foregroundStyle(Theme.muted)
            TextField("https://", text: $link)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .field()
                .accessibilityIdentifier("linkField")
            Toggle(T("This page is mine, or I have permission to use it"), isOn: $ownsLink)
                .font(Theme.small).foregroundStyle(Theme.black).tint(Theme.black)
            Button {
                editing = false
                Task { await fetchArticle() }
            } label: {
                BusyLabel(title: work == .fetching ? T("Getting the article") : T("Get the article"),
                          busy: work == .fetching)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(busy || !ownsLink || !TextKind.isLink(link))
            .accessibilityIdentifier("fetchButton")
        }
        .card(fill: Theme.grey, padding: 14)
    }

    private func editor(_ binding: Binding<String>, placeholder: String, id: String) -> some View {
        ZStack(alignment: .topLeading) {
            if binding.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(Theme.body).foregroundStyle(Theme.muted)
                    .padding(.top, 16).padding(.leading, 13)
                    .allowsHitTesting(false)
            }
            TextEditor(text: binding)
                .font(Theme.body)
                .lineSpacing(Theme.amharicLineSpacing)
                .foregroundStyle(Theme.black)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 170)
                .focused($editing)
                .accessibilityIdentifier(id)
        }
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Theme.white))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
            .strokeBorder(Theme.black, lineWidth: 1))
    }

    private var lengthRow: some View {
        HStack {
            Text(T("Video length")).font(Theme.body).foregroundStyle(Theme.black)
            Spacer()
            Picker(T("Video length"), selection: $targetSec) {
                Text(T("Automatic")).tag(Int?.none)
                ForEach(ScriptOptions.lengths, id: \.self) { sec in
                    Text(Fmt.length(Double(sec))).tag(Int?.some(sec))
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.black)
            .accessibilityIdentifier("lengthPicker")
        }
    }

    /// The one button that spends credits on writing, with its price on it.
    private func writeButton(disabled: Bool, kind: WriteKind) -> some View {
        let price = estimate.map { " · ≈ " + Fmt.credits($0) + " " + T("credits") } ?? ""
        return Button {
            editing = false
            Task { await write(kind) }
        } label: {
            BusyLabel(title: work == .writing ? T("Writing") : T("Write the script") + price,
                      busy: work == .writing)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(busy || disabled)
        .accessibilityIdentifier("writeButton")
    }

    // MARK: step 2

    @ViewBuilder private var voiceStep: some View {
        if state.me != nil && state.me?.hasVoice == false {
            VStack(alignment: .leading, spacing: 10) {
                Text(T("Clone your voice first")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                Text(T("Read a short script on camera once. After that, every voiceover is in your voice."))
                    .font(Theme.small).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink(value: Route.enroll) { Text(T("Clone my voice")) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("cloneVoiceButton")
            }
            .card(fill: Theme.lime, padding: 14)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "waveform").font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.black)
                Text(state.activeVoice?.name ?? T("My voice"))
                    .font(Theme.bodyMedium).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("voiceLine")
                Spacer()
                NavigationLink(value: Route.voices) { Text(T("Change")) }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("changeVoiceButton")
            }
            .card(fill: Theme.white, padding: 14)
        }
    }

    // MARK: step 3

    private var voiceButtonTitle: String {
        if work == .starting { return T("Starting") }
        if script.isEmpty { return T("Make voiceover") }
        let credits = ScriptMath.voiceCredits(seconds: seconds)
        return T("Make voiceover") + " · ≈ " + Fmt.credits(credits) + " " + T("credits")
    }

    private var makeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if language == .en {
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

            Button {
                editing = false
                Task { await makeVoiceover() }
            } label: {
                BusyLabel(title: voiceButtonTitle, busy: work == .starting)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || script.isEmpty)
            .accessibilityIdentifier("voiceButton")

            if script.isEmpty {
                NoteText(text: T("Finish step 1 first. The button wakes up when there is a script."))
            } else {
                NoteText(text: Tf("This makes the audio, about %@. Next you can turn it into a video.", Fmt.length(max(1, seconds))))
            }
            if let limit = state.me?.trialMaxChars, language == .am, !script.isEmpty {
                NoteText(text: Tf("Free credits voice up to %@ Amharic characters at a time. This script has %@.",
                                  "\(limit)", "\(TextKind.ethiopicLetterCount(script))"))
            }
            if let me = state.me, me.hasVoice, me.balance < 3 {
                Text(Tf("You have %@ credits left, enough for about one short voiceover.", Fmt.credits(me.balance)) + " " + T(APIError.buyingNote))
                    .font(Theme.small).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .card(fill: Theme.grey, padding: 14)
                    .accessibilityIdentifier("lowBalanceCard")
            }
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Your recent scripts")).font(Theme.heading).foregroundStyle(Theme.black)
                .padding(.top, 6)
            ForEach(recent.prefix(5)) { item in
                Button {
                    beforeRewrite = text.isEmpty ? nil : text
                    text = item.body
                    tab = .script
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.body).font(Theme.small).foregroundStyle(Theme.black)
                            .lineSpacing(4).lineLimit(2).multilineTextAlignment(.leading)
                        Text(Fmt.ago(item.createdAt)).font(Theme.small).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(fill: Theme.white, padding: 12)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
    }

    private static let ideas: [(title: String, am: String, en: String)] = [
        ("News", "ስለ ዛሬው ዋና ዜና አጭር ማብራሪያ", "A short explainer about today's top news story"),
        ("History", "ስለ አድዋ ድል አጭር ታሪክ", "A short history of the Battle of Adwa"),
        ("Motivation", "ጠዋት ለመነሳት የሚያነሳሳ አጭር መልእክት", "A short motivational message for the morning"),
        ("Business", "ለአዲስ የቡና መሸጫ ማስታወቂያ", "An ad for a new coffee shop"),
        ("How to", "ገንዘብ ለመቆጠብ ሦስት ቀላል መንገዶች", "Three easy ways to save money"),
    ]

    private static let rewrites: [(title: String, instruction: String)] = [
        ("Shorter", "Make it shorter. Keep the main point."),
        ("Longer", "Make it longer with one more example."),
        ("More dramatic", "Make it more dramatic and gripping, with a stronger opening line."),
        ("Simpler", "Use simpler, everyday words and shorter sentences."),
        ("Stronger opening", "Rewrite only the first sentence as a hook that makes people keep watching."),
    ]

    // MARK: work

    /// What the price on the write button is for. Empty when nothing would be written.
    private var estimateKey: String {
        guard work == .idle else { return "" }
        switch tab {
        case .idea: return idea.isEmpty ? "" : "i|" + idea + "|\(targetSec ?? 0)"
        case .source: return source.isEmpty ? "" : "s|" + source + "|\(targetSec ?? 0)|\(faithful)"
        case .script, .link: return ""
        }
    }

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
        let input = tab == .idea ? idea : source
        guard tab == .idea || tab == .source, !input.isEmpty else { return }
        // Wait for typing to pause before asking the server.
        try? await Task.sleep(nanoseconds: 800_000_000)
        if Task.isCancelled { return }
        estimate = try? await state.api.rewriteEstimate(
            text: input, options: ScriptOptions(language: language, targetSec: faithful ? nil : targetSec))
    }

    private func write(_ kind: WriteKind) async {
        work = .writing
        problem = nil
        defer { work = .idle }
        let old = text
        var options = ScriptOptions(language: language, targetSec: targetSec)
        let input: String
        switch kind {
        case .idea:
            input = idea.trimmingCharacters(in: .whitespacesAndNewlines)
            options.fromIdea = true
        case .source:
            input = source.trimmingCharacters(in: .whitespacesAndNewlines)
            options.faithful = faithful
            if faithful { options.targetSec = nil }
        case .refine:
            input = old
            options.refineInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            // The script box fills as the text arrives.
            tab = .script
            text = ""
            let result = try await state.api.rewrite(text: input, options: options) { piece in
                text += piece
            }
            let final = (result.amharic ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
            beforeRewrite = old.isEmpty ? nil : old
            draftText = final
            text = final
            draftId = result.draftId
            if kind == .refine { instruction = "" }
            Haptics.success()
            await state.refresh()
        } catch {
            text = old
            if kind == .idea { tab = .idea } else if kind == .source { tab = .source }
            problem = state.report(error)
        }
    }

    private func fetchArticle() async {
        work = .fetching
        problem = nil
        defer { work = .idle }
        do {
            let article = try await state.api.extract(url: link.trimmingCharacters(in: .whitespacesAndNewlines))
            source = article.text
            tab = .source
        } catch {
            problem = state.report(error)
        }
    }

    private func makeVoiceover() async {
        guard state.me?.hasVoice != false else {
            problem = T("Clone your voice first. Your account has no voice yet.")
            return
        }
        work = .starting
        problem = nil
        defer { work = .idle }
        do {
            var options = voice
            options.language = language
            let submit = try await state.api.generate(text: script, draftId: draftId, voice: options)
            await state.refresh()
            path.append(.job(submit.jobId))
        } catch {
            tab = .script
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

/// Reading time and voiceover price, by the website's own rules of thumb.
enum ScriptMath {
    /// About 7.17 syllables a second for Amharic, 2.2 words a second for English.
    static func seconds(_ script: String, language: Lang) -> Double {
        if language == .en {
            return Double(script.split(whereSeparator: { $0.isWhitespace }).count) / 2.2
        }
        return Double(TextKind.ethiopicLetterCount(script)) / 7.17
    }

    /// About 2.5 credits a minute, in half credits, never under half a credit.
    static func voiceCredits(seconds: Double) -> Double {
        max(0.5, ((seconds / 60 * 2.5) * 2).rounded(.up) / 2)
    }
}
