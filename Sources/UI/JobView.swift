import SwiftUI

/// One voiceover: progress while it is being made, then the player and the tools to fix it.
struct JobView: View {
    @EnvironmentObject private var state: AppState
    let jobId: String
    var onMakeAnother: (() -> Void)?

    private enum EditMode { case words, sentences }

    @StateObject private var player = AudioPlayer()
    @State private var job: JobStatus?
    @State private var problem: String?
    @State private var attempt = 0
    @State private var audioProblem: String?
    @State private var sharing = false
    @State private var shared: SharedFile?
    @State private var copied = false
    @State private var startedAt = Date()
    @State private var slow = false

    // Fixing, the website's way: choices wait in a list and are generated together.
    @State private var mode: EditMode = .words
    @State private var fixingWord: FixTarget?
    @State private var fixingSentence: SentenceTarget?
    @State private var pending: [FixEdit] = []
    @State private var applying = false
    @State private var batchId: String?
    @State private var fixProblem: String?
    @State private var fixDone = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                if let job, job.isDone {
                    result(job)
                } else if let job, job.isFailed {
                    failed(job)
                } else {
                    progress
                }
            }
            .page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: attempt) { await poll() }
        .onDisappear { player.stop() }
        .sheet(item: $shared) { file in
            ShareSheet(items: [file.url])
        }
        .sheet(item: $fixingWord) { target in
            WordFixSheet(target: target, occurrences: occurrences(of: target.word),
                         onUse: { fix in
                             queue(fix)
                             fixingWord = nil
                         },
                         onClose: { fixingWord = nil })
                .environmentObject(state)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $fixingSentence) { target in
            SentenceSheet(segment: target.segment, original: target.text,
                          onUse: { fix in
                              queue(fix)
                              fixingSentence = nil
                          },
                          onClose: { fixingSentence = nil })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: making

    /// The website's own progress maths: 4% in line, then the share of parts recorded.
    private var fraction: Double {
        guard let job, job.isRunning, let total = job.segmentsTotal, total > 0 else { return 0.04 }
        return max(0.06, Double(job.segmentsDone ?? 0) / Double(total))
    }

    private var stageLine: String {
        guard let job, job.isRunning else { return T("Waiting in line") }
        guard let total = job.segmentsTotal, total > 1 else { return T("Voicing your narration") }
        return Tf("Voicing part %@ of %@", "\(min((job.segmentsDone ?? 0) + 1, total))", "\(total)")
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("Composing your voiceover")).font(Theme.title).foregroundStyle(Theme.black)
                .accessibilityIdentifier("progressHeading")

            if problem == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text(stageLine).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                        .accessibilityIdentifier("stageLine")
                    ProgressView(value: fraction)
                        .tint(Theme.black)
                        .animation(.easeInOut(duration: 0.4), value: fraction)
                    HStack {
                        Text(T("Voice: ") + (state.activeVoice?.name ?? T("My voice")))
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Fmt.clock(context.date.timeIntervalSince(startedAt))).monospacedDigit()
                        }
                    }
                    .font(Theme.small).foregroundStyle(Theme.muted)
                }
                .card(fill: Theme.lime)

                if slow {
                    Text(T("This is taking longer than usual. It is still working. You can leave this screen and find it later in your Library."))
                        .font(Theme.small).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                        .card(fill: Theme.grey, padding: 14)
                }
            }

            NoteText(text: T("The first voiceover of a session wakes the voice engine and takes about 2 extra minutes. After that it is much faster. You can leave this screen: it keeps going, and the result waits in your Library for 48 hours."))

            if let problem {
                ProblemCard(message: problem)
                Button(T("Try again")) {
                    self.problem = nil
                    attempt += 1
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func failed(_ job: JobStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("This one did not work")).font(Theme.title).foregroundStyle(Theme.black)
            ProblemCard(message: job.error.map(APIError.sentenceCase)
                        ?? T("Something went wrong on our side. Your credits were returned."))
        }
    }

    // MARK: result

    private func result(_ job: JobStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("Your voiceover")).font(Theme.title).foregroundStyle(Theme.black)
                .accessibilityIdentifier("resultHeading")

            playerCard(job)

            NavigationLink(value: Route.video(jobId)) {
                Text(job.brollPlanId == nil ? T("Make a video") : T("Continue the video"))
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("makeVideoLink")

            Button {
                Task { await share() }
            } label: {
                BusyLabel(title: T("Share or save"), busy: sharing)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(sharing)
            .accessibilityIdentifier("shareButton")

            NoteText(text: T("Kept for 48 hours. Save it if you need it later."))

            if job.isEnglish {
                englishScript(job)
            } else if !(job.segments ?? []).isEmpty {
                fixCard(job)
            }

            if let onMakeAnother {
                Button(T("Make another")) { onMakeAnother() }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("makeAnotherButton")
            }
        }
    }

    private func playerCard(_ job: JobStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Theme.black))
                }
                .disabled(!player.isReady)
                .accessibilityLabel(player.isPlaying ? T("Pause") : T("Play"))
                .accessibilityIdentifier("playButton")

                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: Binding(get: { player.position },
                                          set: { player.seek(to: $0) }),
                           in: 0...max(player.duration, 0.1))
                        .tint(Theme.black)
                        .disabled(!player.isReady)
                    HStack {
                        Text(Fmt.clock(player.position))
                        Spacer()
                        Text(Fmt.clock(player.isReady ? player.duration : (job.audioSec ?? 0)))
                    }
                    .font(Theme.small).foregroundStyle(Theme.muted)
                }
            }
            if player.isReady {
                ChipRow {
                    ForEach([0.75, 1.0, 1.25, 1.5], id: \.self) { speed in
                        Chip(title: speed == 1.0 ? "1x" : "\(speed.formatted())x",
                             selected: player.rate == Float(speed)) {
                            player.setRate(Float(speed))
                        }
                    }
                }
            }
            if let audioProblem {
                NoteText(text: audioProblem)
            } else if !player.isReady {
                NoteText(text: T("Loading the audio."))
            }
        }
        .card(fill: Theme.lime)
    }

    /// The script with the two ways to fix it, the waiting changes, and one button to make them.
    private func fixCard(_ job: JobStatus) -> some View {
        let segments = job.segments ?? []
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(mode == .words ? T("Your script · tap a word") : T("Your script · tap a sentence"))
                    .font(Theme.smallMedium).foregroundStyle(Theme.black)
                Spacer()
                Button(copied ? T("Copied") : T("Copy")) {
                    UIPasteboard.general.string = job.scriptText
                    copied = true
                }
                .buttonStyle(QuietButtonStyle())
            }

            ChipRow {
                Chip(title: T("Fix how a word sounds"), selected: mode == .words) { mode = .words }
                Chip(title: T("Change the words"), selected: mode == .sentences) { mode = .sentences }
            }
            .disabled(applying)

            if mode == .words {
                TappableScript(segments: segments,
                               fixedWords: (job.fixedWords ?? []) + pendingWords) { fixingWord = $0 }
                    .disabled(applying)
            } else {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, sentence in
                    Button {
                        fixingSentence = SentenceTarget(segment: index, text: pendingText(for: index) ?? sentence)
                    } label: {
                        AmharicText(text: pendingText(for: index) ?? sentence)
                            .multilineTextAlignment(.leading)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(pending.contains { $0.id == "s:\(index)" } ? Theme.lime : Theme.grey))
                    }
                    .buttonStyle(.plain)
                    .disabled(applying)
                    .accessibilityIdentifier("sentence-\(index)")
                }
            }

            if !pending.isEmpty {
                Text(T("Waiting to be generated")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                FlowLayout(spacing: 8) {
                    ForEach(pending) { fix in
                        Button {
                            pending.removeAll { $0.id == fix.id }
                        } label: {
                            HStack(spacing: 6) {
                                Text(label(for: fix)).font(Theme.small).lineLimit(1)
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(Theme.black)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(Capsule().fill(Theme.lime))
                            .overlay(Capsule().strokeBorder(Theme.black, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(applying)
                    }
                }
            }

            if let fixProblem {
                ProblemCard(message: fixProblem)
            }

            if applying {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.black)
                    Text(T("Recording the changed sentences again.")).font(Theme.body).foregroundStyle(Theme.black)
                }
                Button(T("Stop and get the credits back")) { Task { await stopFixes() } }
                    .buttonStyle(QuietButtonStyle())
            } else if !pending.isEmpty {
                Button(Tf("Generate my %@ changes · 1.5 credits", "\(pending.count)")) {
                    Task { await applyFixes() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("generateChangesButton")
            } else if fixDone {
                Text(T("Done. Your new take is in the player above. Press play to hear it."))
                    .font(Theme.small).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("fixDoneNote")
            } else {
                NoteText(text: T("Pick as many changes as you like. They are all recorded together for 1.5 credits."))
            }
        }
        .card(fill: Theme.white)
    }

    private func englishScript(_ job: JobStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(T("Script")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                Spacer()
                Button(copied ? T("Copied") : T("Copy")) {
                    UIPasteboard.general.string = job.scriptText
                    copied = true
                }
                .buttonStyle(QuietButtonStyle())
            }
            Text(job.scriptText).font(Theme.body).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(T("Emphasis on pauses")).font(Theme.smallMedium).foregroundStyle(Theme.black)
            Picker(T("Emphasis"), selection: Binding(
                get: { job.emphasis ?? "none" },
                set: { level in Task { await changeEmphasis(level) } })
            ) {
                ForEach(VoiceOptions.emphases, id: \.self) { Text(T($0.capitalized)).tag($0) }
            }
            .pickerStyle(.segmented)
            NoteText(text: T("Free. The audio is updated at once."))
        }
        .card(fill: Theme.white)
    }

    // MARK: fix helpers

    private var pendingWords: [String] {
        pending.compactMap { fix in
            switch fix {
            case .option(let word, _), .custom(let word, _): return word
            default: return nil
            }
        }
    }

    private func pendingText(for segment: Int) -> String? {
        for fix in pending {
            if case .editSentence(let s, let text) = fix, s == segment { return text }
        }
        return nil
    }

    private func occurrences(of word: String) -> Int {
        (job?.segments ?? []).reduce(0) { count, sentence in
            count + Words.tokens(in: sentence).filter { $0.word == word }.count
        }
    }

    private func label(for fix: FixEdit) -> String {
        switch fix {
        case .option(let word, _), .custom(let word, _): return word
        case .rereadSentence(let segment): return Tf("Sentence %@ again", "\(segment + 1)")
        case .editSentence(let segment, _): return Tf("Sentence %@ edited", "\(segment + 1)")
        }
    }

    /// A newer choice for the same word or sentence replaces the older one.
    private func queue(_ fix: FixEdit) {
        pending.removeAll { $0.id == fix.id }
        guard pending.count < FixEdit.maxPerBatch else {
            fixProblem = T("That is the most changes for one go. Generate these first.")
            return
        }
        pending.append(fix)
        fixDone = false
        fixProblem = nil
        Haptics.tap()
    }

    private func applyFixes() async {
        applying = true
        fixProblem = nil
        defer { applying = false }
        do {
            var batch = try await state.api.fixApply(jobId: jobId, fixes: pending)
            guard let id = batch.batchId else {
                fixProblem = T("The changes could not be started. Try again.")
                return
            }
            batchId = id
            await state.refresh()
            var misses = 0
            var tries = 0
            while !batch.isOver && tries < 180 {
                tries += 1
                try? await Task.sleep(nanoseconds: UInt64((Launch.isMock ? 0.2 : 2) * 1_000_000_000))
                do {
                    batch = try await state.api.fixStatus(jobId: jobId, batchId: id)
                    misses = 0
                } catch {
                    // The work is already paid for, so a dropped check is not the end.
                    misses += 1
                    if misses >= 8 { throw error }
                }
            }
            if batch.status == "done" {
                pending = []
                fixDone = true
                Haptics.success()
                await reloadAfterChange()
            } else if batch.status == "cancelled" {
                fixProblem = T("Stopped. Your credits were returned.")
            } else {
                Haptics.failure()
                fixProblem = batch.error.map(APIError.sentenceCase)
                    ?? T("The changes did not finish. Your credits were returned.")
            }
            await state.refresh()
        } catch {
            fixProblem = state.report(error)
        }
    }

    private func stopFixes() async {
        guard let batchId else { return }
        try? await state.api.fixCancel(jobId: jobId, batchId: batchId)
    }

    // MARK: work

    private func poll() async {
        startedAt = Date()
        slow = false
        while !Task.isCancelled {
            do {
                let latest = try await state.api.job(id: jobId)
                job = latest
                if latest.isDone {
                    Haptics.success()
                    await loadAudio()
                    await state.refresh()
                    // The website does the same: wake the engine so word fixes start fast.
                    if !latest.isEnglish { await state.api.warmEngine() }
                    return
                }
                if latest.isFailed {
                    Haptics.failure()
                    await state.refresh()
                    return
                }
            } catch {
                if Task.isCancelled { return }
                problem = state.report(error)
                return
            }
            if Date().timeIntervalSince(startedAt) > 180 { slow = true }
            try? await Task.sleep(nanoseconds: UInt64(Launch.jobPollSeconds * 1_000_000_000))
        }
    }

    /// After a fix or an emphasis change the audio at the same address is different.
    private func reloadAfterChange() async {
        player.stop()
        if let latest = try? await state.api.job(id: jobId) { job = latest }
        await loadAudio()
    }

    private func changeEmphasis(_ level: String) async {
        do {
            try await state.api.setEmphasis(jobId: jobId, emphasis: level)
            await reloadAfterChange()
        } catch {
            audioProblem = state.report(error)
        }
    }

    private func loadAudio() async {
        audioProblem = nil
        do {
            let url = try await state.api.playbackAudio(jobId: jobId)
            if !player.load(url: url) {
                audioProblem = T("The audio could not be opened. Use Share or save to get the file.")
            }
        } catch {
            audioProblem = state.report(error)
        }
    }

    private func share() async {
        sharing = true
        defer { sharing = false }
        do {
            let url = try await state.api.downloadAudio(jobId: jobId)
            shared = SharedFile(url: url)
        } catch {
            audioProblem = state.report(error)
        }
    }
}
