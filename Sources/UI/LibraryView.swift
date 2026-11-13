import SwiftUI

/// Recent voiceovers. The server keeps them for 48 hours.
struct LibraryView: View {
    @EnvironmentObject private var state: AppState
    @State private var jobs: [JobSummary] = []
    @State private var videos: [VideoSummary] = []
    @State private var loaded = false
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text(T("Library")).screenTitle()
                    .accessibilityIdentifier("libraryHeading")

                if let problem {
                    ProblemCard(message: problem)
                }

                if !loaded && problem == nil {
                    ProgressView().tint(Theme.black)
                } else if jobs.isEmpty && videos.isEmpty && problem == nil {
                    EmptyState(icon: "square.stack", title: T("Nothing here yet"),
                               detail: T("Your voiceovers and videos appear here for 48 hours."))
                        .accessibilityIdentifier("libraryEmpty")
                } else {
                    if !videos.isEmpty {
                        Text(T("Videos")).font(Theme.heading).foregroundStyle(Theme.black)
                        ForEach(videos) { video in
                            NavigationLink(value: Route.videoJob(video.videoJobId, landscape: video.orientation == "landscape")) {
                                videoRow(video)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("videoRow")
                        }
                        if !jobs.isEmpty {
                            Text(T("Voiceovers")).font(Theme.heading).foregroundStyle(Theme.black)
                        }
                    }
                    ForEach(jobs) { job in
                        NavigationLink(value: Route.job(job.jobId)) {
                            row(job)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("libraryRow")
                    }
                }
            }
            .page()
        }
        .background(Theme.white)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
    }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.black)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Theme.lime))
            .overlay(Circle().strokeBorder(Theme.black, lineWidth: 1))
    }

    private func row(_ job: JobSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
        rowIcon(job.status == "done" ? "play.fill" : "waveform")
        VStack(alignment: .leading, spacing: 8) {
            Text((job.preview ?? "").isEmpty ? T("Voiceover") : (job.preview ?? ""))
                .font(Theme.body).foregroundStyle(Theme.black)
                .lineSpacing(Theme.amharicLineSpacing)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 8) {
                Pill(text: statusLabel(job.status), fill: job.status == "done" ? Theme.lime : Theme.grey)
                if job.status == "done", let hours = Fmt.hoursLeft(job.finishedAt), hours <= 12 {
                    Pill(text: Tf("%@ h left", "\(hours)"), fill: Theme.white)
                }
                Text([Fmt.length(job.audioSec), Fmt.ago(job.finishedAt ?? job.createdAt)]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.small).foregroundStyle(Theme.muted)
            }
        }
        Spacer(minLength: 0)
        }
        .card(fill: Theme.white, padding: 14)
    }

    private func videoRow(_ video: VideoSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
        rowIcon("film")
        VStack(alignment: .leading, spacing: 8) {
            Text((video.preview ?? "").isEmpty ? T("Video") : (video.preview ?? ""))
                .font(Theme.body).foregroundStyle(Theme.black)
                .lineSpacing(Theme.amharicLineSpacing)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 8) {
                Pill(text: video.orientation == "landscape" ? T("Horizontal") : T("Vertical"))
                if let hours = Fmt.hoursLeft(video.finishedAt), hours <= 12 {
                    Pill(text: Tf("%@ h left", "\(hours)"), fill: Theme.white)
                }
                Text([Fmt.length(video.durationSec), Fmt.ago(video.finishedAt)]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.small).foregroundStyle(Theme.muted)
            }
        }
        Spacer(minLength: 0)
        }
        .card(fill: Theme.white, padding: 14)
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "done": return T("Ready")
        case "failed": return T("Did not work")
        case "running": return T("Recording")
        default: return T("In line")
        }
    }

    private func load() async {
        do {
            jobs = try await state.api.jobs().filter { $0.belongsInLibrary }
            videos = (try? await state.api.videos()) ?? []
            problem = nil
        } catch {
            if !Task.isCancelled { problem = state.report(error) }
        }
        loaded = true
    }
}
