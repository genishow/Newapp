import SwiftUI

/// One voiceover: progress while it is being made, then the player and the tools to fix it.
struct JobView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let jobId: String
    var onMakeAnother: (() -> Void)?

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
        // Coming back from the fix screen: the audio may have changed.
        .onAppear {
            if job?.isDone == true { Task { await reloadAfterChange() } }
        }
        .sheet(item: $shared) { file in
            ShareSheet(items: [file.url])
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
            Text(T("Composing your voiceover")).screenTitle()
                .accessibilityIdentifier("progressHeading")

            if problem == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text(stageLine).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                        .accessibilityIdentifier("stageLine")
                    Waveform()
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

            NoteText(text: T("The first one of the day takes about 2 minutes longer. You can leave this screen. It will be in your Library."))

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
            Text(T("This one did not work")).screenTitle()
            ProblemCard(message: job.error.map(APIError.sentenceCase)
                        ?? T("Something went wrong on our side. Your credits were returned."))
            Button(T("Back to my script")) { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: result

    private func result(_ job: JobStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("Your voiceover")).screenTitle()
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
                NavigationLink(value: Route.fix(jobId)) {
                    OptionRow(icon: "wand.and.stars", title: T("Something sound wrong?"),
                              detail: T("Fix a word or change a sentence."))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fixLink")
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
