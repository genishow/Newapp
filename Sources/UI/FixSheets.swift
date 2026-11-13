import SwiftUI

/// "How should this word sound?" Works the way the website does: the first reading plays
/// by itself, the others are prepared in the background, and choosing one only adds it to
/// the list of changes. Nothing is charged until the changes are generated together.
struct WordFixSheet: View {
    @EnvironmentObject private var state: AppState
    let target: FixTarget
    let jobId: String
    /// How many times this word appears, so the user knows one fix changes them all.
    let occurrences: Int
    /// True when this word already has a change waiting, so it can be unmarked.
    let marked: Bool
    let onUnmark: () -> Void
    /// The fix, and the short label shown for it in the list of changes.
    let onUse: (FixEdit, String) -> Void
    let onClose: () -> Void

    @StateObject private var player = AudioPlayer()
    @StateObject private var recorder = SpeechRecorder()
    /// Goes up with every Listen tap, so a newer tap takes over from one still preparing.
    @State private var turn = 0
    @State private var options: [FixOption] = []
    @State private var loaded = false
    @State private var optionsFailed: String?
    @State private var custom = ""
    @State private var problem: String?
    /// Which reading is being prepared right now, for the spinner on its row.
    @State private var preparing: String?
    @State private var waited = 0
    @State private var firstEver = false
    /// Readings already downloaded. A second tap plays at once.
    @State private var clips: [String: URL] = [:]
    @State private var playingKey: String?

    private enum Way { case none, type, say }
    @State private var way: Way = .none

