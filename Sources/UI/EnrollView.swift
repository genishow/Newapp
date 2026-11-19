import AVKit
import SwiftUI

/// Clone my voice: read a short script on camera, look at the take, then send it.
struct EnrollView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var script = ""
    @State private var scriptProblem: String?
    @State private var showRecorder = false
    @State private var uploading = false
    @State private var problem: String?
    @State private var result: EnrollResult?
    @State private var language: Lang = .am

    // The take being looked at before it is sent.
    @State private var take: URL?
    @State private var takePlayer: AVPlayer?
    @State private var checking = false
    @State private var check: EnrollCheck?

    // The two consent ticks. Both are needed before the take can be sent.
    @State private var agreedVoice = false
    @State private var agreedPolicy = false

    // Naming the new voice once it exists.
    @State private var voiceName = ""
    @State private var savedName: String?
    @State private var savingName = false
    // A second voice is added but not switched to, so the switch is offered here.
    @State private var activating = false
    @State private var madeActive = false
    @FocusState private var nameFocused: Bool

    static let policyURL = URL(string: "https://kinbir.com/voice-policy")!
    static let maxNameLength = 40

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                if let result {
                    done(result)
                } else if take != nil {
                    review
                } else {
                    if state.me?.cloneOpen == false { cloneClosed } else { form }
                }
            }
            .page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task(id: language) { await loadScript() }
        .onDisappear { takePlayer?.pause() }
        .fullScreenCover(isPresented: $showRecorder) {
            VideoRecorder(script: script) { url in
                showRecorder = false
                if let url { Task { await picked(url) } }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: before recording

    /// Voice cloning is closed for this account (the server decides).
    private var cloneClosed: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("Clone your voice")).screenTitle(amharic: A("Clone your voice"))
                .accessibilityIdentifier("enrollClosedHeading")
            Text(T("Voice cloning is not available in your country yet. You can still make voiceovers in the Kinbir voice."))
                .font(Theme.body).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
                .card(fill: Theme.grey)
            Button(T("Continue")) { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("Clone your voice")).screenTitle(amharic: A("Clone your voice"))
                .accessibilityIdentifier("enrollHeading")

            // Two big choices, each in its own language, so nobody reads the wrong
            // statement by leaving a small switch where it was (Geni, 2026-11-19).
            Text(T("Which language will you read in?"))
                .font(Theme.bodyMedium).foregroundStyle(Theme.black)
            HStack(spacing: 12) {
                languageTile(.am, title: "አማርኛ", detail: "Amharic")
                languageTile(.en, title: "English", detail: "እንግሊዝኛ")
            }
            .accessibilityIdentifier("enrollLanguagePicker")
            if language == .en {
                NoteText(text: T("Read in English to get a voice with a native English sound."))
            }

            mustRead
            scriptCard
            tips

            if let problem {
                ProblemCard(message: problem)
            }
            recordButtons
        }
    }

    private func languageTile(_ value: Lang, title: String, detail: String) -> some View {
        let selected = language == value
        return Button {
            Haptics.tap()
            language = value
        } label: {
            VStack(spacing: 4) {
                Text(title).font(Theme.heading).foregroundStyle(Theme.black)
                Text(detail).font(Theme.small).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 14).fill(selected ? Theme.lime : Theme.grey))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.black, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("enrollLanguage-" + value.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The one rule, said before anything else, in the language being read. People
    /// were talking about other things, or singing, and no voice could be made.
    private var mustRead: some View {
        let am = language == .am
        return VStack(alignment: .leading, spacing: 6) {
            Text(am ? "እነዚህን ቃላት በትክክል ማንበብ አለብዎት" : "You must read these exact words")
                .font(Theme.heading).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
            Text(am ? "ሌላ ምንም አይናገሩ። ሌላ ንግግር ወይም ዘፈን ተቀባይነት የለውም፤ ድምፅም አይሰራም።"
                    : "Do not say anything else. Other talking or singing is refused, and no voice is made.")
                .font(Theme.body).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("enrollMustRead")
    }

    private var scriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Read this aloud, word for word")).font(Theme.smallMedium).foregroundStyle(Theme.black)
            if script.isEmpty && scriptProblem == nil {
                ProgressView().tint(Theme.black)
            } else if let scriptProblem {
                NoteText(text: scriptProblem)
                Button(T("Try again")) { Task { await loadScript() } }
                    .buttonStyle(QuietButtonStyle())
            } else {
                AmharicText(text: script, font: .system(size: 19))
                    .accessibilityIdentifier("enrollScript")
            }
        }
        .card(fill: Theme.lime)
    }

    /// One line that matters, why a video, the rest folded away. In the language being
    /// read, so an Amharic reader gets Amharic tips (Geni).
    private var tips: some View {
        let am = language == .am
        func L(_ en: String, _ amh: String) -> String { am ? amh : en }
        return VStack(alignment: .leading, spacing: 10) {
            Text(L("Read every word, 10 to 40 seconds. The words stay on screen while you record.",
                   "እያንዳንዱን ቃል ያንብቡ፤ ከ10 እስከ 40 ሰከንድ። በሚቀረፁበት ጊዜ ቃላቱ በስክሪኑ ላይ ይቆያሉ።"))
                .font(Theme.small).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.black)
                Text(L("Why a video? It shows the voice is really yours, so nobody can clone someone else's voice. It stays private to your account.",
                       "ለምን ቪዲዮ? ድምፁ በእርግጥ የእርስዎ መሆኑን ያሳያል፤ ስለዚህ ማንም የሌላ ሰውን ድምፅ መቅዳት አይችልም። ቪዲዮው ለእርስዎ መለያ ብቻ ግላዊ ሆኖ ይቀመጣል።"))
                    .font(Theme.small).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("enrollWhyVideo")
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    tip(L("A quiet room, no music or TV.", "ፀጥ ያለ ክፍል፤ ሙዚቃ ወይም ቴሌቪዥን የሌለበት።"))
                    tip(L("Hold the phone close to your mouth, with your face still showing in the video.", "ስልኩን ወደ አፍዎ አቅርበው ይያዙ፤ ፊትዎ ግን በቪዲዮው ላይ ይታይ።"))
                    tip(L("Read the way you want every voiceover to sound.",
                          "እያንዳንዱ የድምፅ ቅጂዎ እንዲሰማ በሚፈልጉት መንገድ ያንብቡ።"))
                    tip(L("We check the statement was said before the voice is made.",
                          "ድምፁ ከመሰራቱ በፊት መግለጫው መነበቡን እናረጋግጣለን።"))
                }
                .padding(.top, 6)
            } label: {
                Text(L("Tips for a great voice", "ለጥሩ ድምፅ ምክሮች"))
                    .font(Theme.smallMedium).foregroundStyle(Theme.black)
            }
            .tint(Theme.black)
            .accessibilityIdentifier("enrollTips")
        }
    }

    @ViewBuilder private var recordButtons: some View {
        if Launch.isMock {
            // The simulator has no camera, so the UI tests take this path.
            Button(T("Use sample video")) { useSample() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("sampleVideoButton")
        } else if VideoRecorder.isAvailable {
            Button(T("Record now")) { showRecorder = true }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(script.isEmpty)
                .accessibilityIdentifier("recordButton")
        }
        else {
            // No old video can be chosen any more (Geni, 2026-11-19): people sent
            // songs and random clips. The reading is recorded here, with the words
            // on the screen.
            NoteText(text: T("This device has no camera to record with. Open Kinbir on your phone to clone your voice."))
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.black).frame(width: 6, height: 6).padding(.top, 7)
            Text(text).font(Theme.small).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: the take, before it is sent

    private var canSend: Bool { agreedVoice && agreedPolicy && !uploading && !notHeard }
    /// The check listened to this take and did not hear the statement.
    private var notHeard: Bool { check?.consent?.verdict == "fail" }

    private var review: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("Check your recording")).screenTitle()
                .accessibilityIdentifier("enrollReviewHeading")

            takeCard
            qualityPart
            consent

            if let problem {
                ProblemCard(message: problem)
            }
            if uploading {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.black)
                    Text(T("Cloning your voice from the recording. This takes about a minute. You can leave the app: it goes on, and Kinbir tells you when your voice is ready."))
                        .font(Theme.small).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card(fill: Theme.grey, padding: 14)
            }
            sendPart
        }
    }

    private var takeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let takePlayer {
                VideoPlayer(player: takePlayer)
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.black, lineWidth: 1))
                    .accessibilityIdentifier("takePlayer")
            }
            HStack {
                NoteText(text: T("Play it back. If it sounds clear, send it."))
                Spacer()
                Button("↺ " + T("Redo")) { redo() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(uploading || checking)
                    .accessibilityIdentifier("redoButton")
            }
        }
    }

    /// The optional, free check: a badge and what to fix, in the server's own words.
    @ViewBuilder private var heardPart: some View {
        if let consent = check?.consent, !checking {
            if consent.verdict == "pass" {
                Label(T("We heard you read the statement. You can send it."), systemImage: "checkmark.circle.fill")
                    .font(Theme.bodyMedium).foregroundStyle(Theme.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(fill: Theme.lime, padding: 14)
                    .accessibilityIdentifier("consentHeard")
            } else if consent.verdict == "fail" {
                VStack(alignment: .leading, spacing: 8) {
                    Text(T("We did not hear the statement"))
                        .font(Theme.heading).foregroundStyle(Theme.black)
                    Text(T("Record again and read the words on the screen, word for word. Do not say anything else."))
                        .font(Theme.body).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                    if let heard = consent.heard, !heard.isEmpty {
                        Text(T("What we heard:")).font(Theme.smallMedium).foregroundStyle(Theme.muted)
                        AmharicText(text: heard, font: .system(size: 15))
                    }
                    Button("↺ " + T("Record again")) { redo() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("recordAgainButton")
                }
                .card(fill: Theme.grey, padding: 14)
                .accessibilityIdentifier("consentNotHeard")
            }
        }
    }

    @ViewBuilder private var qualityPart: some View {
        heardPart
        if checking {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.black)
                Text(T("Listening to your recording")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
            }
            .card(fill: Theme.grey, padding: 14)
        } else if let check {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Pill(text: T(check.title).uppercased(), fill: badgeFill(check.badge))
                        .accessibilityIdentifier("qualityBadge")
                    Text(check.lengthLine).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                }
                ForEach(check.advice ?? [], id: \.self) { line in
                    tip(APIError.sentenceCase(line))
                }
            }
            .card(fill: Theme.white, padding: 14)
        }
    }

    private func badgeFill(_ badge: String?) -> Color {
        switch badge {
        case "green": return Theme.lime
        case "yellow": return Theme.white
        default: return Theme.grey
        }
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: 12) {
            tick(isOn: $agreedVoice,
                 title: T("I agree: this is my voice"),
                 detail: T("Kinbir may create a synthetic copy of my voice, from this recording, to read my scripts for my account only. It stays private to me. Kinbir keeps it until I delete it, which I can do at any time, and destroys it three years after I last use Kinbir."))
                .accessibilityIdentifier("consentVoiceTick")
            tick(isOn: $agreedPolicy,
                 title: T("I have read and agree to the Voice Policy"),
                 detail: T("My own voice only, no impersonation. Kinbir checks recordings and removes any voice that is not the person's own, at any time."))
                .accessibilityIdentifier("consentPolicyTick")
            Link(T("Read the Voice Policy"), destination: EnrollView.policyURL)
                .font(Theme.smallMedium)
                .foregroundStyle(Theme.black)
                .accessibilityIdentifier("voicePolicyLink")
        }
        .card(fill: Theme.grey, padding: 14)
    }

    private func tick(isOn: Binding<Bool>, title: String, detail: String) -> some View {
        Button {
            Haptics.tap()
            isOn.wrappedValue.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.black)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.smallMedium).foregroundStyle(Theme.black)
                        .multilineTextAlignment(.leading)
                    Text(detail).font(Theme.small).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(uploading)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    @ViewBuilder private var sendPart: some View {
        Button {
            Task { await send() }
        } label: {
            BusyLabel(title: uploading ? T("Cloning your voice") : T("Send my voice"), busy: uploading)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canSend)
        .accessibilityIdentifier("sendVoiceButton")

        if !agreedVoice {
            NoteText(text: T("Tick the consent statement above first."))
        } else if !agreedPolicy {
            NoteText(text: T("Agree to the Voice Policy above first."))
        }

        if check == nil && !checking {
            Button(T("Check my recording")) { Task { await runCheck() } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(uploading)
                .accessibilityIdentifier("checkQualityButton")
        }
    }

    // MARK: ready

    private func done(_ result: EnrollResult) -> some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            if result.isApproved {
                Text(T("Your voice is ready")).screenTitle(amharic: A("Your voice is ready"))
                    .accessibilityIdentifier("enrollDoneHeading")
                if let granted = result.creditsGranted, granted > 0 {
                    Text(Tf("%@ free credits are on your account.", Fmt.credits(granted)))
                        .font(Theme.body).foregroundStyle(Theme.black)
                        .card(fill: Theme.lime, padding: 14)
                }
                if let voiceId = result.voiceId, !voiceId.isEmpty {
                    namePart(voiceId: voiceId)
                    activePart(result, voiceId: voiceId)
                }
            } else {
                Text(T("Submitted, pending review")).screenTitle()
                Text(result.message.map(APIError.sentenceCase)
                     ?? T("You will get an email when it is approved."))
                    .font(Theme.body).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            adviceNotes(result)
            if let problem {
                ProblemCard(message: problem)
            }
            Button(T("Continue")) { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("enrollContinueButton")
        }
    }

    /// A weak recording is still approved, so this is the moment to say so plainly.
    @ViewBuilder private func adviceNotes(_ result: EnrollResult) -> some View {
        if result.isApproved, result.needsReview == true {
            VStack(alignment: .leading, spacing: 6) {
                Text(T("Your voice works, but this recording is weak."))
                    .font(Theme.bodyMedium).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                Text(T("Every video you make will carry it. Worth one more take:"))
                    .font(Theme.small).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(result.advice ?? [], id: \.self) { line in
                    tip(APIError.sentenceCase(line))
                }
            }
            .card(fill: Theme.grey, padding: 14)
            .accessibilityIdentifier("weakRecordingCard")
        } else {
            ForEach(result.advice ?? [], id: \.self) { line in
                NoteText(text: T("Tip: ") + APIError.sentenceCase(line))
            }
        }
    }

    /// Says which voice the next voiceover will use. A first voice is in use at once; a
    /// second one waits until the user switches to it.
    @ViewBuilder private func activePart(_ result: EnrollResult, voiceId: String) -> some View {
        if madeActive {
            Text(T("This voice is now in use."))
                .font(Theme.smallMedium).foregroundStyle(Theme.black)
                .accessibilityIdentifier("voiceNowActive")
        } else if result.active == false {
            VStack(alignment: .leading, spacing: 10) {
                Text(Tf("Your voiceovers still use \"%@\". The new voice is saved, and you can switch to it now or later in My voices.", currentVoiceName))
                    .font(Theme.body).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voiceInUseNote")
                Button {
                    Task { await useNow(voiceId: voiceId) }
                } label: {
                    BusyLabel(title: T("Use this voice now"), busy: activating)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(activating)
                .accessibilityIdentifier("useVoiceNowButton")
            }
            .card(fill: Theme.grey, padding: 14)
        }
    }

    private var currentVoiceName: String {
        let name = (state.activeVoice?.name ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? T("My voice") : name
    }

    private func useNow(voiceId: String) async {
        guard !activating else { return }
        activating = true
        problem = nil
        defer { activating = false }
        do {
            try await state.api.activateVoice(id: voiceId)
            await state.refresh()
            madeActive = true
        } catch {
            problem = state.report(error)
        }
    }

    private func namePart(voiceId: String) -> some View {
        let trimmed = voiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            Text(T("Give it a name")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
            NoteText(text: T("So you can tell it apart later. Something like \"My voice\" or \"Narration\". You can change it any time."))
            if let savedName {
                Text(Tf("Saved as \"%@\"", savedName))
                    .font(Theme.smallMedium).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("voiceNameSaved")
            } else {
                // Side by side, so the button stays above the keyboard.
                HStack(spacing: 10) {
                    TextField(T("My voice"), text: $voiceName)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .field()
                        .accessibilityIdentifier("voiceNameField")
                        .onChange(of: voiceName) { _, new in
                            if new.count > EnrollView.maxNameLength {
                                voiceName = String(new.prefix(EnrollView.maxNameLength))
                            }
                        }
                        .onSubmit { Task { await saveName(voiceId: voiceId, name: trimmed) } }
                    Button {
                        Task { await saveName(voiceId: voiceId, name: trimmed) }
                    } label: {
                        BusyLabel(title: T("Save name"), busy: savingName)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(trimmed.isEmpty || savingName)
                    .accessibilityIdentifier("saveVoiceNameButton")
                }
            }
        }
        .card(fill: Theme.white, padding: 14)
    }

    // MARK: work

    private func loadScript() async {
        scriptProblem = nil
        do {
            script = ""
            script = try await state.api.enrollScript(language: language)
            if script.isEmpty { scriptProblem = T("The script could not be loaded.") }
        } catch {
            scriptProblem = APIError.wrap(error).message
        }
    }

    /// A fresh recording or a chosen video. It is only kept when it can be sent at all.
    private func picked(_ url: URL) async {
        problem = nil
        let seconds = await VideoFiles.seconds(of: url)
        if let issue = EnrollRules.problem(seconds: seconds, bytes: VideoFiles.bytes(of: url)) {
            problem = issue
            return
        }
        keep(url)
    }

    private func useSample() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sample.mov")
        try? Data("sample".utf8).write(to: url)
        keep(url)
    }

    private func keep(_ url: URL) {
        problem = nil
        check = nil
        take = url
        takePlayer = AVPlayer(url: url)
        // Every take is listened to at once, so the person knows before sending
        // whether the statement was heard (Geni, 2026-11-19).
        Task { await runCheck() }
    }

    private func redo() {
        takePlayer?.pause()
        takePlayer = nil
        take = nil
        check = nil
        problem = nil
    }

    private func runCheck() async {
        guard let take, !checking else { return }
        checking = true
        problem = nil
        defer { checking = false }
        do {
            check = try await state.api.enrollCheck(videoURL: take, language: language)
        } catch {
            problem = state.report(error)
        }
    }

    private func send() async {
        guard let take, canSend else { return }
        takePlayer?.pause()
        uploading = true
        problem = nil
        defer { uploading = false }
        // So "tell you when it is ready" can be kept: asked once, at this moment.
        Task { if await Notifications.canAsk() { await Notifications.askNow() } }
        do {
            let answer = try await state.api.enroll(videoURL: take, language: language)
            await state.refresh()
            result = answer
            if UIApplication.shared.applicationState != .active {
                await Notifications.tellNow(title: T("Your voice is ready"),
                                            body: T("Open Kinbir to use it."), id: "kinbir.voice")
            }
        } catch {
            problem = state.report(error)
            if UIApplication.shared.applicationState != .active {
                await Notifications.tellNow(title: T("Your voice could not be made"),
                                            body: T("Open Kinbir and send the recording again."),
                                            id: "kinbir.voice")
            }
        }
    }

    private func saveName(voiceId: String, name: String) async {
        guard !name.isEmpty else { return }
        savingName = true
        problem = nil
        defer { savingName = false }
        do {
            try await state.api.renameVoice(id: voiceId, name: name)
            nameFocused = false
            savedName = name
            await state.refresh()
        } catch {
            problem = state.report(error)
        }
    }
}
