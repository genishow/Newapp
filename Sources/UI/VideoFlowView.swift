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

    @State private var render = RenderOptions()
    @State private var shotLength = "auto"

    /// The website's finishing choices: quality, music loudness, caption font, graphics.
    @ViewBuilder private var renderRows: some View {
        menuRow(T("Quality"), value: render.quality.uppercased()) {
            ForEach(RenderOptions.qualities, id: \.self) { quality in
                Button(quality.uppercased()) { render.quality = quality }
            }
        }
        .accessibilityIdentifier("qualityMenu")
        if musicId != nil {
            menuRow(T("Music loudness"),
                    value: T(RenderOptions.musicLevels.first { $0.id == render.musicLevel }?.title ?? "Normal")) {
                ForEach(RenderOptions.musicLevels, id: \.id) { level in
                    Button(T(level.title)) { render.musicLevel = level.id }
                }
            }
        }
        if captions {
            menuRow(T("Caption font"),
                    value: T(RenderOptions.fonts.first { $0.id == render.captionFont }?.title ?? "Standard")) {
                ForEach(RenderOptions.fonts, id: \.id) { font in
                    Button(T(font.title)) { render.captionFont = font.id }
                }
            }
        }
        Toggle(T("On-screen graphics"), isOn: $render.graphics)
            .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
        if render.graphics {
            menuRow(T("Graphics colour"), value: T(render.graphicsColor.capitalized)) {
                ForEach(RenderOptions.colors, id: \.self) { color in
                    Button(T(color.capitalized)) { render.graphicsColor = color }
                }
            }
        }
    }

    /// A label on the left and a menu on the right showing the current choice.
    private func menuRow<Items: View>(_ title: String, value: String,
                                      @ViewBuilder items: () -> Items) -> some View {
        HStack {
            Text(title).font(Theme.body).foregroundStyle(Theme.black)
            Spacer()
            Menu {
                items()
            } label: {
                HStack(spacing: 4) {
                    Text(value).font(Theme.bodyMedium)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Theme.black)
                .frame(minHeight: 44)
            }
        }
    }

    private var emptyShots: [Beat] { beats.filter { $0.isEmpty } }

    /// The shot before or after this one, skipping music breaks.
    private func neighbour(of beat: Beat, step: Int) -> Int? {
        let shots = beats.filter { $0.needsFootage }
        guard let i = shots.firstIndex(where: { $0.beat == beat.beat }) else { return nil }
        let j = i + step
        return shots.indices.contains(j) ? shots[j].beat : nil
    }
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
            ShotSheet(planId: planId ?? "", beat: beat, uploads: uploads, shape: shape,
                      previous: neighbour(of: beat, step: -1), next: neighbour(of: beat, step: 1)) {
                picking = nil
                Task { await reloadPlan() }
            }
            .environmentObject(state)
        }
    }

    // MARK: setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(T("Make a video")).screenTitle(amharic: A("Make a video"))
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
                    menuRow(T("Shot length"),
                            value: T(RenderOptions.shotLengths.first { $0.id == shotLength }?.title ?? "Same as before")) {
                        ForEach(RenderOptions.shotLengths, id: \.id) { item in
                            Button(T(item.title)) { shotLength = item.id }
                        }
                    }
                    .accessibilityIdentifier("shotLengthMenu")
                    renderRows
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
            Text(T("Planning your video")).screenTitle(amharic: A("Planning your video"))
                .accessibilityIdentifier("planningHeading")
            if problem == nil {
                StepList(steps: auto
                            ? [T("Planning the shots"), T("Finding footage"), T("Making your video")]
                            : [T("Planning the shots"), T("Finding footage"), T("Ready for you to review")],
                         current: working == nil ? 0 : 1,
                         detail: working ?? T("Deciding what each shot should show."),
                         estimate: T("usually 1 to 3 minutes"))
            }
            NoteText(text: T("You can leave this screen and come back."))
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
            Text(T("Your shots")).screenTitle(amharic: A("Your shots"))
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
                    Button(T("Find footage for the empty shots")) { Task { await autofill() } }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("autofillButton")
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

            Button(T("Start a new shot list")) {
                planId = nil
                beats = []
                stage = .setup
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(starting || working != nil)
            .accessibilityIdentifier("newShotListButton")
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
            renderRows
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
            let submit = try await state.api.planFootage(jobId: jobId, shape: shape, source: source,
                                                         shotLength: shotLength)
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
                    let match = try await state.api.matchOwnClips(planId: planId, fill: source == .own)
                    if (match.pendingLabels ?? 0) == 0 { break }
                    try? await Task.sleep(nanoseconds: UInt64((Launch.isMock ? 0.2 : 8) * 1_000_000_000))
                } catch {
                    problem = state.report(error)
                    break
                }
            }
        }
        await reloadPlan()
        await preferRightShape()
        working = nil
    }

    /// When the clip in use has the wrong shape and one with the right shape was found,
    /// the right one is put in use. The other stays in the list to pick by hand.
    private func preferRightShape() async {
        guard let planId else { return }
        var changed = false
        for beat in beats where beat.needsFootage {
            guard let chosen = beat.chosen, !chosen.isOwn, !chosen.fits(shape),
                  let better = beat.candidates?.first(where: { $0.fits(shape) }) else { continue }
            if (try? await state.api.chooseClip(planId: planId, beat: beat.beat, clipId: better.clipId)) != nil {
                changed = true
            }
        }
        if changed { await reloadPlan() }
    }

    /// The website's "Find footage for all empty shots". Free.
    private func autofill() async {
        guard let planId else { return }
        problem = nil
        working = T("Finding footage for the empty shots.")
        defer { working = nil }
        do {
            let submit = try await state.api.autofill(planId: planId)
            for _ in 0..<90 {
                let job = try await state.api.planJob(id: submit.jobId)
                if job.status == "done" { break }
                if job.status == "failed" {
                    problem = job.error.map(APIError.sentenceCase) ?? T("No footage was found. Try your own words on each shot.")
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(Launch.jobPollSeconds * 1_000_000_000))
            }
            await reloadPlan()
            await preferRightShape()
        } catch {
            problem = state.report(error)
        }
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
                                                      avatar: avatar.enabled ? avatar : nil,
                                                      options: render)
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
                    } else if let chosen = beat.chosen, !chosen.fits(shape), let label = chosen.aspectLabel {
                        Pill(text: label, fill: Theme.white)
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

/// A clip's picture, cropped to fill the frame it is given. Stock clips have one; the
/// user's own clips show a film mark.
struct ClipThumb: View {
    let candidate: Candidate?

    var body: some View {
        // The picture is an overlay of a box with a fixed size, so a wide picture is cropped
        // to the box instead of spilling out of it.
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.grey)
            .overlay {
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
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.black, lineWidth: 1))
    }
}