    private func otherWay(_ value: Way, icon: String, title: String) -> some View {
        Button {
            Haptics.tap()
            way = (way == value) ? .none : value
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(title).font(Theme.smallMedium).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.black)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(way == value ? Theme.lime : Theme.white))
            .overlay(Capsule().strokeBorder(Theme.black, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(value == .type ? "fixWayType" : "fixWaySay")
    }

    private enum Ear { case idle, recording, matching }
    @State private var ear: Ear = .idle
    /// Readings shown, best first. They add up across takes, as on the website: a new
    /// take re-scores what is showing and adds up to three fresh ones.
    @State private var earMatches: [ByEarMatch] = []
    /// The latest full ranking, so "Hear more readings" can add the rest.
    @State private var earPool: [ByEarMatch] = []
    @State private var earMatchId: String?
    @State private var earProblem: String?
    /// Spellings already tried for this word, newest first, kept on the phone so they can
    /// be heard and used again later, even after the voiceover was regenerated.
    @State private var tries: [String] = []

    private var triesKey: String { "kinbir.tries." + target.word }
    private var earKey: String { "kinbir.ear." + target.word }

    private struct SavedEar: Codable {
        var matchId: String
        var shown: [ByEarMatch]
        var pool: [ByEarMatch]
    }

    private func remember(_ spelling: String) {
        let s = spelling.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        tries.removeAll { $0 == s }
        tries.insert(s, at: 0)
        if tries.count > 10 { tries = Array(tries.prefix(10)) }
        UserDefaults.standard.set(tries, forKey: triesKey)
    }

    private func forget(_ spelling: String) {
        tries.removeAll { $0 == spelling }
        UserDefaults.standard.set(tries, forKey: triesKey)
    }

    private func saveEar() {
        guard let id = earMatchId,
              let data = try? JSONEncoder().encode(SavedEar(matchId: id, shown: earMatches, pool: earPool))
        else { return }
        UserDefaults.standard.set(data, forKey: earKey)
    }

    private func restoreSaved() {
        tries = UserDefaults.standard.stringArray(forKey: triesKey) ?? []
        if let data = UserDefaults.standard.data(forKey: earKey),
           let saved = try? JSONDecoder().decode(SavedEar.self, from: data) {
            earMatchId = saved.matchId
            earMatches = saved.shown
            earPool = saved.pool
        }
    }

    /// The website's merge: re-score what is showing, add up to three new ones, best first.
    private func mergeTake(_ ranked: [ByEarMatch]) {
        earPool = ranked
        let shown = Set(earMatches.map(\.optionId))
        let updated = earMatches.map { m in ranked.first { $0.optionId == m.optionId } ?? m }
        let fresh = ranked.filter { !shown.contains($0.optionId) }.prefix(3)
        earMatches = (updated + fresh).sorted { ($0.match ?? 0) > ($1.match ?? 0) }
        saveEar()
    }

    private var earMore: Int {
        let shown = Set(earMatches.map(\.optionId))
        return earPool.filter { !shown.contains($0.optionId) }.count
    }

    private var typed: String { custom.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        (Text(T("How should") + " ").font(Theme.heading)
                         + Text(target.word).font(.system(size: 24, weight: .bold))
                         + Text(" " + T("sound?")).font(Theme.heading))
                            .foregroundStyle(Theme.black)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("fixHeading")
                        if occurrences > 1 {
                            NoteText(text: Tf("Appears %@ times, fixing it here changes all of them.", "\(occurrences)"))
                        }
                    }

                    suggestions

                    // One thing at a time: the suggestions first, and the two other ways
                    // open only when asked for.
                    if loaded {
                        HStack(spacing: 10) {
                            otherWay(.type, icon: "keyboard", title: T("Type it my way"))
                            otherWay(.say, icon: "mic.fill", title: T("Say it myself"))
                        }
                    }
                    if way == .type || (loaded && options.isEmpty && way == .none) {
                        typeIt
                    }
                    if way == .say {
                        sayIt
                    }
                    if !tries.isEmpty {
                        triedList
                    }

                    // The website's price line, before anything is spent.
                    NoteText(text: T("Hearing a reading is free once anyone has heard that spelling. A brand-new spelling costs up to 1 credit. Applying your changes costs 1.5 credits, however many."))
                        .accessibilityIdentifier("fixPriceNote")

                    if marked {
                        Button(T("Unmark")) { onUnmark() }
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityIdentifier("fixUnmark")
                    }
                }
                .page()
            }
            .background(Theme.white)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    }
                    .accessibilityLabel(T("Close"))
                    .accessibilityIdentifier("fixClose")
                }
            }
        }
        .tint(Theme.black)
        .task {
            restoreSaved()
            // Readings found earlier by saying the word show straight away.
            if !earMatches.isEmpty && way == .none { way = .say }
            await open()
        }
        // As on the website: what was typed starts being made 1.5 seconds after typing
        // stops (3 letters or more), so play is quick. Half-typed words are not sent.
        .task(id: typed) {
            guard typed.count >= 3 else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            _ = try? await state.api.fixPreview(word: target.word, optionId: nil, custom: typed)
        }
        .onDisappear {
            player.stop()
            _ = recorder.stop()
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased()).font(Theme.font(12, .bold, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
            .kerning(0.6)
    }

    /// The website's first block: the suggested readings, each with play and Use.
    @ViewBuilder private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !loaded {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.black)
                    Text(T("Preparing options…")).font(Theme.body).foregroundStyle(Theme.black)
                }
            } else if let optionsFailed {
                Text(optionsFailed).font(Theme.small).foregroundStyle(Theme.black)
                Button(T("Try again")) {
                    loaded = false
                    Task { await open() }
                }
                .buttonStyle(QuietButtonStyle())
            } else if options.isEmpty {
                NoteText(text: T("No suggestion yet, type how it should sound."))
            } else {
                eyebrow(T("Playing the suggestion, sound right?"))
                if preparing != nil && (firstEver || waited > 3) {
                    NoteText(text: (firstEver
                                    ? T("This word is being voiced for the very first time, so it can take up to a minute or two. Everyone after you gets it instantly.")
                                    : T("Preparing the audio…"))
                             + (waited > 3 ? " (\(waited)s)" : ""))
                }
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    row(key: "o:\(option.optionId)",
                        title: option.label ?? Tf("Option %@", optionLetter(index)),
                        index: index,
                        listen: { await hear(key: "o:\(option.optionId)", optionId: option.optionId, custom: nil) },
                        use: {
                            onUse(.option(word: target.word, optionId: option.optionId),
                                  target.word + " · " + (option.label ?? optionLetter(index)))
                        })
                }
            }
            if let problem {
                Text(problem).font(Theme.small).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("fixProblem")
            }
        }
    }

    /// "Or say it yourself": say the word, and the closest readings are listed best first.
    @ViewBuilder private var sayIt: some View {
        VStack(alignment: .leading, spacing: 8) {
            NoteText(text: T("Say the word once, naturally. The video keeps the cloned voice, never your recording."))
            Button {
                Task { await toggleEar() }
            } label: {
                HStack(spacing: 8) {
                    if ear == .matching {
                        ProgressView().tint(Theme.black)
                    } else {
                        Image(systemName: ear == .recording ? "stop.fill" : "mic.fill")
                    }
                    Text(ear == .recording ? T("Stop. I said it")
                         : ear == .matching ? T("Listening…")
                         : T("Record the word · up to 1 credit"))
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(ear == .matching)
            .accessibilityIdentifier("fixRecordWord")

            if ear == .matching {
                NoteText(text: T("Comparing with the voice's own readings. The first time for a word can take a couple of minutes, stay here."))
            }
            if !earMatches.isEmpty {
                NoteText(text: T("Closest to your reading. Listen from 1 down and keep the right one. Say it again as many times as you like: each take re-orders this list and adds new readings."))
                ForEach(Array(earMatches.enumerated()), id: \.element.id) { index, match in
                    row(key: "o:\(match.optionId)",
                        title: "\(index + 1) · " + Tf("%@% match", "\(Int((match.match ?? 0).rounded()))"),
                        index: 100 + index,
                        useTitle: T("Use this"),
                        listen: { await hear(key: "o:\(match.optionId)", optionId: match.optionId, custom: nil) },
                        use: {
                            onUse(.heard(word: target.word, optionId: match.optionId, matchId: earMatchId ?? ""),
                                  target.word + " · " + T("my reading"))
                        })
                }
                if earMore > 0 {
                    Button(Tf("None of these? Hear %@ more readings", "\(earMore)")) {
                        let shown = Set(earMatches.map(\.optionId))
                        earMatches += earPool.filter { !shown.contains($0.optionId) }
                        saveEar()
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("fixEarMore")
                }
            }
            if let earProblem {
                Text(earProblem).font(Theme.small).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Not right? Type it your way": a field with its own play button, then Use.
    @ViewBuilder private var typeIt: some View {
        VStack(alignment: .leading, spacing: 8) {
            NoteText(text: T("Spell it how it sounds. Double a letter to hold it longer."))
            HStack(spacing: 10) {
                TextField(T("e.g. gebboch"), text: $custom)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .field()
                    .accessibilityIdentifier("fixCustomField")
                playButton(key: "c:" + typed, id: "fixListenTyped") {
                    let spelling = typed
                    remember(spelling)
                    await hear(key: "c:" + spelling, optionId: nil, custom: spelling)
                }
                .disabled(typed.isEmpty)
                .opacity(typed.isEmpty ? 0.4 : 1)
            }
            Button(T("Use what I typed")) {
                remember(typed)
                onUse(.custom(word: target.word, spelling: typed), target.word + " · " + typed)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(typed.isEmpty)
            .accessibilityIdentifier("fixUseTyped")
        }
    }

    /// Every spelling tried for this word, so an earlier one can be heard and used again.
    @ViewBuilder private var triedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow(T("Your spellings"))
            NoteText(text: T("Every spelling you tried for this word. Tap play to hear one again."))
            ForEach(Array(tries.enumerated()), id: \.element) { index, spelling in
                HStack(spacing: 12) {
                    playButton(key: "c:" + spelling, id: "fixTry-\(index)") {
                        await hear(key: "c:" + spelling, optionId: nil, custom: spelling)
                    }
                    Text(spelling).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    Button(T("Use")) {
                        remember(spelling)
                        onUse(.custom(word: target.word, spelling: spelling), target.word + " · " + spelling)
                    }
                    .font(Theme.smallMedium)
                    .foregroundStyle(Theme.black)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(Capsule().fill(Theme.lime))
                    .overlay(Capsule().strokeBorder(Theme.black, lineWidth: 1))
                    .accessibilityIdentifier("fixTryUse-\(index)")
                    Button {
                        forget(spelling)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 32, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(T("Remove"))
                }
                .card(fill: Theme.grey, padding: 10)
            }
        }
        .accessibilityIdentifier("fixTriedList")
    }

    private func optionLetter(_ index: Int) -> String {
        String(UnicodeScalar(UInt8(65 + min(index, 25))))
    }

    private func playButton(key: String, id: String, listen: @escaping () async -> Void) -> some View {
        Button {
            Task { await listen() }
        } label: {
            ZStack {
                Circle().fill(playingKey == key ? Theme.lime : Theme.black)
                if preparing == key {
                    ProgressView().tint(Theme.white)
                } else {
                    Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(playingKey == key ? Theme.black : Theme.white)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("Listen"))
        .accessibilityIdentifier(id)
    }

    private func row(key: String, title: String, index: Int, useTitle: String = T("Use"),
                     listen: @escaping () async -> Void, use: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            playButton(key: key, id: "fixListen-\(index)", listen: listen)
            Text(title).font(Theme.bodyMedium).foregroundStyle(Theme.black)
            Spacer()
            Button(useTitle) { use() }
                .font(Theme.smallMedium)
                .foregroundStyle(Theme.black)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(Capsule().fill(Theme.lime))
                .overlay(Capsule().strokeBorder(Theme.black, lineWidth: 1))
                .accessibilityIdentifier("fixUse-\(index)")
        }
        .card(fill: Theme.grey, padding: 10)
    }

    /// Records the word, sends it, and lists the closest readings.
    private func toggleEar() async {
        earProblem = nil
        if ear == .recording {
            guard let file = recorder.stop() else {
                ear = .idle
                return
            }
            ear = .matching
            do {
                let id = try await state.api.fixByEar(jobId: jobId, word: target.word, audioURL: file)
                earMatchId = id
                var result = try await state.api.fixByEarStatus(matchId: id)
                var tries = 0
                while !result.isDone && !result.isFailed && tries < 240 {
                    tries += 1
                    try await Task.sleep(nanoseconds: UInt64((Launch.isMock ? 0.2 : 2) * 1_000_000_000))
                    result = try await state.api.fixByEarStatus(matchId: id)
                }
                if result.isDone, let ranked = result.ranked, !ranked.isEmpty {
                    mergeTake(ranked)
                    await state.refresh()
                } else {
                    earProblem = result.error.map(APIError.sentenceCase)
                        ?? T("Could not compare the recording. Try again.")
                }
            } catch {
                if !Task.isCancelled { earProblem = state.report(error) }
            }
            ear = .idle
        } else {
            player.stop()
            if await recorder.start() {
                ear = .recording
            } else {
                earProblem = T("Kinbir needs the microphone to hear you. Allow it in Settings, then try again.")
            }
        }
    }

    /// Loads the options, starts preparing every reading, and plays the first one.
    private func open() async {
        guard !loaded else { return }
        optionsFailed = nil
        let api = state.api
        Task { await api.warmEngine() }
        do {
            options = try await state.api.fixCandidates(word: target.word)
        } catch {
            optionsFailed = state.report(error)
        }
        loaded = true
        guard let first = options.first else { return }
        // Exactly as the website does: every other reading starts being made at once,
        // in the background, while the first one plays. By the time they are tapped
        // they are usually ready.
        let word = target.word
        for option in options.dropFirst() {
            let id = option.optionId
            Task { _ = try? await api.fixPreview(word: word, optionId: id, custom: nil) }
        }
        await hear(key: "o:\(first.optionId)", optionId: first.optionId, custom: nil)
    }

    private func hear(key: String, optionId: Int?, custom: String?) async {
        problem = nil
        if let ready = clips[key] {
            play(ready, key: key)
            return
        }
        // A newer tap takes over: the older request keeps going on the server (so its
        // reading is ready later) but no longer touches the screen.
        turn += 1
        let mine = turn
        preparing = key
        waited = 0
        firstEver = false
        do {
            var preview = try await firstPreview(optionId: optionId, custom: custom)
            var tries = 0
            while !preview.isDone {
                guard mine == turn else { return }
                if preview.isFailed {
                    preparing = nil
                    problem = T("The voice engine could not say that spelling. Try typing it instead.")
                    return
                }
                if tries >= 90 {
                    preparing = nil
                    problem = T("Still preparing after 3 minutes. Tap play to try again.")
                    return
                }
                firstEver = preview.firstEver ?? firstEver
                tries += 1
                let pause = Launch.isMock ? 0.2 : 2.0
                try await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
                if mine == turn { waited += Int(pause.rounded(.up)) }
                preview = try await state.api.fixPreviewStatus(id: preview.previewId)
            }
            let url = try await state.api.fixPreviewAudio(id: preview.previewId)
            clips[key] = url
            guard mine == turn else { return }
            preparing = nil
            play(url, key: key)
        } catch {
            guard mine == turn else { return }
            preparing = nil
            if !Task.isCancelled { problem = state.report(error) }
        }
    }

    /// The website tries once more after a short pause when the network drops the first ask.
    private func firstPreview(optionId: Int?, custom: String?) async throws -> FixPreview {
        do {
            return try await state.api.fixPreview(word: target.word, optionId: optionId, custom: custom)
        } catch {
            guard APIError.wrap(error).kind == .network else { throw error }
            try await Task.sleep(nanoseconds: 700_000_000)
            return try await state.api.fixPreview(word: target.word, optionId: optionId, custom: custom)
        }
    }

    private func play(_ url: URL, key: String) {
        if player.load(url: url) {
            playingKey = key
            player.toggle()
        }
    }
}

/// Change the words of one sentence, or record it again as it is.
struct SentenceSheet: View {
    let target: SentenceTarget
    let onSave: (String) -> Void
    let onReread: () -> Void
    let onUndo: () -> Void
    let onClose: () -> Void

    @State private var text: String
    @FocusState private var editing: Bool

    init(target: SentenceTarget, onSave: @escaping (String) -> Void, onReread: @escaping () -> Void,
         onUndo: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.target = target
        self.onSave = onSave
        self.onReread = onReread
        self.onUndo = onUndo
        self.onClose = onClose
        _text = State(initialValue: target.pendingText ?? target.sentence.text)
    }

    private var original: String { target.sentence.text }
    private var cleaned: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var changed: Bool { cleaned != original }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    Text(T("Edit this sentence")).font(Theme.heading).foregroundStyle(Theme.black)
                        .accessibilityIdentifier("sentenceHeading")

                    TextEditor(text: $text)
                        .font(Theme.body)
                        .lineSpacing(Theme.amharicLineSpacing)
                        .foregroundStyle(Theme.black)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                        .focused($editing)
                        .card(fill: Theme.grey, padding: 12)
                        .accessibilityIdentifier("sentenceEditor")

                    if changed && cleaned.isEmpty {
                        // All the words were deleted: that means take the sentence out.
                        Button(T("Remove this sentence")) { onSave("") }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("removeSentenceButton")
                    } else if changed {
                        Button(T("Save this edit")) { onSave(cleaned) }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("saveSentenceButton")
                    } else if !target.queued {
                        Button(T("Record this sentence again")) { onReread() }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("rereadButton")
                    }
                    if target.queued {
                        Button(T("Undo")) { onUndo() }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("undoSentenceButton")
                    }
                    NoteText(text: T("Keep the ። at the end. Numbers are spoken as words."))
                }
                .page()
            }
            .background(Theme.white)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Close")) { onClose() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(T("Done")) { editing = false }
                }
            }
        }
        .tint(Theme.black)
    }
}

/// A sentence the user tapped, for `.sheet(item:)`.
struct SentenceTarget: Identifiable, Equatable {
    let sentence: Script.Sentence
    /// The new words already waiting in the list, if any.
    let pendingText: String?
    /// True when an edit or a re-read of this sentence is already in the list.
    let queued: Bool
    var id: String { sentence.id }
}
