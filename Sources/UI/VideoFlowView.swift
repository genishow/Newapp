import AVKit
import SwiftUI

/// A stock clip playing silently on a loop, so a shot can be judged in motion.
struct LoopingPreview: View {
    let url: URL
    var shape: Shape = .landscape
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.black)
            if let player {
                VideoPlayer(player: player).disabled(true)
            }
        }
        .aspectRatio(shape == .portrait ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: shape == .portrait ? 200 : .infinity)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.black, lineWidth: 1))
        .onAppear {
            let queue = AVQueuePlayer()
            queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            player = queue
            queue.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
            looper = nil
        }
    }
}

/// Turns a finished voiceover into a video: choose the shape and footage, plan the
/// shots, fill them with clips, pick music, then render.
struct VideoFlowView: View {
    @EnvironmentObject private var state: AppState
    let jobId: String

    private enum Stage: Equatable {
        case loading, setup, planning, shots
        case video(String)
    }

    @State private var stage: Stage = .loading
    @State private var script = ""
    @State private var shape: Shape = .portrait
    @State private var source: FootageSource = .stock
    @State private var estimate: Double?
    @State private var planId: String?
    @State private var beats: [Beat] = []
    @State private var uploads: [UploadMeta] = []
    @State private var problem: String?
    @State private var working: String?
    /// The stock libraries refused or were unreachable; the user is told to add clips.
    @State private var stockLimited = false
    @State private var showClipPicker = false
    @State private var picking: Beat?
    @State private var tracks: [MusicTrack] = []
    @State private var musicId: String?
    /// On by default: captions are what make a short video look finished.
    @State private var captions = true
    @State private var showSetupOptions = false
    @State private var showPresenter = false
    @State private var avatar = AvatarChoice()
    @State private var audioSec = 0.0
    @State private var starting = false
    /// One-tap mode: plan, fill and render without stopping, when every shot gets footage.
    @State private var auto = false
    @StateObject private var musicPlayer = AudioPlayer()

