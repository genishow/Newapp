import SwiftUI

/// The main screen: one script box and one button. Everything else is one tap away
/// in "Write it for me" or "More options".
struct CreateView: View {
    @EnvironmentObject private var state: AppState
    /// The finished script: what the voice will read.
    @Binding var text: String
    @Binding var path: [Route]

    private enum Work: Equatable {
        case idle, fetching, writing, starting, listening, transcribing
    }

    @State private var work: Work = .idle
    @State private var problem: String?
    /// The script from before Kinbir wrote or changed it, for Undo.
    @State private var beforeRewrite: String?
    @State private var draftId: String?
    @State private var draftText: String?
    @State private var voice = VoiceOptions()
    @State private var seededVoice = false
    @State private var recent: [SavedScript] = []
    @State private var showWriter = false
    @State private var showMore = false
    @State private var showCredits = false
    @State private var keepProblem = false
    @StateObject private var recorder = SpeechRecorder()
    @FocusState private var editing: Bool
    /// The voiceover's language. It starts as the app's language and lives in More options.
    @AppStorage("kinbir.language") private var languageRaw = ""

    private var language: Lang {
        Lang(rawValue: languageRaw) ?? Lang.matchingInterface
    }
    private var busy: Bool { work != .idle }
    private var script: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var needsVoice: Bool { state.me != nil && state.me?.hasVoice == false }
    private var seconds: Double { ScriptMath.seconds(script, language: language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if needsVoice {
                    voiceHero
                }

                Text(T("What will you say?")).screenTitle(amharic: A("What will you say?"))

                editorCard

                HStack(spacing: 10) {
                    if language == .am {
                        pill(icon: work == .listening ? "stop.fill" : "mic.fill",
                             title: work == .listening ? T("Stop") : T("Speak"),
                             id: "speakButton") {
                            Task { await toggleSpeech() }
                        }
                        .disabled(busy && work != .listening)
                    }
                    pill(icon: "sparkles", title: T("Write it for me"), id: "writeForMeButton") {
                        editing = false
                        showWriter = true
                    }
                    .disabled(busy)
                }

                if !needsVoice {
                    NavigationLink(value: Route.voices) {
                        OptionRow(icon: "waveform", title: T("Voice"),
                                  value: state.activeVoice?.name ?? T("My voice"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("voiceLine")
                }

                Button {
                    editing = false
                    showMore = true
                } label: {
                    OptionRow(icon: "slider.horizontal.3", title: T("More options"),
                              detail: nil)
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityIdentifier("moreOptionsButton")

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
        .safeAreaInset(edge: .bottom) {
            BottomBar(problem: problem) { mainButton }
        }
        .sheet(isPresented: $showWriter) {
            WriteSheet(language: language) { request in
                showWriter = false
                Task { await write(request) }
            }
            .environmentObject(state)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCredits) {
            CreditsSheet(balance: state.balance) { showCredits = false }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMore) {
            MoreOptionsSheet(languageRaw: $languageRaw, voice: $voice, hasScript: !script.isEmpty,
                             amharicVoice: state.activeVoice?.isAmharic == true,
                             onImprove: { instruction in
                                 showMore = false
                                 Task { await write(WriteRequest(kind: .refine, input: instruction)) }
                             },
                             onClose: { showMore = false })
                .environmentObject(state)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: text) { _, new in
            state.saveDraft(new)
            if new != draftText { draftId = nil }
            // A failed rewrite puts the old text back, and the reason it failed must stay
            // on screen.
            if keepProblem { keepProblem = false } else { problem = nil }
        }
        .onChange(of: state.me) { _, me in seedVoice(from: me) }
        // A script is ready and a voice exists: wake the voice engine now, so the
        // voiceover does not start with its two minute warm-up.
        .task(id: script.isEmpty) {
            if !script.isEmpty, state.me?.hasVoice == true { await state.api.warmEngine() }
        }
        .task {
            await state.refresh()
            recent = (try? await state.api.recentScripts()) ?? []
        }
    }

    // MARK: pieces

    private var header: some View {
        HStack {
            LogoMark(size: 36)
            Text("Kinbir").font(Theme.heading).foregroundStyle(Theme.black)
            Spacer()
            Button {
                showCredits = true
            } label: {
                Pill(text: Fmt.credits(state.balance) + " " + T("credits"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("creditsPill")
        }
    }

    /// Shown only until the user has a voice: the one thing to do first.
    private var voiceHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("First, record your voice")).font(Theme.heading).foregroundStyle(Theme.black)
            Text(T("Read a few lines on camera, about 30 seconds. After that, everything is in your voice."))
                .font(Theme.body).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: Route.enroll) { Text(T("Record my voice")) }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("cloneVoiceButton")
        }
        .card(fill: Theme.lime)
    }

    private var placeholder: String {
        language == .en ? T("Write or paste your script here.")
                        : T("Write or paste your Amharic script here.")
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    .frame(minHeight: 190)
                    .focused($editing)
                    .disabled(work == .writing || work == .transcribing || work == .fetching)
                    .accessibilityIdentifier("scriptEditor")
            }

            HStack(spacing: 14) {
                if let status = statusLine {
                    ProgressView().controlSize(.small).tint(Theme.black)
                    Text(status).font(Theme.small).foregroundStyle(Theme.black)
                } else if !script.isEmpty {
                    Text(Tf("About %@", Fmt.length(max(1, seconds))))
                        .font(Theme.small).foregroundStyle(Theme.muted)
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
                        beforeRewrite = text
                        text = ""
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("clearButton")
                }
            }
            .frame(minHeight: 28)
        }
        .card(fill: Theme.grey, padding: 14)
    }

    private var statusLine: String? {
        switch work {
        case .listening: return T("Listening. Speak in Amharic, then tap Stop.")
        case .transcribing: return T("Turning your words into text.")
        case .writing: return T("Writing your script")
        case .fetching: return T("Getting the article")
        case .idle, .starting: return nil
        }
    }

    private func pill(icon: String, title: String, id: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(title).font(Theme.bodyMedium).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.black)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Capsule().fill(Theme.white))
            .overlay(Capsule().strokeBorder(Theme.black, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// The one lime button, always in reach. It says what it will do and what it costs.
    @ViewBuilder private var mainButton: some View {
        if needsVoice {
            NavigationLink(value: Route.enroll) { Text(T("Record my voice")) }
                .buttonStyle(PrimaryButtonStyle())
        } else {
            Button {
                editing = false
                Task { await makeVoiceover() }
            } label: {
                BusyLabel(title: mainTitle, busy: work == .starting)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || script.isEmpty)
            .accessibilityIdentifier("voiceButton")
        }
    }

    private var mainTitle: String {
        if work == .starting { return T("Starting") }
        if script.isEmpty { return T("Make voiceover") }
        return T("Make voiceover") + " · ≈ " + Fmt.credits(ScriptMath.voiceCredits(seconds: seconds))
            + " " + T("credits")
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Recent scripts")).font(Theme.heading).foregroundStyle(Theme.black)
            ForEach(recent.prefix(5)) { item in
                Button {
                    beforeRewrite = text.isEmpty ? nil : text
                    text = item.body
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
        .accessibilityIdentifier("recentList")
    }

    // MARK: work

    private func seedVoice(from me: WhoAmI?) {
        guard !seededVoice, let me else { return }
        seededVoice = true
        if let pace = me.enPace, VoiceOptions.paces.contains(pace) { voice.pace = pace }
        if let emphasis = me.enEmphasis, VoiceOptions.emphases.contains(emphasis) {
            voice.emphasis = emphasis
        }
    }

    /// Writes or changes the script. A link is fetched and written in one go.
    private func write(_ request: WriteRequest) async {
        problem = nil
        let old = text
        var input = request.input.trimmingCharacters(in: .whitespacesAndNewlines)
        var options = ScriptOptions(language: language, targetSec: request.targetSec)
        do {
            switch request.kind {
            case .idea:
                options.fromIdea = true
            case .source:
                options.faithful = request.faithful
                if request.faithful { options.targetSec = nil }
            case .link:
                work = .fetching
                input = try await state.api.extract(url: input).text
            case .refine:
                options.refineInstruction = input
                options.targetSec = nil
                input = old
            }
            work = .writing
            // The script box fills as the text arrives.
            text = ""
            let result = try await state.api.rewrite(text: input, options: options) { piece in
                text += piece
            }
            let final = (result.amharic ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
            beforeRewrite = old.isEmpty ? nil : old
            draftText = final
            text = final
            draftId = result.draftId
            work = .idle
            Haptics.success()
            await state.refresh()
        } catch {
            work = .idle
            keepProblem = text != old
            text = old
            problem = state.report(error)
        }
    }

    private func makeVoiceover() async {
        work = .starting
        problem = nil
        defer { work = .idle }
        // The script must be in the voiceover's language, or the voice reads nonsense.
        let kind = TextKind.detect(script)
        if language == .am && kind == .english {
            problem = T("This script is in English. Tap Write it for me to turn it into Amharic, or switch the voiceover language in More options.")
            return
        }
        if language == .en && kind == .amharic {
            problem = T("This script is in Amharic. Switch the voiceover language to Amharic in More options.")
            return
        }
        do {
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

/// What "Write it for me" asks Kinbir to do.
struct WriteRequest {
    enum Kind { case idea, source, link, refine }
    var kind: Kind
    var input: String
    var targetSec: Int?
    var faithful = false
}

/// Three ways to get a script without writing it: an idea, English text, or a link.
struct WriteSheet: View {
    @EnvironmentObject private var state: AppState
    let language: Lang
    let onWrite: (WriteRequest) -> Void

    @State private var kind: WriteRequest.Kind?
    @State private var input = ""
    @State private var targetSec: Int? = 60
    @State private var faithful = false
    @State private var ownsLink = false
    @State private var estimate: Double?
    @FocusState private var typing: Bool

    private static let ideas: [(title: String, am: String, en: String)] = [
        ("News", "ስለ ዛሬው ዋና ዜና አጭር ማብራሪያ", "A short explainer about today's top news story"),
        ("History", "ስለ አድዋ ድል አጭር ታሪክ", "A short history of the Battle of Adwa"),
        ("Motivation", "ጠዋት ለመነሳት የሚያነሳሳ አጭር መልእክት", "A short motivational message for the morning"),
        ("Business", "ለአዲስ የቡና መሸጫ ማስታወቂያ", "An ad for a new coffee shop"),
        ("Tips", "ገንዘብ ለመቆጠብ ሦስት ቀላል መንገዶች", "Three easy ways to save money"),
    ]

    private var clean: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var ready: Bool {
        switch kind {
        case .idea: return clean.count >= 4
        case .source: return !clean.isEmpty
        case .link: return ownsLink && TextKind.isLink(clean)
        case .refine, .none: return false
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    if let kind {
                        form(kind)
                    } else {
                        chooser
                    }
                }
                .page()
            }
            .background(Theme.white)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                if kind != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(T("Back")) {
                            kind = nil
                            input = ""
                            estimate = nil
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(T("Done")) { typing = false }
                        .accessibilityIdentifier("sheetKeyboardDone")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if kind != nil {
                    BottomBar {
                        Button {
                            guard let kind else { return }
                            let length = (kind == .source && faithful) ? nil : targetSec
                            onWrite(WriteRequest(kind: kind, input: clean, targetSec: length,
                                                 faithful: kind == .source && faithful))
                        } label: {
                            Text(buttonTitle)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!ready)
                        .accessibilityIdentifier("writeButton")
                    }
                }
            }
        }
        .tint(Theme.black)
        .task(id: estimateKey) { await loadEstimate() }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Write it for me")).screenTitle(amharic: A("Write it for me"))
                .accessibilityIdentifier("writerHeading")
            Text(T("Kinbir writes the script. You can change it afterwards."))
                .font(Theme.body).foregroundStyle(Theme.muted)
            choice(.idea, icon: "lightbulb", title: T("From an idea"),
                   detail: T("Say what the video is about in one line."))
            choice(.source, icon: "doc.text", title: language == .en ? T("From any text") : T("From English text"),
                   detail: language == .en ? T("Paste text and get a video script.")
                                           : T("Paste English and get a natural Amharic script."))
            choice(.link, icon: "link", title: T("From a link"),
                   detail: T("Paste a link to an article."))
        }
    }

    private func choice(_ value: WriteRequest.Kind, icon: String, title: String, detail: String) -> some View {
        Button {
            kind = value
        } label: {
            OptionRow(icon: icon, title: title, detail: detail)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("writeChoice-\(value)")
    }

    @ViewBuilder private func form(_ kind: WriteRequest.Kind) -> some View {
        switch kind {
        case .idea:
            Text(T("What is the video about?")).screenTitle(amharic: A("What is the video about?"))
            TextField(T("For example: the history of Ethiopian coffee"), text: $input, axis: .vertical)
                .lineLimit(3...6)
                .padding(.vertical, 8)
                .field()
                .focused($typing)
                .accessibilityIdentifier("ideaField")
            ChipRow {
                ForEach(WriteSheet.ideas, id: \.title) { item in
                    Chip(title: T(item.title)) { input = language == .en ? item.en : item.am }
                }
            }
            lengthRow
        case .source:
            Text(language == .en ? T("Paste the text") : T("Paste the English text"))
                .screenTitle()
            TextEditor(text: $input)
                .font(Theme.body)
                .foregroundStyle(Theme.black)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .focused($typing)
                .card(fill: Theme.grey, padding: 12)
                .accessibilityIdentifier("sourceEditor")
            Toggle(T("Keep it close to the original"), isOn: $faithful)
                .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
            if !faithful { lengthRow }
        case .link:
            Text(T("Paste the link")).screenTitle(amharic: A("Paste the link"))
            TextField("https://", text: $input)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .field()
                .focused($typing)
                .accessibilityIdentifier("linkField")
            Toggle(T("This page is mine, or I have permission to use it"), isOn: $ownsLink)
                .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
            lengthRow
        case .refine:
            EmptyView()
        }
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
        .card(fill: Theme.grey, padding: 12)
    }

    private var buttonTitle: String {
        let price = estimate.map { " · ≈ " + Fmt.credits($0) + " " + T("credits") } ?? ""
        return T("Write the script") + price
    }

    private var estimateKey: String {
        guard kind == .idea || kind == .source, !clean.isEmpty else { return "" }
        return clean + "|\(targetSec ?? 0)|\(faithful)"
    }

    private func loadEstimate() async {
        estimate = nil
        guard !estimateKey.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 800_000_000)
        if Task.isCancelled { return }
        estimate = try? await state.api.rewriteEstimate(
            text: clean, options: ScriptOptions(language: language, targetSec: faithful ? nil : targetSec))
    }
}

/// The things most people never need, kept off the main screen.
struct MoreOptionsSheet: View {
    @Binding var languageRaw: String
    @Binding var voice: VoiceOptions
    let hasScript: Bool
    let amharicVoice: Bool
    let onImprove: (String) -> Void
    let onClose: () -> Void

    @State private var instruction = ""
    @FocusState private var typing: Bool

    private static let rewrites: [(title: String, instruction: String)] = [
        ("Shorter", "Make it shorter. Keep the main point."),
        ("Longer", "Make it longer with one more example."),
        ("More dramatic", "Make it more dramatic and gripping, with a stronger opening line."),
        ("Simpler", "Use simpler, everyday words and shorter sentences."),
        ("Stronger opening", "Rewrite only the first sentence as a hook that makes people keep watching."),
    ]

    private var language: Lang { Lang(rawValue: languageRaw) ?? Lang.matchingInterface }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(T("More options")).screenTitle(amharic: A("More options"))
                        .accessibilityIdentifier("moreHeading")

                    if hasScript {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(T("Improve the script")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                            ChipRow {
                                ForEach(MoreOptionsSheet.rewrites, id: \.title) { item in
                                    Chip(title: T(item.title)) { onImprove(item.instruction) }
                                }
                            }
                            HStack(spacing: 10) {
                                TextField(T("Tell Kinbir what to change"), text: $instruction)
                                    .field()
                                    .focused($typing)
                                    .accessibilityIdentifier("refineField")
                                Button(T("Apply")) { onImprove(instruction) }
                                    .buttonStyle(QuietButtonStyle())
                                    .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .accessibilityIdentifier("refineButton")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(T("Voiceover language")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                        Picker(T("Voiceover language"), selection: Binding(
                            get: { language.rawValue },
                            set: { languageRaw = $0 })
                        ) {
                            ForEach(Lang.allCases) { Text(T($0.title)).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("languagePicker")
                    }

                    if language == .en {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(T("Reading speed")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                            Picker(T("Reading speed"), selection: $voice.pace) {
                                ForEach(VoiceOptions.paces, id: \.self) { Text(T($0.capitalized)).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            if amharicVoice {
                                NoteText(text: T("This voice was cloned reading Amharic, so its English has an Amharic accent. Clone an English reading for a native sound."))
                            }
                        }
                        .accessibilityIdentifier("englishCard")
                    }

                    NavigationLink(value: Route.scriptRules) {
                        OptionRow(icon: "list.bullet.rectangle", title: T("Script rules"),
                                  detail: T("Standing instructions for every script Kinbir writes."))
                    }
                    .buttonStyle(.plain)
                }
                .page()
            }
            .background(Theme.white)
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(for: Route.self) { route in
                if case .scriptRules = route { ScriptRulesView() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Done")) { onClose() }.accessibilityIdentifier("moreDone")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(T("Done")) { typing = false }
                }
            }
        }
        .tint(Theme.black)
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