/// Change one shot the way the website lets you: watch a clip before using it, find
/// different clips, search with your own words, use your own clip, remove the clip,
/// move the shot, split it or merge it.
struct ShotSheet: View {
    @EnvironmentObject private var state: AppState
    let planId: String
    @State var beat: Beat
    let uploads: [UploadMeta]
    var shape: Shape = .portrait
    /// The shots before and after this one, for Move earlier / Move later.
    var previous: Int?
    var next: Int?
    let onClose: () -> Void

    @State private var query = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var note: String?
    /// The clip being watched. It is only used when "Use this clip" is tapped.
    @State private var watching: Candidate?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    /// Clips in the video's shape first; the other shape after them, marked.
    private var clips: [Candidate] {
        let list = beat.candidates ?? []
        return list.filter { $0.fits(shape) } + list.filter { !$0.fits(shape) }
    }

    private var shown: Candidate? { watching ?? beat.chosen }

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

                    if let link = shown?.previewLink, link.hasPrefix("http"), let url = URL(string: link) {
                        LoopingPreview(url: url, shape: shape).id(link)
                    }
                    if let watching, watching.clipId != beat.chosen?.clipId {
                        Button {
                            Task { await choose(watching) }
                        } label: {
                            BusyLabel(title: T("Use this clip"), busy: busy)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(busy)
                        .accessibilityIdentifier("useClipButton")
                    }

                    if !clips.isEmpty {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                                Button {
                                    Haptics.tap()
                                    watching = clip
                                } label: {
                                    ClipThumb(candidate: clip)
                                        .aspectRatio(shape == .portrait ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
                                        .overlay(alignment: .topLeading) {
                                            if clip.clipId == beat.chosen?.clipId {
                                                Pill(text: T("In use")).padding(4)
                                            }
                                        }
                                        .overlay(alignment: .bottomTrailing) {
                                            if !clip.fits(shape), let label = clip.aspectLabel {
                                                Pill(text: label, fill: Theme.white).padding(4)
                                            }
                                        }
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Theme.black, lineWidth: shown?.clipId == clip.clipId ? 3 : 0))
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

                    Button {
                        Task { await search(words: "") }
                    } label: {
                        BusyLabel(title: T("Find different clips"), busy: busy)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(busy)
                    .accessibilityIdentifier("findDifferentButton")

                    VStack(alignment: .leading, spacing: 10) {
                        Text(T("Say what this shot should show")).font(Theme.smallMedium)
                            .foregroundStyle(Theme.black)
                        HStack(spacing: 8) {
                            TextField(beat.query ?? T("For example: coffee cup"), text: $query)
                                .textInputAutocapitalization(.never)
                                .field()
                                .accessibilityIdentifier("shotQueryField")
                            Button(T("Search")) {
                                Task { await search(words: query.trimmingCharacters(in: .whitespacesAndNewlines)) }
                            }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("shotSearchButton")
                        }
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

                    tools
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

    /// The website's shot tools.
    private var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Shot tools")).font(Theme.smallMedium).foregroundStyle(Theme.black)
            ChipRow {
                if let previous {
                    Chip(title: "↑ " + T("Move earlier")) { Task { await tool("swap", with: previous) } }
                }
                if let next {
                    Chip(title: "↓ " + T("Move later")) { Task { await tool("swap", with: next) } }
                }
                Chip(title: T("Split in two")) { Task { await tool("split", with: nil) } }
                if next != nil {
                    Chip(title: T("Merge with next")) { Task { await tool("merge", with: nil) } }
                }
                if beat.chosen != nil {
                    Chip(title: T("Remove clip")) { Task { await tool("clear", with: nil) } }
                }
            }
            .disabled(busy)
        }
        .accessibilityIdentifier("shotTools")
    }

    private func choose(_ clip: Candidate) async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            try await state.api.chooseClip(planId: planId, beat: beat.beat, clipId: clip.clipId)
            Haptics.success()
            onClose()
        } catch {
            let wrapped = APIError.wrap(error)
            if wrapped.status == 404 {
                // The list changed on the server. Show the fresh one, as the website does.
                await refresh()
                watching = nil
                problem = T("The clips changed. Pick again.")
            } else {
                problem = state.report(error)
            }
        }
    }

    private func refresh() async {
        if let fresh = try? await state.api.plan(id: planId).beats?.first(where: { $0.beat == beat.beat }) {
            beat = fresh
        }
    }

    private func search(words: String) async {
        busy = true
        problem = nil
        note = nil
        defer { busy = false }
        do {
            let result = try await state.api.searchFootage(planId: planId, shape: nil,
                                                           beat: beat.beat, query: words)
            if result.stockLimited {
                note = T("Stock footage is not available right now. Use one of your own clips, or try again in a few minutes.")
                return
            }
            if let fresh = result.beats?.first(where: { $0.beat == beat.beat }) {
                beat = fresh
            } else {
                await refresh()
            }
            watching = nil
            if beat.candidates?.isEmpty != false {
                note = T("Nothing found. Try simpler words, like one object or place.")
            } else if beat.exhausted == true {
                note = T("No new clips. Try your own words.")
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

    /// Shots can be renumbered by these, so the sheet closes and the list is loaded again.
    private func tool(_ action: String, with other: Int?) async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            _ = try await state.api.shotTool(planId: planId, beat: beat.beat, action: action, withBeat: other)
            Haptics.tap()
            onClose()
        } catch {
            problem = state.report(error)
        }
    }
}
