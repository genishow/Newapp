import AVKit
import SwiftUI

/// One video: progress while it renders, then the player and Save.
struct VideoJobView: View {
    @EnvironmentObject private var state: AppState
    let videoJobId: String
    /// Vertical or horizontal, when the caller already knows it.
    var shape: Shape?
    /// Goes back to the shots, to change something and make the video again.
    var onEditShots: (() -> Void)?

    @State private var status: AssembleStatus?
    @State private var problem: String?
    @State private var attempt = 0
    @State private var player: AVPlayer?
    @State private var saving = false
    @State private var savingAvatar = false
    @State private var stopping = false
    @State private var shared: SharedFile?
    @State private var refundNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            if let status, status.isDone {
                done(status)
            } else if let status, status.status == "cancelled" {
                Text(T("Stopped")).screenTitle()
                NoteText(text: refundNote ?? T("The video was stopped and the credits were returned."))
                editShotsButton(primary: true)
            } else if let status, status.status == "failed" {
                Text(T("This one did not work")).screenTitle()
                ProblemCard(message: status.error.map(APIError.sentenceCase)
                            ?? T("The video could not be made. Your credits were returned."))
                editShotsButton(primary: true)
            } else {
                rendering
            }
        }
        .task(id: attempt) { await poll() }
        .onDisappear { player?.pause() }
        .sheet(item: $shared) { file in
            ShareSheet(items: [file.url])
        }
    }

    private var rendering: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("Making your video")).screenTitle()
                .accessibilityIdentifier("videoProgressHeading")
            if problem == nil {
                StepList(steps: [T("In line"), T("Putting the clips together"), T("Finishing")],
                         current: status?.status == "running" ? 1 : 0,
                         detail: clipDetail,
                         estimate: T("usually 2 to 5 minutes"))
            }
            NoteText(text: T("This takes a few minutes. You can leave this screen. The video will be in your Library when it is ready."))

            if let problem {
                ProblemCard(message: problem)
                Button(T("Check again")) {
                    self.problem = nil
                    attempt += 1
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button {
                    Task { await stop() }
                } label: {
                    BusyLabel(title: T("Stop and get the credits back"), busy: stopping)
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(stopping)
            }
        }
    }

    private var clipDetail: String? {
        guard let status, let total = status.filesTotal, total > 0 else { return nil }
        return Tf("Clip %@ of %@", "\(min(status.filesDone ?? 0, total))", "\(total)")
    }

    private func done(_ status: AssembleStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("Your video")).screenTitle()
                .accessibilityIdentifier("videoReadyHeading")

            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(isLandscape(status) ? 16.0 / 9.0 : 9.0 / 16.0, contentMode: .fit)
                    .frame(maxWidth: isLandscape(status) ? .infinity : 300)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.black, lineWidth: 1))
            } else {
                Text(T("The preview is not available here. Save the video to watch it."))
                    .font(Theme.body).foregroundStyle(Theme.black)
                    .card(fill: Theme.lime)
            }

            Button {
                Task { await save() }
            } label: {
                BusyLabel(title: saving ? T("Downloading") : T("Save or share video"), busy: saving)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(saving)
            .accessibilityIdentifier("saveVideoButton")

            if status.avatarFile == true {
                Button {
                    Task { await saveAvatar() }
                } label: {
                    BusyLabel(title: T("Save the presenter clip"), busy: savingAvatar)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(savingAvatar)
                .accessibilityIdentifier("saveAvatarButton")
            }
            if let skipped = status.avatarSkipped, !skipped.isEmpty {
                NoteText(text: T("Presenter: ") + APIError.sentenceCase(skipped))
            }

            if let problem {
                ProblemCard(message: problem)
            }
            editShotsButton(primary: false)

            NoteText(text: [Fmt.length(status.durationSec), T("Kept for 48 hours. Save it if you need it later.")]
                .filter { !$0.isEmpty }.joined(separator: " · "))
        }
    }

    @ViewBuilder private func editShotsButton(primary: Bool) -> some View {
        if let onEditShots {
            if primary {
                Button(T("Back to the shots")) { onEditShots() }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button(T("Change shots and make it again")) { onEditShots() }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("editShotsButton")
            }
        }
    }

    private func isLandscape(_ status: AssembleStatus) -> Bool {
        if let raw = status.orientation, let known = Shape(rawValue: raw) { return known == .landscape }
        return shape == .landscape
    }

    private func poll() async {
        var misses = 0
        while !Task.isCancelled {
            do {
                let latest = try await state.api.assembleStatus(id: videoJobId)
                status = latest
                misses = 0
                if latest.isOver {
                    if latest.isDone { Haptics.success() } else if latest.status == "failed" { Haptics.failure() }
                    if latest.isDone, player == nil,
                       let url = state.api.absoluteURL(latest.playPath) {
                        player = AVPlayer(url: url)
                    }
                    await state.refresh()
                    return
                }
            } catch {
                if Task.isCancelled { return }
                // The render is already paid for, so a dropped check is not the end.
                misses += 1
                if misses >= 4 {
                    problem = state.report(error)
                    return
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(Launch.jobPollSeconds * 1_000_000_000))
        }
    }

    private func stop() async {
        stopping = true
        defer { stopping = false }
        do {
            let answer = try await state.api.stopAssemble(id: videoJobId)
            if let back = answer.creditsRefunded, back > 0 {
                refundNote = Tf("The video was stopped. %@ credits were returned.", Fmt.credits(back))
            }
            attempt += 1
            await state.refresh()
        } catch {
            problem = state.report(error)
        }
    }

    private func saveAvatar() async {
        savingAvatar = true
        problem = nil
        defer { savingAvatar = false }
        do {
            let url = try await state.api.downloadAvatarClip(videoJobId: videoJobId)
            shared = SharedFile(url: url)
        } catch {
            problem = state.report(error)
        }
    }

    private func save() async {
        saving = true
        problem = nil
        defer { saving = false }
        do {
            let url = try await state.api.downloadVideo(id: videoJobId)
            shared = SharedFile(url: url)
        } catch {
            problem = state.report(error)
        }
    }
}

/// A finished or running video opened from the Library.
struct VideoJobScreen: View {
    let videoJobId: String
    var shape: Shape?

    var body: some View {
        ScrollView {
            VideoJobView(videoJobId: videoJobId, shape: shape).page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
    }
}