    private var emptyShots: [Beat] { beats.filter { $0.isEmpty } }
    private var planJobKey: String { "planjob." + jobId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                switch stage {
                case .loading:
                    ProgressView().tint(Theme.black)
                case .setup:
                    setup
                case .planning:
                    planning
                case .shots:
                    shots
                case .video(let id):
                    VideoJobView(videoJobId: id, shape: shape, onEditShots: planId == nil ? nil : {
                        Task {
                            await reloadPlan()
                            stage = .shots
                        }
                    })
                }
            }
            .page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { musicPlayer.stop() }
        .safeAreaInset(edge: .bottom) {
            if stage == .setup {
                BottomBar(problem: problem) { setupBar }
            }
        }
        .sheet(isPresented: $showPresenter) {
            NavigationStack {
                ScrollView {
                    AvatarCard(choice: $avatar, audioSec: audioSec, shape: shape).page()
                }
                .background(Theme.white)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(T("Done")) { showPresenter = false }
                            .accessibilityIdentifier("presenterDone")
                    }
                }
            }
            .tint(Theme.black)
            .environmentObject(state)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showClipPicker) {
            ClipPicker { urls in
                showClipPicker = false
                if !urls.isEmpty { Task { await addClips(urls) } }
            }
        }
        .sheet(item: $picking) { beat in
            ShotSheet(planId: planId ?? "", beat: beat, uploads: uploads, shape: shape) {
                picking = nil
                Task { await reloadPlan() }
            }
            .environmentObject(state)
        }
    }

    // MARK: setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(T("Make a video")).screenTitle()
                .accessibilityIdentifier("videoSetupHeading")

            // The one real choice: where the video will be watched.
            HStack(spacing: 12) {
                shapeTile(.portrait, title: T("Vertical"), detail: "TikTok · Reels · Shorts")
                shapeTile(.landscape, title: T("Horizontal"), detail: "YouTube")
            }

            VStack(spacing: 0) {
                Toggle(isOn: $captions) {
                    Label(T("Captions"), systemImage: "captions.bubble")
                        .font(Theme.bodyMedium).foregroundStyle(Theme.black)
                }
                .tint(Theme.black)
                .frame(minHeight: 48)
                Rectangle().fill(Theme.white).frame(height: 2)
                HStack {
                    Label(T("Music"), systemImage: "music.note")
                        .font(Theme.bodyMedium).foregroundStyle(Theme.black)
                    Spacer()
                    Picker(T("Music"), selection: $musicId) {
                        Text(T("None")).tag(String?.none)
                        ForEach(tracks) { track in
                            Text(track.title ?? T("Track")).tag(String?.some(track.trackId))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.black)
                }
                .frame(minHeight: 48)
            }
            .card(fill: Theme.grey, padding: 14)

            DisclosureGroup(isExpanded: $showSetupOptions) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(T("Footage")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                    Picker(T("Footage"), selection: $source) {
                        ForEach(FootageSource.allCases) { Text(T($0.title)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("sourcePicker")
                    NoteText(text: sourceNote)
                    if source != .stock {
                        clipsCard
                    }
                    Button {
                        showPresenter = true
                    } label: {
                        OptionRow(icon: "person.crop.square", title: T("Add yourself as presenter"),
                                  value: avatar.enabled ? T("On") : T("Off"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("presenterRow")
                    Button {
                        auto = false
                        Task { await startPlan() }
                    } label: {
                        BusyLabel(title: T("Review the shots first"), busy: starting && !auto)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(starting || working != nil || (source == .own && uploads.isEmpty))
                    .accessibilityIdentifier("planButton")
                }
                .padding(.top, 12)
            } label: {
                Text(T("More options")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("setupMoreOptions")
            }
            .tint(Theme.black)
        }
    }

    /// A tile drawn in the shape of the screen the video is for.
    private func shapeTile(_ value: Shape, title: String, detail: String) -> some View {
        let selected = shape == value
        return Button {
            Haptics.tap()
            shape = value
        } label: {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.black, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Theme.black.opacity(0.08) : Theme.white))
                    .frame(width: value == .portrait ? 34 : 60, height: value == .portrait ? 60 : 34)
                    .frame(height: 64)
                Text(title).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                Text(detail).font(Theme.small).foregroundStyle(Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(selected ? Theme.lime : Theme.grey))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.black, lineWidth: selected ? 1.5 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shape-" + value.rawValue)
    }

    /// The setup screen's one main button, with what it will cost in total.
    private var setupTitle: String {
        guard let estimate else { return T("Make my video") }
        let price: String = Fmt.credits(estimate + 2)
        return T("Make my video") + " · ≈ " + price + " " + T("credits")
    }

    @ViewBuilder private var setupBar: some View {
        Button {
            auto = true
            Task { await startPlan() }
        } label: {
            BusyLabel(title: setupTitle, busy: starting && auto)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(starting || working != nil || (source == .own && uploads.isEmpty))
        .accessibilityIdentifier("autoVideoButton")
    }

    private var sourceNote: String {
        switch source {
        case .stock: return T("Kinbir finds free stock clips for every shot.")
        case .mix: return T("Your clips go where they fit. Stock clips fill the rest.")
        case .own: return T("Only clips you add are used.")
        }
    }

    private var clipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(uploads.isEmpty ? T("No clips added yet") : Tf("%@ of your clips added", "\(uploads.count)"))
                .font(Theme.bodyMedium).foregroundStyle(Theme.black)
                .accessibilityIdentifier("clipCount")
            if let working {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.black)
                    Text(working).font(Theme.small).foregroundStyle(Theme.black)
                }
            } else {
                addClipsButton
            }
            NoteText(text: T("Only add footage you filmed or have permission to use."))
        }
        .card(fill: Theme.white)
    }

    @ViewBuilder private var addClipsButton: some View {
        if Launch.isMock {
            // The simulator's photo library is empty, so the UI tests take this path.
            Button(T("Add sample clip")) {
                Task { await addClips([FileManager.default.temporaryDirectory.appendingPathComponent("sample.mov")]) }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("addSampleClipButton")
        } else {
            Button(T("Add my clips")) { showClipPicker = true }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("addClipsButton")
        }
    }

    // MARK: planning

    private var planning: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("Planning your video")).screenTitle()
                .accessibilityIdentifier("planningHeading")
            if problem == nil {
                StepList(steps: auto
                            ? [T("Planning the shots"), T("Finding footage"), T("Making your video")]
                            : [T("Planning the shots"), T("Finding footage"), T("Ready for you to review")],
                         current: working == nil ? 0 : 1,
                         detail: working ?? T("Deciding what each shot should show."),
                         estimate: T("usually 1 to 3 minutes"))
            }
            NoteText(text: T("This can take a few minutes. You can leave this screen and come back."))
            if let problem {
                ProblemCard(message: problem)
                Button(T("Check again")) {
                    self.problem = nil
                    Task { await resumePlanning() }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: shots

    private var shots: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("Your shots")).screenTitle()
                .accessibilityIdentifier("shotsHeading")

            if stockLimited && !emptyShots.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(T("Stock footage is not available right now"))
                        .font(Theme.heading).foregroundStyle(Theme.black)
                    Text(T("The free stock library has reached its limit. Upload your own footage for the empty shots, or try stock again in a few minutes."))
                        .font(Theme.body).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(T("Try stock again")) { Task { await fillShots(stock: true, own: false) } }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(working != nil)
                }
                .card(fill: Theme.lime)
                .accessibilityIdentifier("stockLimitCard")
            } else if !emptyShots.isEmpty && working == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Tf("%@ shots need footage", "\(emptyShots.count)"))
                        .font(Theme.bodyMedium).foregroundStyle(Theme.black)
                    Text(T("Tap a shot to search with other words, or add your own clips."))
                        .font(Theme.small).foregroundStyle(Theme.muted)
                }
                .card(fill: Theme.grey, padding: 14)
            }

            if let working {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.black)
                    Text(working).font(Theme.body).foregroundStyle(Theme.black)
                }
                .card(fill: Theme.grey, padding: 14)
            }

            ForEach(beats.filter { $0.needsFootage }) { beat in
                Button {
                    picking = beat
                } label: {
                    ShotRow(beat: beat, shape: shape)
                }
                .buttonStyle(.plain)
                .disabled(working != nil)
                .accessibilityIdentifier("shotRow-\(beat.beat)")
            }

            if working == nil {
                addClipsButton
            }

            finishCard

            Button {
                showPresenter = true
            } label: {
                OptionRow(icon: "person.crop.square", title: T("Add yourself as presenter"),
                          value: avatar.enabled ? T("On") : T("Off"))
            }
            .buttonStyle(.plain)
            .disabled(working != nil)
            .accessibilityIdentifier("presenterRowShots")

            if let problem {
                ProblemCard(message: problem)
            }

            Button {
                Task { await makeVideo() }
            } label: {
                BusyLabel(title: T("Make video · 2 credits"), busy: starting)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(starting || working != nil || !emptyShots.isEmpty)
            .accessibilityIdentifier("makeVideoButton")

            if !emptyShots.isEmpty {
                NoteText(text: T("Every shot needs footage before the video can be made."))
            }
        }
    }

    private var finishCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(T("Music")).font(Theme.body).foregroundStyle(Theme.black)
                Spacer()
                Picker(T("Music"), selection: $musicId) {
                    Text(T("None")).tag(String?.none)
                    ForEach(tracks) { track in
                        Text(track.title ?? T("Track")).tag(String?.some(track.trackId))
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.black)
                .accessibilityIdentifier("musicPicker")
            }
            if musicId != nil {
                Button(musicPlayer.isPlaying ? T("Stop preview") : T("Listen")) {
                    Task { await toggleMusic() }
                }
                .buttonStyle(QuietButtonStyle())
            }
            Toggle(T("Captions on the video"), isOn: $captions)
                .font(Theme.body).foregroundStyle(Theme.black)
                .tint(Theme.black)
        }
        .card(fill: Theme.grey)
        .onChange(of: musicId) { _, _ in musicPlayer.stop() }
    }

    // MARK: work

    private func load() async {
        guard stage == .loading else { return }
        do {
            let job = try await state.api.job(id: jobId)
            script = job.scriptText
            audioSec = job.audioSec ?? 0
            uploads = (try? await state.api.uploads(jobId: jobId)) ?? []
            tracks = (try? await state.api.music()) ?? []
            // A video with music feels finished, so the first track is chosen to start with.
            if musicId == nil { musicId = tracks.first?.trackId }
            if let existing = job.brollPlanId {
                planId = existing
                await reloadPlan()
                stage = .shots
            } else if UserDefaults.standard.string(forKey: planJobKey) != nil {
                stage = .planning
                await resumePlanning()
            } else {
                stage = .setup
                estimate = try? await state.api.footageEstimate(script: script)
            }
        } catch {
            problem = state.report(error)
            stage = .setup
        }
    }

    private func startPlan() async {
        starting = true
        problem = nil
        defer { starting = false }
        do {
            let submit = try await state.api.planFootage(jobId: jobId, shape: shape, source: source)
            // Saved at once: planning is paid for, so it must never be submitted twice.
            UserDefaults.standard.set(submit.jobId, forKey: planJobKey)
            UserDefaults.standard.set(auto, forKey: planJobKey + ".auto")
            stage = .planning
        } catch {
            problem = state.report(error)
            return
        }
        await resumePlanning()
    }

    private func resumePlanning() async {
        guard let planJob = UserDefaults.standard.string(forKey: planJobKey) else {
            stage = .setup
            return
        }
        auto = auto || UserDefaults.standard.bool(forKey: planJobKey + ".auto")
        var misses = 0
        while !Task.isCancelled {
            do {
                let latest = try await state.api.planJob(id: planJob)
                misses = 0
                if latest.status == "done", let id = latest.result?.planId {
                    planId = id
                    beats = latest.result?.beats ?? []
                    UserDefaults.standard.removeObject(forKey: planJobKey)
                    await state.refresh()
                    await fillShots(stock: source != .own, own: source != .stock)
                    stage = .shots
                    if auto && emptyShots.isEmpty && !beats.isEmpty {
                        await makeVideo()
                    } else if auto {
                        problem = T("Some shots have no footage yet, so the video was not made. Add footage to them, then tap Make video.")
                    }
                    auto = false
                    UserDefaults.standard.removeObject(forKey: planJobKey + ".auto")
                    return
                }
                if latest.status == "failed" {
                    UserDefaults.standard.removeObject(forKey: planJobKey)
                    problem = latest.error.map(APIError.sentenceCase)
                        ?? "The plan could not be made. Your credits were returned."
                    stage = .setup
                    return
                }
            } catch {
                if Task.isCancelled { return }
                misses += 1
                if misses >= 4 {
                    problem = state.report(error)
                    return
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(Launch.jobPollSeconds * 1_000_000_000))
        }
    }

    /// Fills the shots: stock search first, then the user's own clips on top.
    private func fillShots(stock: Bool, own: Bool) async {
        guard let planId else { return }
        problem = nil
        if stock {
            working = T("Finding footage for your shots.")
            stockLimited = false
            var refusals = 0
            for _ in 0..<20 {
                do {
                    let slice = try await state.api.searchFootage(planId: planId, shape: shape,
                                                                  beat: nil, query: nil)
                    if slice.stockLimited {
                        refusals += 1
                        if refusals >= 2 {
                            stockLimited = true
                            break
                        }
                        let wait = Launch.isMock ? 0.2 : Double(min(slice.retryAfter ?? 10, 20))
                        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                        continue
                    }
                    if (slice.remaining ?? 0) == 0 { break }
                } catch {
                    problem = state.report(error)
                    break
                }
            }
        }
        if own && !uploads.isEmpty {
            working = T("Placing your clips.")
            for _ in 0..<30 {
                do {
                    let match = try await state.api.matchOwnClips(planId: planId,
                                                                  fill: source == .own || stockLimited)
                    if (match.pendingLabels ?? 0) == 0 { break }
                    try? await Task.sleep(nanoseconds: UInt64((Launch.isMock ? 0.2 : 8) * 1_000_000_000))
                } catch {
                    problem = state.report(error)
                    break
                }
            }
        }
        await reloadPlan()
        working = nil
    }

    private func reloadPlan() async {
        guard let planId else { return }
        do {
            let stored = try await state.api.plan(id: planId)
            beats = stored.beats ?? beats
            if let raw = stored.orientation, let saved = Shape(rawValue: raw) { shape = saved }
            if let raw = stored.source, let saved = FootageSource(rawValue: raw) { source = saved }
        } catch {
            problem = state.report(error)
        }
    }

    private func addClips(_ urls: [URL]) async {
        problem = nil
        var done = 0
        for url in urls {
            let label = Tf("Uploading clip %@ of %@", "\(done + 1)", "\(urls.count)")
            working = label
            do {
                let meta = try await state.api.uploadClip(fileURL: url, jobId: jobId) { fraction in
                    working = label + " · \(Int(fraction * 100))%"
                }
                uploads.append(meta)
                done += 1
            } catch {
                problem = state.report(error)
                break
            }
        }
        working = nil
        // With a plan already made, new clips go straight onto the shots.
        if planId != nil && done > 0 {
            await fillShots(stock: false, own: true)
        }
    }

    private func toggleMusic() async {
        if musicPlayer.isPlaying {
            musicPlayer.stop()
            return
        }
        guard let musicId else { return }
        do {
            let url = try await state.api.musicAudio(trackId: musicId)
            if musicPlayer.load(url: url) { musicPlayer.toggle() }
        } catch {
            problem = state.report(error)
        }
    }

    private func makeVideo() async {
        guard let planId else { return }
        starting = true
        problem = nil
        musicPlayer.stop()
        defer { starting = false }
        do {
            let submit = try await state.api.assemble(planId: planId, shape: shape,
                                                      musicId: musicId, captions: captions,
                                                      avatar: avatar.enabled ? avatar : nil)
            await state.refresh()
            stage = .video(submit.jobId)
        } catch {
            problem = state.report(error)
        }
    }
}

