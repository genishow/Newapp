import SwiftUI

/// Recent voiceovers. The server keeps them for 48 hours.
struct LibraryView: View {
    @EnvironmentObject private var state: AppState
    @State private var jobs: [JobSummary] = []
    @State private var videos: [VideoSummary] = []
    @State private var loaded = false
    @State private var problem: String?
    /// The item the person asked to delete, until they confirm.
    @State private var deleting: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                PageHeader()
                Text(T("Library")).screenTitle(amharic: A("Library"))
                    .accessibilityIdentifier("libraryHeading")

                if let problem {
                    ProblemCard(message: problem)
                }

                if !loaded && problem == nil && items.isEmpty {
                    ProgressView().tint(Theme.black)
                } else if jobs.isEmpty && videos.isEmpty && problem == nil {
                    EmptyState(icon: "square.stack", title: T("Nothing here yet"),
                               detail: T("Your voiceovers and videos appear here for 48 hours."))
                        .accessibilityIdentifier("libraryEmpty")
                } else {
                    NoteText(text: T("Files are kept for 48 hours. Save what you want to keep."))
                        .accessibilityIdentifier("libraryKeepNote")
                    // One list, newest first: videos and voiceovers together.
                    // Lazy, so only the rows on screen are drawn.
                    LazyVStack(alignment: .leading, spacing: Theme.gap) {
                    ForEach(items) { item in
                        switch item {
                        case .video(let video):
                            NavigationLink(value: Route.videoJob(video.videoJobId, landscape: video.orientation == "landscape")) {
                                videoRow(video)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("videoRow")
                            .overlay(alignment: .topTrailing) { rowMenu(id: video.videoJobId) }
                        case .voiceover(let job):
                            NavigationLink(value: Route.job(job.jobId)) {
                                row(job)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("libraryRow")
                            .overlay(alignment: .topTrailing) { rowMenu(id: job.jobId) }
                        }
                    }
                    }
                }
            }
            .page()
        }
        .background(Theme.white)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .confirmationDialog(T("Delete this from your Library?"),
                            isPresented: Binding(get: { deleting != nil },
                                                 set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button(T("Delete"), role: .destructive) {
                if let id = deleting { Task { await delete(id) } }
                deleting = nil
            }
            Button(T("Cancel"), role: .cancel) { deleting = nil }
        } message: {
            Text(T("It cannot be brought back. Credits are not returned."))
        }
        .task {
            // Show the last list straight away, then refresh behind it.
            if !loaded, let cached = state.loadLibraryCache() {
                jobs = cached.jobs
                videos = cached.videos
            }
            await load()
        }
    }

    enum Item: Identifiable {
        case video(VideoSummary)
        case voiceover(JobSummary)

        var id: String {
            switch self {
            case .video(let v): return "v:" + v.videoJobId
            case .voiceover(let j): return "j:" + j.jobId
            }
        }

        /// Still being made counts as newest, so it sits on top.
        var when: Date {
            switch self {
            case .video(let v): return Fmt.date(fromServer: v.finishedAt) ?? .distantFuture
            case .voiceover(let j):
                return Fmt.date(fromServer: j.finishedAt ?? j.createdAt) ?? .distantFuture
            }
        }
    }

    /// Newest on top, oldest at the bottom.
    static func merged(jobs: [JobSummary], videos: [VideoSummary]) -> [Item] {
        let all = videos.map(Item.video) + jobs.map(Item.voiceover)
        return all.enumerated()
            .sorted { $0.element.when != $1.element.when ? $0.element.when > $1.element.when : $0.offset < $1.offset }
            .map(\.element)
    }

    private var items: [Item] {
        let fresh = LibraryCache(jobs: jobs, videos: videos).fresh()
        return Self.merged(jobs: fresh.jobs, videos: fresh.videos)
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
                if job.status == "done", let hours = Fmt.hoursLeft(job.finishedAt) {
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
                if let hours = Fmt.hoursLeft(video.finishedAt) {
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

    /// The three dots on a row: delete it now instead of waiting 48 hours.
    private func rowMenu(id: String) -> some View {
        Menu {
            Button(role: .destructive) { deleting = id } label: {
                Label(T("Delete"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(T("More"))
        .accessibilityIdentifier("rowMenu-" + id)
    }

    private func delete(_ id: String) async {
        problem = nil
        do {
            try await state.api.deleteLibraryItem(id: id)
            jobs.removeAll { $0.jobId == id }
            videos.removeAll { $0.videoJobId == id }
            state.saveLibraryCache(LibraryCache(jobs: jobs, videos: videos))
        } catch {
            problem = state.report(error)
        }
    }

    private func load() async {
        do {
            // Both lists at the same time, not one after the other.
            async let videoList = try? state.api.videos()
            let jobList = try await state.api.jobs().filter { $0.belongsInLibrary }
            jobs = jobList
            videos = await videoList ?? []
            problem = nil
            state.saveLibraryCache(LibraryCache(jobs: jobs, videos: videos))
        } catch {
            if !Task.isCancelled { problem = state.report(error) }
        }
        loaded = true
    }
}
