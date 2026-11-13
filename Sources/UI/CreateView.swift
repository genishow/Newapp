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
    @AppStorage("kinbir.recentShown") private var recentOpen = false
    @State private var keepProblem = false
    @AppStorage("kinbir.ethOn") private var ethOn = false
    @State private var fidelOpen = false
    @State private var dictation = LiveDictation()
    /// The script as it was before speaking began, and what has been heard since.
    @State private var spokenBase = ""
    @State private var spokenLive = ""
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

                // The website's control row, above the box: type in Amharic, speak, the
                // letter pad, and Write it for me.
                ChipRow {
                    tool(icon: work == .listening ? "stop.fill" : "mic.fill",
                         title: work == .listening ? T("Stop") : T("Speak to type"),
                         active: work == .listening, id: "speakButton") {
                        useAmharic()
                        Task { await toggleSpeech() }
                    }
                    .disabled(busy && work != .listening)
                    tool(icon: "sparkles", title: T("Write it for me"), active: false,
                         id: "writeForMeButton") {
                        editing = false
                        showWriter = true
                    }
                    .disabled(busy)
                    tool(icon: "keyboard", title: "አማርኛ " + (ethOn ? "ON" : "OFF"), active: ethOn,
                         id: "ethToggle") {
                        ethOn.toggle()
                        if ethOn { useAmharic() }
                    }
                    tool(icon: nil, title: "ፊደል " + (fidelOpen ? "▴" : "▾"), active: fidelOpen,
                         id: "fidelTab") {
                        fidelOpen.toggle()
                        if fidelOpen { useAmharic() }
                    }
                }

                if ethOn {
                    NoteText(text: "selam → ሰላም  ·  se → ሰ  ·  :: → ።")
                }

                editorCard

                if fidelOpen {
                    fidelPad
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
        // One point of padding keeps the scrolling page from sliding under the clock.
        .padding(.top, 1)
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
        .onChange(of: text) { old, new in
            // Type-to-Amharic: one Latin letter typed at the end becomes Ethiopic.
            if ethOn, work == .idle, new.count == old.count + 1, new.hasPrefix(old),
               let typed = new.last {
                let turned = Ethiopic.type(old, typed: typed)
                if turned != new {
                    text = turned
                    return
                }
            }
            // An Amharic script is read in Amharic, whatever was chosen for an earlier one.
            if language == .en, TextKind.detect(new) == .amharic { useAmharic() }
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
                    .autocorrectionDisabled(ethOn)
                    .textInputAutocapitalization(ethOn ? .never : .sentences)
                    .disabled(work == .writing || work == .transcribing || work == .fetching
                              || work == .listening)
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
                // The keyboard's own Done bar does not always show on this screen, so there is
                // a clear way to put the keyboard away right in the box.
                if editing {
                    Button {
                        editing = false
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
                    .accessibilityIdentifier("hideKeyboardButton")
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
        case .listening: return T("Keep talking, words appear as you go. Tap Stop when done.")
        case .transcribing: return T("Finishing…")
        case .writing: return T("Writing your script")
        case .fetching: return T("Getting the article")
        case .idle, .starting: return nil
        }
    }

    /// Speaking, Amharic typing and the letter pad all make an Amharic script.
    private func useAmharic() {
        if language != .am { languageRaw = Lang.am.rawValue }
    }

    /// A small control above the script box. It turns lime while it is on.
    private func tool(icon: String?, title: String, active: Bool, id: String,
                      action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .bold))
                }
                Text(title).font(Theme.smallMedium).lineLimit(1)
            }
            .foregroundStyle(Theme.black)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule().fill(active ? Theme.lime : Theme.white))
            .overlay(Capsule().strokeBorder(Theme.black, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// The website's letter pad: tap a letter to add it to the script.
    private var fidelPad: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(Ethiopic.padLetters.enumerated()), id: \.offset) { _, letter in
                    Button {
                        text += letter
                    } label: {
                        Text(letter).font(Theme.body).foregroundStyle(Theme.black)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.white))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .frame(height: 230)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.grey))
        .accessibilityIdentifier("fidelPad")
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
            Button {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.2)) { recentOpen.toggle() }
            } label: {
                HStack {
                    Text(T("Recent scripts")).font(Theme.heading).foregroundStyle(Theme.black)
                    Text("\(min(recent.count, 20))").font(Theme.smallMedium).foregroundStyle(Theme.muted)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.black)
                        .rotationEffect(.degrees(recentOpen ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recentToggle")
            if recentOpen {
            ForEach(recent.prefix(20)) { item in
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
        }
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

    /// Speak to type, the website's way: the words appear in the box while you talk.
    private func toggleSpeech() async {
        problem = nil
        if work == .listening {
            work = .transcribing
            defer { work = .idle }
            let final = await dictation.stop()
            if let final, !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showSpoken(final)
                return
            }
            // The live socket was not there (or gave nothing): send the whole take once.
            if final == nil, let file = dictation.takeFile() {
                do {
                    let heard = try await state.api.transcribe(audioURL: file)
                    if !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        showSpoken(heard)
                        return
                    }
                } catch {
                    problem = state.report(error)
                    return
                }
            }
            if spokenLive.isEmpty {
                problem = T("Could not hear any words. Try again closer to the mic.")
            }
            return
        }
        editing = false
        spokenBase = text
        spokenLive = ""
        dictation.onPartial = { partial in
            guard work == .listening else { return }
            showSpoken(partial)
        }
        let address = state.api.dictationAddress()
        Task { await state.api.warmDictation() }
        if await dictation.start(base: address?.base ?? RequestBuilder.defaultBase,
                                 accessCode: address?.accessCode ?? "") {
            work = .listening
        } else {
            problem = T("Kinbir needs the microphone to hear you. Allow it in Settings, then try again.")
        }
    }

    /// Puts what has been heard so far after the text that was there before speaking.
    /// Each update replaces the last one, so words can still be corrected as you go.
    private func showSpoken(_ heard: String) {
        let words = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        spokenLive = words
        let before = spokenBase
        let gap = before.isEmpty || before.last?.isWhitespace == true ? "" : " "
        text = before + gap + words
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

    private var language: Lang { Lang(rawValue: languageRaw) ?? Lang.matchingInterface }

    /// The website's small capital labels: LANGUAGE, SPEED, EMPHASIS.
    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(Theme.font(12, .bold, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
            .kerning(0.6)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(T("More options")).screenTitle(amharic: A("More options"))
                        .accessibilityIdentifier("moreHeading")

                    // The website's own sections, in its order and words.
                    VStack(alignment: .leading, spacing: 10) {
                        label(T("Language"))
                        Picker(T("Voiceover language"), selection: Binding(
                            get: { language.rawValue },
                            set: { languageRaw = $0 })
                        ) {
                            Text("አማርኛ").tag(Lang.am.rawValue)
                            Text("English").tag(Lang.en.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("languagePicker")
                    }

                    if language == .en {
                        VStack(alignment: .leading, spacing: 10) {
                            label(T("Speed"))
                            Picker(T("Speed"), selection: $voice.pace) {
                                Text(T("Slower")).tag("slow")
                                Text(T("Normal")).tag("normal")
                                Text(T("Faster")).tag("fast")
                            }
                            .pickerStyle(.segmented)
                            label(T("Emphasis"))
                            Picker(T("Emphasis"), selection: $voice.emphasis) {
                                Text(T("None")).tag("none")
                                Text(T("Punchy")).tag("punchy")
                                Text(T("Strong")).tag("strong")
                            }
                            .pickerStyle(.segmented)
                            if voice.emphasis != "none" {
                                NoteText(text: T("A beat lands where you wrote one: after a line ending in three dots, and between paragraphs."))
                            }
                            if amharicVoice {
                                NoteText(text: T("This voice was enrolled in Amharic, so its English carries an Amharic accent. Enroll an English reading for a native sound."))
                            }
                        }
                        .accessibilityIdentifier("englishCard")
                    }

                    if hasScript {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(T("Not quite right? Tell Kinbir what to change"))
                                .font(Theme.bodyMedium).foregroundStyle(Theme.black)
                                .fixedSize(horizontal: false, vertical: true)
                            TextField(T("e.g. remove the part about thieves · make the last line warmer"),
                                      text: $instruction, axis: .vertical)
                                .lineLimit(2...4)
                                .field()
                                .focused($typing)
                                .accessibilityIdentifier("refineField")
                            Button(T("Apply change") + " →") { onImprove(instruction) }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("refineButton")
                            NoteText(text: T("Everything you do not mention comes back exactly as it is."))
                        }
                    }

                    NavigationLink(value: Route.scriptRules) {
                        OptionRow(icon: "list.bullet.rectangle", title: T("Script Rules"),
                                  detail: T("Tailor it to your niche"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("scriptRulesRow")
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