/// One shot in the list: its picture, its place in the video, the words it covers.
struct ShotRow: View {
    let beat: Beat
    var shape: Shape = .portrait

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ClipThumb(candidate: beat.chosen)
                .frame(width: shape == .portrait ? 63 : 128, height: shape == .portrait ? 112 : 72)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(Tf("Shot %@", "\(beat.beat)")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                    Text(Fmt.clock(beat.start ?? 0)).font(Theme.small).foregroundStyle(Theme.muted)
                    if beat.isEmpty {
                        Pill(text: T("Needs footage"), fill: Theme.white)
                    } else if beat.chosen?.isOwn == true {
                        Pill(text: T("Yours"))
                    }
                }
                Text(beat.says ?? beat.mustShow ?? "")
                    .font(Theme.small).foregroundStyle(Theme.muted)
                    .lineSpacing(4)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .card(fill: beat.isEmpty ? Theme.grey : Theme.white, padding: 12)
    }
}

/// A clip's picture. Stock clips have one; the user's own clips show a film mark.
struct ClipThumb: View {
    let candidate: Candidate?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.grey)
            if let url = candidate?.posterURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView().tint(Theme.black)
                }
            } else {
                Image(systemName: candidate == nil ? "questionmark" : "film")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.black, lineWidth: 1))
    }
}

