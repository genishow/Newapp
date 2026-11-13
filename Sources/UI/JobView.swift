import SwiftUI

/// One voiceover: progress while it is being made, then the player.
struct JobView: View {
    @EnvironmentObject private var state: AppState
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
    @State private var fixing: FixTarget?

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
        .sheet(item: $fixing) { target in
            FixWordSheet(jobId: jobId, target: target, onFixed: {
                fixing = nil
                Task { await reloadAfterChange() }
            }, onClose: { fixing = nil })
            .environmentObject(state)
        }
    }

    // MARK: states

    private var progress: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(job?.isRunning == true ? "Recording your voiceover" : "In line")
                .font(Theme.title).foregroundStyle(Theme.black)
                .accessibilityIdentifier("progressHeading")

            VStack(alignment: .leading, spacing: 12) {
                if problem == nil {
                    ProgressView().tint(Theme.black)
                }
                if let job, let total = job.segmentsTotal, total > 0 {
                    Text("Part \(min((job.segmentsDone ?? 0) + 1, total)) of \(total)")
                        .font(Theme.body).foregroundStyle(Theme.black)
                }
                NoteText(text: "The first voiceover of a session takes a couple of minutes longer while the voice engine wakes up. You can leave this screen. It will be in your Library when it is ready.")
            }
            .card(fill: Theme.grey)

            if let problem {
                ProblemCard(message: problem)
                Button("Try again") {
                    self.problem = nil
                    attempt += 1
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func failed(_ job: JobStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text("This one did not work").font(Theme.title).foregroundStyle(Theme.black)
            ProblemCard(message: job.error.map(APIError.sentenceCase)
                        ?? "The voiceover could not be made. Your credits were returned.")
        }
    }

    private func result(_ job: JobStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text("Your voiceover").font(Theme.title).foregroundStyle(Theme.black)
                .accessibilityIdentifier("resultHeading")

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
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
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
                if let audioProblem {
                    NoteText(text: audioProblem)
                } else if !player.isReady {
                    NoteText(text: "Loading the audio.")
                }
            }
            .card(fill: Theme.lime)

            Button {
                Task { await share() }
            } label: {
                BusyLabel(title: "Share or save", busy: sharing)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sharing)
            .accessibilityIdentifier("shareButton")

            NoteText(text: "Kept for 48 hours. Save it if you need it later.")

            NavigationLink(value: Route.video(jobId)) {
                Text(job.brollPlanId == nil ? "Make a video" : "Continue the video")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("makeVideoLink")

            if !job.scriptText.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Script").font(Theme.small.weight(.medium)).foregroundStyle(Theme.black)
                        Spacer()
                        Button(copied ? "Copied" : "Copy") {
                            UIPasteboard.general.string = job.scriptText
                            copied = true
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                    if job.isEnglish {
                        Text(job.scriptText).font(Theme.body).foregroundStyle(Theme.black)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else {
                        NoteText(text: "A word sounds wrong? Tap it to fix it.")
                        TappableScript(segments: job.segments ?? [],
                                       fixedWords: job.fixedWords ?? []) { fixing = $0 }
                    }
                }
                .card(fill: Theme.white)
            }

            if job.isEnglish {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Emphasis on pauses").font(Theme.small.weight(.medium))
                        .foregroundStyle(Theme.black)
                    Picker("Emphasis", selection: Binding(
                        get: { job.emphasis ?? "none" },
                        set: { level in Task { await changeEmphasis(level) } })
                    ) {
                        ForEach(VoiceOptions.emphases, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    NoteText(text: "Free. The audio is updated at once.")
                }
                .card(fill: Theme.white, padding: 14)
            }

            if let onMakeAnother {
                Button("Make another") { onMakeAnother() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("makeAnotherButton")
            }
        }
    }

    // MARK: work

    private func poll() async {
        while !Task.isCancelled {
            do {
                let latest = try await state.api.job(id: jobId)
                job = latest
                if latest.isDone {
                    await loadAudio()
                    await state.refresh()
                    return
                }
                if latest.isFailed {
                    await state.refresh()
                    return
                }
            } catch {
                if Task.isCancelled { return }
                problem = state.report(error)
                return
            }
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
                audioProblem = "The audio could not be opened. Use Share or save to get the file."
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
