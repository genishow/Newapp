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
                Text("Library").font(Theme.title).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("libraryHeading")

                if let problem {
                    ProblemCard(message: problem)
                }

                if !loaded && problem == nil {
                    ProgressView().tint(Theme.black)
                } else if jobs.isEmpty && videos.isEmpty && problem == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nothing here yet").font(Theme.heading).foregroundStyle(Theme.black)
                        Text("Your voiceovers and videos appear here for 48 hours.")
                            .font(Theme.body).foregroundStyle(Theme.muted)
                    }
                    .card(fill: Theme.grey)
                    .accessibilityIdentifier("libraryEmpty")
                } else {
                    if !videos.isEmpty {
                        Text("Videos").font(Theme.heading).foregroundStyle(Theme.black)
                        ForEach(videos) { video in
                            NavigationLink(value: Route.videoJob(video.videoJobId)) {
                                videoRow(video)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("videoRow")
                        }
                        if !jobs.isEmpty {
                            Text("Voiceovers").font(Theme.heading).foregroundStyle(Theme.black)
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

    private func row(_ job: JobSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((job.preview ?? "").isEmpty ? "Voiceover" : (job.preview ?? ""))
                .font(Theme.body).foregroundStyle(Theme.black)
                .lineSpacing(Theme.amharicLineSpacing)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 8) {
                Pill(text: statusLabel(job.status), fill: job.status == "done" ? Theme.lime : Theme.grey)
                Text([Fmt.length(job.audioSec), Fmt.ago(job.finishedAt ?? job.createdAt)]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.small).foregroundStyle(Theme.muted)
            }
        }
        .card(fill: Theme.white, padding: 14)
    }

    private func videoRow(_ video: VideoSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((video.preview ?? "").isEmpty ? "Video" : (video.preview ?? ""))
                .font(Theme.body).foregroundStyle(Theme.black)
                .lineSpacing(Theme.amharicLineSpacing)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 8) {
                Pill(text: video.orientation == "landscape" ? "Horizontal" : "Vertical")
                Text([Fmt.length(video.durationSec), Fmt.ago(video.finishedAt)]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.small).foregroundStyle(Theme.muted)
            }
        }
        .card(fill: Theme.white, padding: 14)
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "done": return "Ready"
        case "failed": return "Did not work"
        case "running": return "Recording"
        default: return "In line"
        }
    }

    private func load() async {
        do {
            jobs = try await state.api.jobs()
            videos = (try? await state.api.videos()) ?? []
            problem = nil
        } catch {
            if !Task.isCancelled { problem = state.report(error) }
        }
        loaded = true
    }
}