/// Change one shot: pick another clip, search with other words, or use your own clip.
struct ShotSheet: View {
    @EnvironmentObject private var state: AppState
    let planId: String
    @State var beat: Beat
    let uploads: [UploadMeta]
    var shape: Shape = .portrait
    let onClose: () -> Void

    @State private var query = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var note: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    Text(Tf("Shot %@", "\(beat.beat)")).screenTitle()
                        .accessibilityIdentifier("shotSheetHeading")
                    if let says = beat.says, !says.isEmpty {
                        AmharicText(text: says, font: Theme.small)
                    }

                    if let problem {
                        ProblemCard(message: problem)
                    }

                    if let link = beat.chosen?.previewLink, link.hasPrefix("http"), let url = URL(string: link) {
                        LoopingPreview(url: url, shape: shape).id(link)
                    }

                    if let list = beat.candidates, !list.isEmpty {
                        Text(T("Tap a clip to use it")).font(Theme.smallMedium)
                            .foregroundStyle(Theme.black)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, clip in
                                Button {
                                    Task { await choose(clip) }
                                } label: {
                                    ClipThumb(candidate: clip)
                                        .aspectRatio(shape == .portrait ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
                                        .overlay(alignment: .topLeading) {
                                            if index == 0 { Pill(text: T("In use")).padding(4) }
                                        }
                                }
                                .buttonStyle(.plain)
                                .disabled(busy)
                                .accessibilityIdentifier("clip-\(index)")
                            }
                        }
                    } else {
                        Text(T("No clip found for this shot yet."))
                            .font(Theme.body).foregroundStyle(Theme.black)
                            .card(fill: Theme.grey, padding: 14)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(T("Search with other words")).font(Theme.smallMedium)
                            .foregroundStyle(Theme.black)
                        TextField(beat.query ?? T("For example: coffee cup"), text: $query)
                            .textInputAutocapitalization(.never)
                            .field()
                            .accessibilityIdentifier("shotQueryField")
                        Button {
                            Task { await search() }
                        } label: {
                            BusyLabel(title: T("Search stock footage"), busy: busy)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(busy)
                        .accessibilityIdentifier("shotSearchButton")
                        if let note { NoteText(text: note) }
                    }

                    if !uploads.isEmpty {
                        Text(T("Use one of your clips")).font(Theme.smallMedium)
                            .foregroundStyle(Theme.black)
                        ForEach(uploads) { upload in
                            Button {
                                Task { await use(upload) }
                            } label: {
                                HStack {
                                    Image(systemName: "film").foregroundStyle(Theme.black)
                                    Text(upload.name ?? T("My clip")).font(Theme.body)
                                        .foregroundStyle(Theme.black).lineLimit(1)
                                    Spacer()
                                    Text(Fmt.length(upload.duration)).font(Theme.small)
                                        .foregroundStyle(Theme.muted)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                        }
                    }
                }
                .page()
            }
            .background(Theme.white)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Done")) { onClose() }
                        .accessibilityIdentifier("shotSheetDone")
                }
            }
        }
        .tint(Theme.black)
    }

    private func choose(_ clip: Candidate) async {
        guard clip.clipId != beat.chosen?.clipId else {
            onClose()
            return
        }
        busy = true
        problem = nil
        defer { busy = false }
        do {
            try await state.api.chooseClip(planId: planId, beat: beat.beat, clipId: clip.clipId)
            onClose()
        } catch {
            problem = state.report(error)
        }
    }

    private func search() async {
        busy = true
        problem = nil
        note = nil
        defer { busy = false }
        do {
            let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await state.api.searchFootage(planId: planId, shape: nil,
                                                           beat: beat.beat, query: words)
            if result.stockLimited {
                note = T("Stock footage is not available right now. Use one of your own clips, or try again in a few minutes.")
                return
            }
            if let fresh = try await state.api.plan(id: planId).beats?.first(where: { $0.beat == beat.beat }) {
                beat = fresh
            }
            if beat.candidates?.isEmpty != false {
                note = T("Nothing found. Try simpler words, like one object or place.")
            } else if beat.exhausted == true {
                note = T("No new clips for those words. Try different words.")
            }
        } catch {
            problem = state.report(error)
        }
    }

    private func use(_ upload: UploadMeta) async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            _ = try await state.api.useUpload(planId: planId, beat: beat.beat, uploadId: upload.uploadId)
            onClose()
        } catch {
            problem = state.report(error)
        }
    }
}
