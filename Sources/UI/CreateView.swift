import SwiftUI
import UIKit

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

    /// One quiet line under the script: what a rewrite cost, or that the voiceover
    /// language was changed. It belongs to the text it was said about, so the next edit
    /// clears it.
    @State private var note: String?
    @State private var noteText = ""
    /// What was typed in "Write it for me", kept while the app is open so closing the
    /// sheet or a failed write does not lose it.
    @State private var writerDraft = WriterDraft()
    /// Speaking stopped by itself at the longest length of one take.
    @State private var speechCapped = false

    private var language: Lang {
        Lang(rawValue: languageRaw) ?? Lang.matchingInterface
    }
    private var busy: Bool { work != .idle }
    private var script: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var needsVoice: Bool { state.me != nil && state.me?.hasVoice == false }
    private var seconds: Double { ScriptMath.seconds(script, language: language) }
    private var voiceCost: Double { ScriptMath.voiceCredits(seconds: seconds) }
    /// As on the website, the balance is the gate: nothing can be voiced at zero.
    private var outOfCredits: Bool { state.me != nil && !needsVoice && state.balance <= 0 }
    private var shownNote: String? { noteText == text ? note : nil }

    /// The website's sentence when a free-trial script is over the limit. Nil when it fits.
    private var trialLine: String? {
        guard !needsVoice, !outOfCredits,
              let line = TrialRule.problem(script, language: language,
                                           trialMaxChars: state.me?.trialMaxChars) else { return nil }
        return T(line) + " " + T(APIError.buyingNote)
    }

    /// The website's line by the button: what is left afterwards, and how long the audio is.
    private var leavesLine: String? {
        guard !needsVoice, !outOfCredits, !script.isEmpty, state.me != nil else { return nil }
        return Tf("Leaves you %@ of %@ credits · ≈ %@s of audio",
                  Fmt.credits(ScriptMath.balanceAfter(balance: state.balance, credits: voiceCost)),
                  Fmt.credits(state.balance), "\(max(1, Int(seconds.rounded())))")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                topCard

                Text(T("What will you say?")).screenTitle(amharic: A("What will you say?"))

                // The website's control row, above the box: type in Amharic, speak, the
                // letter pad, and Write it for me.
                ChipRow {
                    // Speech to text understands Amharic only, so it shows for Amharic.
                    if language == .am {
                        tool(icon: work == .listening ? "stop.fill" : "mic.fill",
                             title: work == .listening ? T("Stop") : T("Speak to type"),
                             active: work == .listening, id: "speakButton") {
                            Task { await toggleSpeech() }
                        }
                        .disabled(busy && work != .listening)
                    }
                    tool(icon: "sparkles", title: T("Write it for me"), active: false,
                         id: "writeForMeButton") {
                        editing = false
                        showWriter = true
                    }
                    .disabled(busy)
                    if language == .am {
                        tool(icon: "keyboard", title: "አማርኛ " + (ethOn ? "ON" : "OFF"), active: ethOn,
                             id: "ethToggle") {
                            ethOn.toggle()
                        }
                        tool(icon: nil, title: "ፊደል " + (fidelOpen ? "▴" : "▾"), active: fidelOpen,
                             id: "fidelTab") {
                            fidelOpen.toggle()
                        }
                    }
                }

                if ethOn && language == .am {
                    NoteText(text: "selam → ሰላም  ·  se → ሰ  ·  :: → ።")
                }

                editorCard

                if fidelOpen && language == .am {
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

                // Reading speed on the page itself, where a new user sees it (D-440).
                // Choosing it here is free; changing it after costs a new reading.
                VStack(alignment: .leading, spacing: 8) {
                    Text(T("Reading speed")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                    Picker(T("Reading speed"), selection: $voice.pace) {
                        Text(T("Slower")).tag("slow")
                        Text(T("Normal")).tag("normal")
                        Text(T("Faster")).tag("fast")
                    }
                    .pickerStyle(.segmented)
                    .disabled(busy)
                    .accessibilityIdentifier("speedPicker")
                }

                Button {
                    editing = false
                    showMore = true
                } label: {
                    OptionRow(icon: "slider.horizontal.3", title: T("More options"),
                              detail: language == .en ? T("Emphasis, change the script, script rules")
                                                      : T("Change the script, script rules"))
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
            BottomBar(problem: problem ?? trialLine) {
                mainButton
                if let line = leavesLine {
                    NoteText(text: line).accessibilityIdentifier("leavesLine")
                }
            }
        }
        .sheet(isPresented: $showWriter) {
            WriteSheet(language: language, draft: $writerDraft) { request in
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
                             script: script,
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
            // Only for an Amharic voiceover: an English one keeps its Latin letters.
            if ethOn, language == .am, work == .idle, new.count == old.count + 1, new.hasPrefix(old),
               let typed = new.last {
                let turned = Ethiopic.type(old, typed: typed)
                if turned != new {
                    text = turned
                    return
                }
            }
            // An Amharic script is read in Amharic, whatever was chosen for an earlier one.
            if language == .en, TextKind.detect(new) == .amharic,
               TextKind.ethiopicLetterCount(new) > 0 { useAmharic(about: new) }
            state.saveDraft(new)
            if new != draftText { draftId = nil }
            // A failed rewrite puts the old text back, and the reason it failed must stay
            // on screen.
            if keepProblem { keepProblem = false } else { problem = nil }
        }
        .onChange(of: languageRaw) { _, new in
            // English keeps its own letters: Amharic typing and the letter pad go away.
            if Lang(rawValue: new) == .en {
                ethOn = false
                fidelOpen = false
                note = nil
            }
        }
        .onChange(of: state.me) { _, me in seedVoice(from: me) }
        // A script is ready and a voice exists: wake the voice engine now, so the
        // voiceover does not start with its two minute warm-up.
        .task(id: script.isEmpty) {
            if !script.isEmpty, state.me?.hasVoice == true { await state.api.warmEngine() }
        }
        .task {
            // Amharic typing remembered from an Amharic script must not change English.
            if language == .en { ethOn = false }
            await state.refresh()
            recent = (try? await state.api.recentScripts()) ?? []
        }
    }

    // MARK: pieces

    private var header: some View {
        HStack {
            LogoMark(size: 36)
            Spacer()
            Button {
                showCredits = true
            } label: {
                Pill(text: Fmt.credits(state.balance) + " " + T("credits"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("creditsPill")
            // The script language, always in reach: only that language's tools show below.
            LanguageSwitch(selection: Binding(
                get: { language },
                set: { languageRaw = $0.rawValue }))
                .disabled(busy)
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

    @ViewBuilder private var topCard: some View {
        if needsVoice {
            voiceHero
        } else if outOfCredits {
            creditsCard
        }
    }

    /// The website's out-of-credits card, shown before a tap can be refused.
    private var creditsCard: some View {
        let paid = state.me?.hasPaid == true
        return VStack(alignment: .leading, spacing: 8) {
            Text(paid ? T("You've used all your credits") : T("You're out of credits"))
                .font(Theme.heading).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
            Text(paid ? T("Your scripts and voices are safe. Add credits to keep generating.")
                      : T("Pick a plan or grab a top-up to start generating with your voice."))
                .font(Theme.body).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
            NoteText(text: T(APIError.buyingNote))
        }
        .card(fill: Theme.grey)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("outOfCreditsCard")
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
                    KeyboardDoneButton { editing = false }
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

            if let line = shownNote {
                NoteText(text: line).accessibilityIdentifier("scriptNote")
            }
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
    /// When that changes the voiceover language, a line under the script says so.
    private func useAmharic(about current: String? = nil) {
        guard language != .am else { return }
        languageRaw = Lang.am.rawValue
        say(T("Voiceover language set to Amharic."), for: current ?? text)
    }

    /// Shows a line under the script until the script changes again.
    private func say(_ line: String, for current: String) {
        note = line
        noteText = current
    }

    /// The website's line after Kinbir wrote or changed a script.
    private func chargeLine(_ charged: Double, balance: Double) -> String {
        Tf(charged == 1 ? "Charged %@ credit, leaves you %@ credits"
                        : "Charged %@ credits, leaves you %@ credits",
           Fmt.credits(charged), Fmt.credits(balance))
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
            .disabled(busy || script.isEmpty || outOfCredits || trialLine != nil)
            .accessibilityIdentifier("voiceButton")
        }
    }

    private var mainTitle: String {
        if work == .starting { return T("Starting") }
        if script.isEmpty { return T("Make voiceover") }
        return T("Make voiceover") + " · ≈ " + Fmt.credits(voiceCost) + " " + T("credits")
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
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = item.body
                    } label: { Label(T("Copy script"), systemImage: "doc.on.doc") }
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
                // Text already in the output language is still rewritten. Without this
                // the server hands it back unchanged.
                options.force = ScriptOptions.sameLanguage(input, as: language)
            case .link:
                if let ready = request.fetchedText, !ready.isEmpty {
                    // The sheet already fetched the article, to show the price first.
                    input = ready
                } else {
                    work = .fetching
                    input = try await state.api.extract(url: input).text
                }
                options.force = ScriptOptions.sameLanguage(input, as: language)
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
            // What was typed in the sheet has done its job. After a failure it is kept.
            if request.kind != .refine { writerDraft = WriterDraft() }
            await state.refresh()
            if result.skipped == true {
                say(T("Nothing was changed."), for: final)
            } else if let charged = result.creditsCharged, charged > 0 {
                say(chargeLine(charged, balance: result.creditsBalance ?? state.balance), for: final)
            }
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
        // The free trial voices a limited script at a time. Said here, before the server refuses.
        if let line = trialLine {
            problem = line
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
                noteCap(showSpoken(final))
                return
            }
            // The live socket was not there (or gave nothing): send the whole take once.
            if final == nil, let file = dictation.takeFile() {
                do {
                    let heard = try await state.api.transcribe(audioURL: file)
                    if !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        noteCap(showSpoken(heard))
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
        speechCapped = false
        dictation.onPartial = { partial in
            guard work == .listening else { return }
            showSpoken(partial)
        }
        // The take reached 10 minutes, or the server stopped: finish it as if Stop was
        // tapped, so the screen does not stay on "Keep talking".
        dictation.onEnded = {
            guard work == .listening else { return }
            speechCapped = true
            Task { await toggleSpeech() }
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
    @discardableResult
    private func showSpoken(_ heard: String) -> String {
        let words = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        spokenLive = words
        let before = spokenBase
        let gap = before.isEmpty || before.last?.isWhitespace == true ? "" : " "
        let whole = before + gap + words
        text = whole
        return whole
    }

    /// Says why listening stopped by itself, under the words that were heard.
    private func noteCap(_ shown: String) {
        guard speechCapped else { return }
        speechCapped = false
        say(T("Stopped at 10 minutes, the longest one take can be."), for: shown)
    }
}

/// What "Write it for me" asks Kinbir to do.
struct WriteRequest {
    enum Kind { case idea, source, link, refine }
    var kind: Kind
    var input: String
    var targetSec: Int?
    var faithful = false
    /// The article behind a link, when the sheet already fetched it to show the price.
    var fetchedText: String?
}

/// What has been typed in "Write it for me". It lives on the Create screen, so closing the
/// sheet, going back, or a failed write does not lose it.
struct WriterDraft: Equatable {
    var kind: WriteRequest.Kind?
    var idea = ""
    var source = ""
    var link = ""
    var targetSec: Int? = 60
    var faithful = false
    var ownsLink = false
    /// The article behind `articleLink`, once it has been fetched.
    var article: String?
    var articleLink = ""
    var articleTitle: String?
}

/// Three ways to get a script without writing it: an idea, English text, or a link.
struct WriteSheet: View {
    @EnvironmentObject private var state: AppState
    let language: Lang
    @Binding var draft: WriterDraft
    let onWrite: (WriteRequest) -> Void

    @State private var estimate: Double?
    @State private var fetching = false
    @State private var problem: String?
    @FocusState private var typing: Bool

    private static let ideas: [(title: String, am: String, en: String)] = [
        ("News", "ስለ ዛሬው ዋና ዜና አጭር ማብራሪያ", "A short explainer about today's top news story"),
        ("History", "ስለ አድዋ ድል አጭር ታሪክ", "A short history of the Battle of Adwa"),
        ("Motivation", "ጠዋት ለመነሳት የሚያነሳሳ አጭር መልእክት", "A short motivational message for the morning"),
        ("Business", "ለአዲስ የቡና መሸጫ ማስታወቂያ", "An ad for a new coffee shop"),
        ("Tips", "ገንዘብ ለመቆጠብ ሦስት ቀላል መንገዶች", "Three easy ways to save money"),
    ]

    private var kind: WriteRequest.Kind? { draft.kind }

    private var input: String {
        switch draft.kind {
        case .idea: return draft.idea
        case .source: return draft.source
        case .link: return draft.link
        case .refine, .none: return ""
        }
    }

    private var clean: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The fetched article, for as long as the link is still the one it was fetched for.
    private var article: String? {
        guard draft.kind == .link, draft.articleLink == clean, let text = draft.article,
              !text.isEmpty else { return nil }
        return text
    }

    private var ready: Bool {
        switch draft.kind {
        case .idea: return clean.count >= 4
        case .source: return !clean.isEmpty
        case .link: return draft.ownsLink && TextKind.isLink(clean) && !fetching
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
                        // Going back keeps what was typed.
                        Button(T("Back")) {
                            typing = false
                            draft.kind = nil
                            estimate = nil
                            problem = nil
                        }
                        .accessibilityIdentifier("writerBack")
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
                    BottomBar(problem: problem) {
                        Button {
                            submit()
                        } label: {
                            BusyLabel(title: buttonTitle, busy: fetching)
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

    /// A link is fetched first, which is free, so the price can be shown before the
    /// script is written.
    private func submit() {
        guard let kind = draft.kind else { return }
        typing = false
        if kind == .link && article == nil {
            Task { await fetchArticle() }
            return
        }
        let faithful = kind == .source && draft.faithful
        onWrite(WriteRequest(kind: kind, input: clean, targetSec: faithful ? nil : draft.targetSec,
                             faithful: faithful, fetchedText: article))
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Write it for me")).screenTitle(amharic: A("Write it for me"))
                .accessibilityIdentifier("writerHeading")
            Text(T("Kinbir writes the script. You can change it afterwards."))
                .font(Theme.body).foregroundStyle(Theme.muted)
            choice(.idea, icon: "lightbulb", title: T("From an idea"),
                   detail: T("Say what the video is about in one line."))
            choice(.source, icon: "doc.text", title: T("From any text"),
                   detail: language == .en ? T("Paste text and get a video script.")
                                           : T("Paste text in any language and get a natural Amharic script."))
            choice(.link, icon: "link", title: T("From a link"),
                   detail: T("Paste a link to an article."))
        }
    }

    private func choice(_ value: WriteRequest.Kind, icon: String, title: String, detail: String) -> some View {
        Button {
            draft.kind = value
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
            TextField(T("For example: the history of Ethiopian coffee"), text: $draft.idea, axis: .vertical)
                .lineLimit(3...6)
                .padding(.vertical, 8)
                .field()
                .focused($typing)
                .accessibilityIdentifier("ideaField")
            ChipRow {
                ForEach(WriteSheet.ideas, id: \.title) { item in
                    Chip(title: T(item.title)) { draft.idea = language == .en ? item.en : item.am }
                }
            }
            lengthRow
        case .source:
            Text(T("Paste the text"))
                .screenTitle()
            TextEditor(text: $draft.source)
                .font(Theme.body)
                .foregroundStyle(Theme.black)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .focused($typing)
                .card(fill: Theme.grey, padding: 12)
                .accessibilityIdentifier("sourceEditor")
            Toggle(T("Keep it close to the original"), isOn: $draft.faithful)
                .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
            if !draft.faithful { lengthRow }
        case .link:
            Text(T("Paste the link")).screenTitle(amharic: A("Paste the link"))
            TextField("https://", text: $draft.link)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .field()
                .focused($typing)
                .accessibilityIdentifier("linkField")
            Toggle(T("This page is mine, or I have permission to use it"), isOn: $draft.ownsLink)
                .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
            lengthRow
            linkNote
        case .refine:
            EmptyView()
        }
    }

    /// Under the link: what happens next, and what it costs.
    @ViewBuilder private var linkNote: some View {
        if article != nil {
            NoteText(text: articleLine).accessibilityIdentifier("articleReady")
        } else {
            NoteText(text: T("Getting the article is free. You see the price before the script is written."))
        }
    }

    private var articleLine: String {
        let title = (draft.articleTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let price = estimate.map { " " + Tf("Writing the script costs about %@ credits.", Fmt.credits($0)) } ?? ""
        return (title.isEmpty ? T("The article is ready.") : Tf("The article is ready: %@.", title)) + price
    }

    private var lengthRow: some View {
        HStack {
            Text(T("Video length")).font(Theme.body).foregroundStyle(Theme.black)
            Spacer()
            Picker(T("Video length"), selection: $draft.targetSec) {
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
        if kind == .link && article == nil {
            return fetching ? T("Getting the article") : T("Get the article")
        }
        let price = estimate.map { " · ≈ " + Fmt.credits($0) + " " + T("credits") } ?? ""
        return T("Write the script") + price
    }

    /// What the price depends on. Empty while there is nothing to price yet.
    private var estimateKey: String {
        switch draft.kind {
        case .idea, .source:
            guard !clean.isEmpty else { return "" }
            return clean + "|\(draft.targetSec ?? 0)|\(draft.faithful)"
        case .link:
            guard article != nil else { return "" }
            return "link|" + clean + "|\(draft.targetSec ?? 0)"
        case .refine, .none:
            return ""
        }
    }

    private func loadEstimate() async {
        estimate = nil
        guard !estimateKey.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 800_000_000)
        if Task.isCancelled { return }
        let faithful = draft.kind == .source && draft.faithful
        estimate = try? await state.api.rewriteEstimate(
            text: article ?? clean,
            options: ScriptOptions(language: language, targetSec: faithful ? nil : draft.targetSec))
    }

    private func fetchArticle() async {
        guard !fetching else { return }
        let link = clean
        fetching = true
        problem = nil
        defer { fetching = false }
        do {
            let found = try await state.api.extract(url: link)
            draft.article = found.text
            draft.articleLink = link
            draft.articleTitle = found.title
        } catch {
            problem = state.report(error)
        }
    }
}

/// The things most people never need, kept off the main screen.
struct MoreOptionsSheet: View {
    @Binding var languageRaw: String
    @EnvironmentObject private var state: AppState
    @Binding var voice: VoiceOptions
    let hasScript: Bool
    /// The script a change would be applied to, for its price.
    let script: String
    let amharicVoice: Bool
    let onImprove: (String) -> Void
    let onClose: () -> Void

    @State private var instruction = ""
    @State private var estimate: Double?
    @FocusState private var typing: Bool

    private var language: Lang { Lang(rawValue: languageRaw) ?? Lang.matchingInterface }
    private var wanted: String { instruction.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var applyTitle: String {
        let price = estimate.map { " · ≈ " + Fmt.credits($0) + " " + T("credits") } ?? ""
        return T("Apply change") + price + " →"
    }

    /// The price of a change follows the script, and is asked for once something is typed.
    private var estimateKey: String {
        guard hasScript, !wanted.isEmpty else { return "" }
        return languageRaw + "|" + script
    }

    private func loadEstimate() async {
        guard !estimateKey.isEmpty else {
            estimate = nil
            return
        }
        estimate = try? await state.api.rewriteEstimate(
            text: script, options: ScriptOptions(language: language, refineInstruction: wanted))
    }

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

                    if language == .en {
                        VStack(alignment: .leading, spacing: 10) {
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
                            Button(applyTitle) { onImprove(instruction) }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(wanted.isEmpty)
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
        .task(id: estimateKey) { await loadEstimate() }
    }
}
