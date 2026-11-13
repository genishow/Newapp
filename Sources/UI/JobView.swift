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
    @State private var celebrate = false

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
            Text(T("Composing your voiceover")).screenTitle(amharic: A("Composing your voiceover"))
                .accessibilityIdentifier("progressHeading")

            if problem == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text(stageLine).font(Theme.bodyMedium).foregroundStyle(Theme.white)
                        .accessibilityIdentifier("stageLine")
                    Waveform(color: Theme.lime)
                    ProgressView(value: fraction)
                        .tint(Theme.lime)
                        .animation(.easeInOut(duration: 0.4), value: fraction)
                    HStack {
                        Text(T("Voice: ") + (state.activeVoice?.name ?? T("My voice")))
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Fmt.clock(context.date.timeIntervalSince(startedAt))).monospacedDigit()
                        }
                    }
                    .font(Theme.small).foregroundStyle(Theme.grey)
                }
                .card(fill: Theme.black)

                if slow {
                    Text(T("This is taking longer than usual. It is still working. You can leave this screen and find it later in your Library."))
                        .font(Theme.small).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                        .card(fill: Theme.grey, padding: 14)
                }
            }

            NoteText(text: T("You can leave this screen. It will be in your Library."))

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
            Text(T("This one did not work")).screenTitle(amharic: A("This one did not work"))
            ProblemCard(message: job.error.map(APIError.sentenceCase)
                        ?? T("Something went wrong on our side. Your credits were returned."))
            Button(T("Back to my script")) { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: result

    private func result(_ job: JobStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                Text(T("Ready")).font(Theme.smallMedium)
            }
            .foregroundStyle(Theme.black)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Theme.lime))
            .overlay(Capsule().strokeBorder(Theme.black, lineWidth: 1))
            .scaleEffect(celebrate ? 1 : 0.6)
            .opacity(celebrate ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { celebrate = true }
            }
            .accessibilityHidden(true)

            Text(T("Your voiceover")).screenTitle(amharic: A("Your voiceover"))
                .accessibilityIdentifier("resultHeading")

            playerCard(job)

            // Same order as the website: download, fix, then on to the video.
            Button {
                Task { await share() }
            } label: {
                BusyLabel(title: "↓ " + T("Download") + " · " + Fmt.clock(job.audioSec ?? player.duration),
                          busy: sharing)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(sharing)
            .accessibilityIdentifier("shareButton")

            if job.isEnglish {
                englishScript(job)
            } else if !(job.segments ?? []).isEmpty {
                FixView(jobId: jobId, onRegenerated: { Task { await reloadAfterChange() } })
                    .card(fill: Theme.white, padding: 14)
            }

            NavigationLink(value: Route.video(jobId)) {
                Text((job.brollPlanId == nil ? T("Turn this into a video") : T("Continue the video")) + " →")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("makeVideoLink")

            if let onMakeAnother {
                Button(T("Compose another") + " →") { onMakeAnother() }
                    .buttonStyle(QuietButtonStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("makeAnotherButton")
            }

            NoteText(text: T("This file is deleted from our servers within 48 hours. Download it now."))
        }
    }

    private func playerCard(_ job: JobStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Waveform(active: player.isPlaying, bars: 30, color: Theme.lime)
            HStack(spacing: 14) {
                Button {
                    Haptics.tap()
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.black)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Theme.lime))
                }
                .disabled(!player.isReady)
                .accessibilityLabel(player.isPlaying ? T("Pause") : T("Play"))
                .accessibilityIdentifier("playButton")

                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: Binding(get: { player.position },
                                          set: { player.seek(to: $0) }),
                           in: 0...max(player.duration, 0.1))
                        .tint(Theme.lime)
                        .disabled(!player.isReady)
                    Text(Fmt.clock(player.position) + " / "
                         + Fmt.clock(player.isReady ? player.duration : (job.audioSec ?? 0)))
                        .font(Theme.small).monospacedDigit().foregroundStyle(Theme.grey)
                }
            }
            if let audioProblem {
                Text(audioProblem).font(Theme.small).foregroundStyle(Theme.white)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !player.isReady {
                Text(T("Loading the audio.")).font(Theme.small).foregroundStyle(Theme.grey)
            }
        }
        .card(fill: Theme.black)
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
