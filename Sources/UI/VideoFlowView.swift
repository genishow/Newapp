import AVKit
import PhotosUI
import SwiftUI
import UIKit
import UIKit
import UniformTypeIdentifiers

/// A stock clip playing silently on a loop, so a shot can be judged in motion. The box
/// takes the clip's own shape, so there is no blank space around it (Geni, 2026-11-14).
/// Until the first frame plays the clip's picture shows, with a spinner, and a clip that
/// cannot play says so instead of leaving a black box (Geni, 2026-11-15).
struct LoopingPreview: View {
    let url: URL
    var shape: Shape = .landscape
    /// The clip's width ÷ height when known; otherwise the video's shape is used.
    var aspect: Double?
    /// A frame of the clip, shown while it loads.
    var poster: URL?
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var ready = false
    @State private var failed = false

    private var ratio: Double { aspect ?? (shape == .portrait ? 9.0 / 16.0 : 16.0 / 9.0) }

    var body: some View {
        ZStack {
            Theme.grey
            if let poster, !ready {
                AsyncImage(url: poster) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
            }
            if let player, !failed {
                PlayerLayer(player: player).opacity(ready ? 1 : 0)
            }
            if failed {
                PreviewNote(text: T("Preview not available"))
            } else if !ready {
                ProgressView().tint(Theme.black)
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        // A tall clip is kept to a comfortable height; a wide one uses the full width.
        .frame(maxHeight: ratio < 1 ? 440 : nil)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.black, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shotPreview")
        .onAppear {
            let queue = AVQueuePlayer()
            queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            player = queue
            queue.play()
        }
        .task(id: url) {
            // Watch for the first frame, or for the clip failing, for up to 30 seconds.
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                if looper?.status == .failed || player?.currentItem?.status == .failed {
                    failed = true
                    return
                }
                if player?.currentItem?.status == .readyToPlay {
                    ready = true
                    return
                }
            }
            if !ready { failed = true }
        }
        .onDisappear {
            player?.pause()
            player = nil
            looper = nil
        }
    }
}

/// A still picture in the big preview: a spinner while it loads, then the picture, or a
/// short note when it cannot be shown. Never a video player, which drew a black box with
/// bars for a picture (Geni, 2026-11-15).
struct StillPreview: View {
    let url: URL?
    var shape: Shape = .landscape
    var aspect: Double?

    private var ratio: Double { aspect ?? (shape == .portrait ? 9.0 / 16.0 : 16.0 / 9.0) }

    var body: some View {
        ZStack {
            Theme.grey
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        PreviewNote(text: T("Preview not available"))
                    default:
                        ProgressView().tint(Theme.black)
                    }
                }
            } else {
                PreviewNote(text: T("Preview not available"))
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .frame(maxHeight: ratio < 1 ? 440 : nil)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.black, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shotPreview")
    }
}

/// The few words shown in a preview box that has nothing to show.
struct PreviewNote: View {
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "eye.slash").font(.system(size: 20, weight: .medium))
            Text(text).font(Theme.small)
        }
        .foregroundStyle(Theme.muted)
        .padding(12)
    }
}

/// A bare video layer: fills its box, no player chrome and no light background.
struct PlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        view.playerLayer.player = player
    }
}

/// Tells work started from a button whether its screen is still open. A screen that is
/// left and opened again is a new one, and the old one's work must not carry on and pay
/// for a second video.
final class ScreenLife: ObservableObject {
    var gone = false
    var polling = false
    /// True when "Make my video" was tapped on this very screen, with these options.
    var startedOneTap = false
    var stopCheck = false
    /// The plan the quiet footage tools last ran for, and whether they are running now.
    var quietDone: String?
    var quietRunning = false
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
    /// The soundtrack parts the plan made, and the track picked for parts 2 and on.
    @State private var musicSections: [MusicSection] = []
    @State private var laterMusic: [Int: String] = [:]
    /// Off by default, as on the website (Geni, 2026-08-25 and 2026-11-21): captions are
    /// burned in and cannot be taken out after the render, so the customer ticks them.
    @State private var captions = false
    @State private var showSetupOptions = false
    @State private var showPresenter = false
    @State private var avatar = AvatarChoice()
    @State private var audioSec = 0.0
    @State private var starting = false
    /// One-tap mode: plan, fill and render without stopping, when every shot gets footage.
    @State private var auto = false
    @StateObject private var musicPlayer = AudioPlayer()

    @StateObject private var life = ScreenLife()
    @State private var confirmNewList = false
    @State private var checking = false
    /// True while a render request is being sent, so it can never be sent twice.
    @State private var rendering = false
    @State private var render = RenderOptions()
    /// The last shot change that can be undone, as on the website. One step only.
    @State private var lastUndo: ShotUndo?
    @State private var undoing = false
    /// An English voiceover: English captions have two more fonts.
    @State private var english = false
    @State private var shotLength = "auto"
    @State private var breaks = MusicBreaks()
    @State private var showMusicImporter = false
    @State private var logoItem: PhotosPickerItem?
    @State private var hasLogo = false
    @State private var logoBusy = false
    /// What the checks said about each shot, by shot number.
    @State private var flags: [Int: String] = [:]
    @State private var checkNote: String?
    @State private var uploadsLoaded = false
    /// A shape switch: clips picked for the old shape are searched again, not cropped.
    @State private var freshShape = false
    /// Shapes that already have a finished video from this voiceover.
    @State private var madeShapes: Set<String> = []

    /// The website's logo choices: your logo, its corner and its size.
    @ViewBuilder private var logoRows: some View {
        Toggle(T("My logo on the video"), isOn: $render.logo.enabled)
            .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
            .accessibilityIdentifier("logoToggle")
        if render.logo.enabled {
            PhotosPicker(selection: $logoItem, matching: .images) {
                BusyLabel(title: hasLogo ? T("Change logo") : T("Choose logo"), busy: logoBusy)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(logoBusy)
            if hasLogo {
                menuRow(T("Logo corner"),
                        value: T(LogoChoice.corners.first { $0.id == render.logo.corner }?.title ?? "Top right")) {
                    ForEach(LogoChoice.corners, id: \.id) { corner in
                        Button(T(corner.title)) { render.logo.corner = corner.id }
                    }
                }
                Stepper(value: $render.logo.scale, in: 5...30, step: 1) {
                    Text(Tf("Logo size %@%", "\(render.logo.scale)")).font(Theme.body).foregroundStyle(Theme.black)
                }
            } else {
                NoteText(text: T("PNG, JPG or WebP, up to 2 MB."))
            }
        }
    }

    private func uploadLogo(_ item: PhotosPickerItem) async {
        logoBusy = true
        problem = nil
        defer { logoBusy = false }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: raw) else {
                problem = T("That picture could not be opened. Choose another.")
                return
            }
            // The picture is sent as it is when it is small enough. A big one is made
            // smaller first, as PNG so a see-through background is kept.
            var bytes = raw
            var name = "logo.png"
            var mime = "image/png"
            let isPNG = raw.starts(with: [0x89, 0x50, 0x4E, 0x47])
            let isJPEG = raw.starts(with: [0xFF, 0xD8])
            if raw.count <= 2 * 1024 * 1024 && (isPNG || isJPEG) {
                if isJPEG {
                    name = "logo.jpg"
                    mime = "image/jpeg"
                }
            } else {
                let longest = max(image.size.width, image.size.height)
                let scale = min(1, 1024 / max(longest, 1))
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = false
                let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                guard let png = small.pngData(), png.count <= 2 * 1024 * 1024 else {
                    problem = T("That logo is too big. Choose a smaller picture.")
                    return
                }
                bytes = png
            }
            hasLogo = try await state.api.uploadLogo(image: bytes, filename: name, mimeType: mime)
        } catch {
            problem = state.report(error)
        }
    }

    private func uploadMusic(_ url: URL) async {
        problem = nil
        working = T("Adding your music.")
        defer { working = nil }
        let allowed = url.startAccessingSecurityScopedResource()
        defer { if allowed { url.stopAccessingSecurityScopedResource() } }
        do {
            let track = try await state.api.uploadMusic(fileURL: url)
            tracks.removeAll { $0.trackId == track.trackId }
            tracks.insert(track, at: 0)
            musicId = track.trackId
        } catch {
            problem = state.report(error)
        }
    }

    /// The website's whole-plan tools, under the list of shots.
    private var planTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Footage tools")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
            // Placing own clips and the free match check run on their own (Geni,
            // 2026-11-15), so only the paid check is a button.
            // "AI check", the website's name for it too: "Check the shots" meant the paid
            // check here and the free one on the website (Geni, 2026-11-21).
            Button(Tf("AI check · ≈%@ credits", "\(VerifyResult.credits(shots: filledShots.count))")) {
                Task { await paidCheck() }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(filledShots.isEmpty)
            .accessibilityIdentifier("paidCheckButton")
            if let checkNote {
                Text(checkNote).font(Theme.small).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("checkNote")
            }
        }
        .disabled(working != nil || starting)
        .card(fill: Theme.grey, padding: 14)
    }

    private var filledShots: [Beat] { beats.filter { $0.needsFootage && $0.chosen != nil } }

    /// Runs by itself, quietly, once per shot list and again after new clips are added:
    /// own clips go on the shots they match (the old "Place all my clips" button), then the
    /// free check marks shots whose footage may not match the words (the old "Check
    /// footage matches" button). Nothing here blocks the screen or shows an error.
    /// Not enough credits: Buy credits opens on the Account tab, this screen stays as it is.
    private func openBuyCredits() {
        state.selectedTab = 2
        state.pendingAccountRoute = .buyCredits
    }

    private func quietTools(newClips: Bool = false) async {
        guard let planId, stage == .shots, !life.quietRunning, !starting, !rendering else { return }
        if !newClips && life.quietDone == planId { return }
        life.quietRunning = true
        defer { life.quietRunning = false }
        life.quietDone = planId
        // The clip list loads alongside the shots; wait for it (a few seconds at most).
        for _ in 0..<100 where !uploadsLoaded {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        // Placed once for each set of clips, so clips moved by hand are not moved back
        // every time the screen opens.
        let placedKey = "placedclips." + planId
        if !uploads.isEmpty && UserDefaults.standard.integer(forKey: placedKey) < uploads.count {
            if let result = try? await state.api.placeAllClips(planId: planId) {
                UserDefaults.standard.set(uploads.count, forKey: placedKey)
                if life.gone || stage != .shots { return }
                if (result.placed ?? result.matched ?? 0) > 0 { await reloadPlan() }
            }
        }
        if life.gone || stage != .shots || starting || rendering { return }
        await quietCheck(planId: planId)
    }

    /// The free footage-match check, without a busy line or an error card.
    private func quietCheck(planId: String) async {
        guard let submit = try? await state.api.rescanFootage(planId: planId) else { return }
        var tries = 0
        var job = try? await state.api.footageCheck(jobId: submit.jobId)
        while let current = job, current.status != "done", current.status != "failed", tries < 90 {
            if life.gone { return }
            tries += 1
            try? await Task.sleep(nanoseconds: UInt64(Launch.jobPollSeconds * 1_000_000_000))
            job = try? await state.api.footageCheck(jobId: submit.jobId)
        }
        guard let finished = job, finished.status == "done", !life.gone, stage == .shots, !checking else { return }
        let wrong = finished.wrongShots
        for item in wrong where flags[item.beat] == nil {
            flags[item.beat] = T("May not match the words")
        }
        if !wrong.isEmpty && checkNote == nil {
            checkNote = Tf("%@ shots may not match their words. They are marked in the list.", "\(wrong.count)")
        }
    }

    /// The paid check, 30 shots at a time. Wrong footage is replaced by the server.
    private func paidCheck() async {
        guard let planId else { return }
        problem = nil
        checkNote = nil
        let all = filledShots.map(\.beat)
        var flagged = 0
        var replaced = 0
        var done = 0
        flags = [:]
        defer { working = nil }
        do {
            var start = 0
            life.stopCheck = false
            checking = true
            defer { checking = false }
            while start < all.count {
                if life.stopCheck || life.gone { break }
                let chunk = Array(all[start..<min(start + 30, all.count)])
                working = Tf("Checked %@ of %@ shots", "\(done)", "\(all.count)")
                let result = try await state.api.verifyShots(planId: planId, beats: chunk)
                let swapped = Set(result.autoReplaced ?? [])
                replaced += swapped.count
                for check in result.checks ?? [] where !swapped.contains(check.beat) {
                    if check.verdict == "no" || check.verdict == "weak" {
                        flags[check.beat] = check.why.map(APIError.sentenceCase) ?? T("May not match the words")
                        flagged += 1
                    }
                }
                done += chunk.count
                start += 30
            }
            await reloadPlan()
            await state.refresh()
            if flagged == 0 && replaced == 0 {
                checkNote = T("Every shot looks right.")
            } else {
                checkNote = Tf("%@ shots were replaced. %@ are marked for you to look at.", "\(replaced)", "\(flagged)")
            }
        } catch {
            await state.refresh()
            problem = state.report(error)
        }
    }

    /// The website's finishing choices: quality, music loudness, caption font, graphics.
    @ViewBuilder private var renderRows: some View {
        menuRow(T("Quality"), value: render.quality.uppercased()) {
            ForEach(RenderOptions.qualities, id: \.self) { quality in
                // The server makes 8K only for videos up to 7 minutes.
                if quality != "8k" || audioSec <= 420 {
                    Button(quality.uppercased()) { render.quality = quality }
                }
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
                    value: T(RenderOptions.fonts(english: english).first { $0.id == render.captionFont }?.title
                             ?? "Standard")) {
                ForEach(RenderOptions.fonts(english: english), id: \.id) { font in
                    Button(T(font.title)) { render.captionFont = font.id }
                }
            }
        }
        Toggle(T("On-screen graphics"), isOn: $render.graphics)
            .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
        if render.graphics {
            menuRow(T("Graphics colour"),
                    value: T(RenderOptions.colors.first { $0.id == render.graphicsColor }?.title ?? "Gold")) {
                ForEach(RenderOptions.colors, id: \.id) { color in
                    Button(T(color.title)) { render.graphicsColor = color.id }
                }
            }
        }
        logoRows
        if beats.contains(where: { !$0.needsFootage }) {
            Toggle(T("Include the music breaks"), isOn: $render.includeBreaks)
                .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
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
    /// The stock-limit card and the own-footage card each hold the Add my clips button.
    private var addClipsInCard: Bool { !emptyShots.isEmpty && (stockLimited || source == .own) }

    /// The shot before or after this one, skipping music breaks.
    private func neighbour(of beat: Beat, step: Int) -> Int? {
        let shots = beats.filter { $0.needsFootage }
        guard let i = shots.firstIndex(where: { $0.beat == beat.beat }) else { return nil }
        let j = i + step
        return shots.indices.contains(j) ? shots[j].beat : nil
    }
    private var planJobKey: String { "planjob." + jobId }
    /// A video being made for this voiceover, so leaving and coming back finds it again.
    private var videoJobKey: String { "videojob." + jobId }

    /// What the presenter adds to the price. It costs four times more when the photo has
    /// the same shape as the video and fills the frame.
    private var presenterNote: String? {
        guard avatar.enabled else { return nil }
        let seconds = avatar.totalSeconds(audioSec: audioSec)
        guard seconds > 0 else {
            return T("The presenter is on but has no place in the video. Open the presenter and pick one, or turn it off.")
        }
        return nil   // the total is on the button
    }

    /// Credits the presenter adds, 0 when it is off.
    private var presenterCredits: Double {
        guard avatar.enabled else { return 0 }
        return AvatarChoice.credits(seconds: avatar.totalSeconds(audioSec: audioSec), fullFrame: false)
    }

    private var presenterBlocked: Bool {
        avatar.enabled && avatar.totalSeconds(audioSec: audioSec) <= 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                switch stage {
                case .loading:
                    ProgressView().tint(Theme.black)
                case .setup:
                    if videoLocked { lockedCard } else { setup }
                case .planning:
                    planning
                case .shots:
                    shots
                case .video(let id):
                    VideoJobView(videoJobId: id, shape: shape, onEditShots: planId == nil ? nil : {
                        Task {
                            await reloadPlan()
                            stage = .shots
                            await loadMadeShapes()
                        }
                    })
                }
            }
            .page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable {
            if stage == .shots { await reloadPlan() }
        }
        .onAppear {
            life.gone = false
            // Back on the shots: show what the server has now, without leaving and returning.
            if stage == .shots { Task { await reloadPlan() } }
            // Back on this screen while a plan is still being made: keep checking on it.
            if stage == .planning { Task { await resumePlanning() } }
        }
        .onDisappear {
            life.gone = true
            musicPlayer.stop()
        }
        .safeAreaInset(edge: .bottom) {
            if stage == .setup && !videoLocked {
                BottomBar(problem: problem) { setupBar }
            }
        }
        .fileImporter(isPresented: $showMusicImporter, allowedContentTypes: [.mp3, .mpeg4Audio, .wav]) { result in
            if case .success(let url) = result { Task { await uploadMusic(url) } }
        }
        .onChange(of: logoItem) { _, item in
            if let item { Task { await uploadLogo(item) } }
        }
        .onChange(of: render.logo.enabled) { _, on in
            if on { Task { hasLogo = (try? await state.api.hasLogo()) ?? hasLogo } }
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
        // However the sheet is closed, the list is loaded again: a shot's length can
        // change the times of the shots after it.
        .sheet(item: $picking, onDismiss: { Task { await reloadPlan() } }) { beat in
            ShotSheet(planId: planId ?? "", jobId: jobId, beat: beat, uploads: uploads, shape: shape,
                      previous: neighbour(of: beat, step: -1), next: neighbour(of: beat, step: 1),
                      onUndoable: { lastUndo = $0 }) {
                picking = nil
            }
            .environmentObject(state)
        }
    }

    // MARK: setup

    /// Making a video is not part of the free credits (Geni, 2026-11-18). A video
    /// already started stays open: only starting a new one is locked.
    private var videoLocked: Bool { state.me?.videoOpen == false }

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("Make a video")).screenTitle(amharic: A("Make a video"))
                .accessibilityIdentifier("videoLockedHeading")
            VStack(alignment: .leading, spacing: 12) {
                Text(T("Video making opens with a plan"))
                    .font(Theme.heading).foregroundStyle(Theme.black)
                // No "in your own voice" where cloning is closed for this account.
                Text(state.me?.cloneOpen == false
                     ? T("Your free credits are for voiceovers. Kinbir turns this voiceover into a finished video with footage, captions and music once you have a plan, or free credits you earned.")
                     : T("Your free credits are for voiceovers in your own voice. Kinbir turns this voiceover into a finished video with footage, captions and music once you have a plan, or free credits you earned."))
                    .font(Theme.body).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(fill: Theme.lime)
            Button(T("See plans")) {
                state.selectedTab = 2
                state.pendingAccountRoute = .buyCredits
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("lockedPlansButton")
            Button(T("Earn free credits with a video about Kinbir")) {
                state.selectedTab = 2
                state.pendingAccountRoute = .promo
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("lockedEarnButton")
            NoteText(text: T("Post a short video about Kinbir. When it is approved you get free credits, and video making opens."))
            // A failed load must not hide behind the locked card.
            if let problem {
                ProblemCard(message: problem, buy: openBuyCredits)
            }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(T("Make a video")).screenTitle(amharic: A("Make a video"))
                .accessibilityIdentifier("videoSetupHeading")

            // The two choices that decide the shots, made before they are planned
            // (Geni: footage and shape belong together, before the shots exist).
            stepLabel("1", T("Where will it be watched?"))
            HStack(spacing: 12) {
                shapeTile(.portrait, title: T("Vertical"), detail: "TikTok · Reels · Shorts")
                shapeTile(.landscape, title: T("Horizontal"), detail: "YouTube")
            }

            stepLabel("2", T("What footage?"))
            HStack(spacing: 10) {
                sourceTile(.stock, icon: "film", title: T("Stock"))
                sourceTile(.mix, icon: "square.stack", title: T("Stock + mine"))
                // "Only mine" is gone, as on the website (Geni, 2026-11-20 and
                // 2026-11-21). An older plan made that way still opens as it was.
            }
            NoteText(text: sourceNote)
            if source != .stock {
                clipsCard
            }

            // Four choices only (Geni, 2026-11-16: shape, footage, shot length,
            // music). Everything else is on the shots page, once.
            stepLabel("3", T("Shot length"))
            menuRow(T("Shot length"),
                    value: T(RenderOptions.shotLengths.first { $0.id == shotLength }?.title ?? "Same as before")) {
                ForEach(RenderOptions.shotLengths, id: \.id) { item in
                    Button(T(item.title)) { shotLength = item.id }
                }
            }
            .accessibilityIdentifier("shotLengthMenu")

            stepLabel("4", T("Music"))
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
                .accessibilityIdentifier("setupMusicPicker")
            }
            // Music breaks, as on the website: a few seconds of music with no voice.
            menuRow(T("Music breaks"),
                    value: T(MusicBreaks.choices.first { $0.id == breaks.choice }?.title ?? "None")) {
                ForEach(MusicBreaks.choices, id: \.id) { item in
                    Button(T(item.title)) { breaks.choice = item.id }
                }
            }
            .accessibilityIdentifier("breaksMenu")
            NoteText(text: T("A few seconds of music with no voice, spread through the video."))
        }
    }

    private func stepLabel(_ number: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text(number).font(Theme.smallMedium).foregroundStyle(Theme.black)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.lime))
                .overlay(Circle().strokeBorder(Theme.black, lineWidth: 1))
            Text(title).font(Theme.bodyMedium).foregroundStyle(Theme.black)
        }
        .padding(.top, 4)
    }

    /// Where the footage comes from, picked with the shape before the shots are planned.
    private func sourceTile(_ value: FootageSource, icon: String, title: String) -> some View {
        let selected = source == value
        return Button {
            Haptics.tap()
            source = value
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(title).font(Theme.smallMedium).multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.black)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(selected ? Theme.lime : Theme.grey))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.black, lineWidth: selected ? 1.5 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("source-" + value.rawValue)
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

    /// The setup screen's one main button: plan the shots, with what planning costs.
    /// One-tap "Make my video" is gone, as on the website (Geni, 2026-11-20 and
    /// 2026-11-21): the customer always sees the shots before paying for the render.
    private var setupTitle: String {
        guard let estimate else { return T("See the shots") }
        return T("See the shots") + " · ≈ " + Fmt.credits(estimate) + " " + T("credits")
    }

    @ViewBuilder private var setupBar: some View {
        Button {
            auto = false
            Task { await startPlan() }
        } label: {
            BusyLabel(title: setupTitle, busy: starting)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(starting || working != nil || presenterBlocked)
        .accessibilityIdentifier("planButton")
        if let presenterNote {
            Text(presenterNote).font(Theme.small).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            NoteText(text: T("Each clip can be up to 10 minutes. Only the part used in your video is kept in the video."))
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
                ProblemCard(message: problem, buy: openBuyCredits)
                Button(T("Check again")) {
                    self.problem = nil
                    Task { await resumePlanning() }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: shots

    /// Vertical or horizontal for the next video, from the same shots (Geni,
    /// 2026-11-15: after a vertical video, Make video went straight back to the
    /// vertical shots with no way to get a horizontal one). Switching is free:
    /// the server finds stock footage again in the new shape and keeps every
    /// shot picked by hand and every own clip.
    private var shapeSwitch: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                shapeChip(.portrait, title: T("Vertical"))
                shapeChip(.landscape, title: T("Horizontal"))
                Spacer(minLength: 0)
                Text(T(source.title)).font(Theme.small).foregroundStyle(Theme.muted)
            }
            if let made = madeNote {
                Text(made).font(Theme.small).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("shapeMadeNote")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shotsSummary")
    }

    /// Says which shapes already have a video, so the next choice is clear.
    private var madeNote: String? {
        let vertical = madeShapes.contains(Shape.portrait.rawValue)
        let horizontal = madeShapes.contains(Shape.landscape.rawValue)
        if vertical && horizontal {
            return T("You have both shapes already.")
        }
        if vertical {
            return shape == .portrait
                ? T("You have a vertical video. Tap Horizontal for the other shape.")
                : nil
        }
        if horizontal {
            return shape == .landscape
                ? T("You have a horizontal video. Tap Vertical for the other shape.")
                : nil
        }
        return nil
    }

    private func shapeChip(_ value: Shape, title: String) -> some View {
        let selected = shape == value
        return Button {
            Task { await switchShape(to: value) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: value == .portrait ? "rectangle.portrait" : "rectangle")
                Text(title).font(Theme.smallMedium)
            }
            .foregroundStyle(Theme.black)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(selected ? Theme.lime : Theme.grey))
            .overlay(Capsule().strokeBorder(Theme.black, lineWidth: selected ? 1.5 : 0))
        }
        .buttonStyle(.plain)
        .disabled(working != nil || starting || rendering)
        .accessibilityIdentifier("switchShape-" + value.rawValue)
    }

    private func switchShape(to value: Shape) async {
        guard value != shape, working == nil, !starting, !rendering, planId != nil else { return }
        Haptics.tap()
        let before = shape
        shape = value
        flags = [:]
        if source == .own, let planId {
            // Own clips only: no stock to find, but the server must still
            // record the new shape before the video can be made in it.
            working = T("Changing the shape.")
            _ = try? await state.api.searchFootage(planId: planId, shape: value, beat: nil, query: nil)
            await reloadPlan()
            working = nil
        } else {
            freshShape = true
            await fillShots(stock: true, own: false)
            freshShape = false
        }
        if shape != value {
            // The server kept the old shape (reloadPlan read it back).
            shape = before
            if problem == nil {
                problem = T("The shape could not be changed right now. Try again in a moment.")
            }
        }
    }

    private func loadMadeShapes() async {
        let list = (try? await state.api.videos()) ?? []
        madeShapes = Set(list.filter { $0.jobId == jobId }.compactMap(\.orientation))
    }

    private var shots: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("Your shots")).screenTitle(amharic: A("Your shots"))
                .accessibilityIdentifier("shotsHeading")
            if let lastUndo {
                Button {
                    Task { await undo(lastUndo) }
                } label: {
                    BusyLabel(title: "↶ " + T(lastUndo.label), busy: undoing)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(undoing || working != nil)
                .accessibilityIdentifier("shotUndoButton")
            }
            shapeSwitch

            if source != .stock && !beats.isEmpty {
                clipGuide
            }

            if stockLimited && !emptyShots.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(T("Stock footage is not available right now"))
                        .font(Theme.heading).foregroundStyle(Theme.black)
                    Text(T("The free stock library has reached its limit. Upload your own footage for the empty shots, or try stock again in a few minutes."))
                        .font(Theme.body).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                    if working == nil {
                        addClipsButton
                    }
                    Button(T("Try stock again")) { Task { await fillShots(stock: true, own: false) } }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(working != nil)
                }
                .card(fill: Theme.lime)
                // Contained, so the buttons inside keep their own names for the tests.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("stockLimitCard")
            } else if source == .own && !emptyShots.isEmpty && working == nil {
                // Only their own footage: nothing to search, so say what to do instead.
                VStack(alignment: .leading, spacing: 10) {
                    Text(Tf("%@ shots need footage", "\(emptyShots.count)"))
                        .font(Theme.bodyMedium).foregroundStyle(Theme.black)
                    Text(T("Tap a shot to add your own clip, or add several clips at once."))
                        .font(Theme.body).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                    addClipsButton
                    Button(T("Use stock for the empty shots")) { Task { await useStockForEmpty() } }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("useStockButton")
                }
                .card(fill: Theme.grey, padding: 14)
                // Contained, so the buttons inside keep their own names for the tests.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ownEmptyCard")
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
                    Spacer(minLength: 0)
                    if checking {
                        // The paid check runs 30 shots at a time. Stop ends it after the
                        // group being checked; what is already checked is kept.
                        Button(T("Stop")) { life.stopCheck = true }
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityIdentifier("stopCheckButton")
                    }
                }
                .card(fill: Theme.grey, padding: 14)
            }

            // Shown here too, so a message is seen next to where the tap was.
            if let problem {
                ProblemCard(message: problem, buy: openBuyCredits)
            }

            if !beats.isEmpty {
                Text(T("Tap any shot to change its clip, use your own, or move it."))
                    .font(Theme.small).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("shotsHint")
            }
            // Lazy: only the shots on screen are drawn and their pictures loaded.
            LazyVStack(alignment: .leading, spacing: Theme.gap) {
            ForEach(beats.filter { $0.needsFootage }) { beat in
                Button {
                    picking = beat
                } label: {
                    ShotRow(beat: beat, shape: shape, flag: flags[beat.beat])
                }
                .buttonStyle(.plain)
                .disabled(working != nil)
                .accessibilityIdentifier("shotRow-\(beat.beat)")
            }
            }

            // Not twice: the cards above already carry this button when shots are empty.
            if working == nil && !addClipsInCard {
                addClipsButton
            }

            if working == nil {
                planTools
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
                ProblemCard(message: problem, buy: openBuyCredits)
            }

            Button {
                Task { await makeVideo() }
            } label: {
                BusyLabel(title: Tf("Make video · %@ credits", Fmt.credits(render.credits(durationSec: audioSec) + presenterCredits)),
                          busy: starting)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(starting || working != nil || !emptyShots.isEmpty || presenterBlocked)
            .accessibilityIdentifier("makeVideoButton")

            if let presenterNote {
                Text(presenterNote).font(Theme.small).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("presenterCostNote")
            }

            if !emptyShots.isEmpty {
                NoteText(text: T("Every shot needs footage before the video can be made."))
            }

            // Not offered while video making is locked: a new list could not be planned.
            if !videoLocked {
            Button(T("Change footage · new shot list")) { confirmNewList = true }
            .confirmationDialog(T("Start a new shot list?"), isPresented: $confirmNewList,
                                titleVisibility: .visible) {
                Button(T("Plan the shots again")) {
                    planId = nil
                    beats = []
                    flags = [:]
                    stage = .setup
                    Task { estimate = try? await state.api.footageEstimate(script: script) }
                }
                Button(T("Keep this list"), role: .cancel) {}
            } message: {
                Text(T("Planning again costs credits, and the clips you picked for this list are not kept."))
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(starting || working != nil)
            .accessibilityIdentifier("newShotListButton")
            }
        }
    }

    /// How many own clips to add, and how long, for this shot list (Geni, 2026-11-15).
    private var clipGuide: some View {
        let count = beats.filter { $0.needsFootage }.count
        let seconds = audioSec > 0 ? audioSec : (beats.compactMap(\.end).max() ?? 0)
        let range = ClipRules.suggestedClips(shots: count)
        // One short line (Geni: keep the app simple, no long explanations).
        return Text(Tf("%@ shots · %@ sec · add %@ to %@ clips", "\(count)",
                       "\(Int(seconds.rounded()))", "\(range.low)", "\(range.high)"))
            .font(Theme.small).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clipGuide")
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
            // A plan with two or more music parts: each part can have its own track,
            // as on the website. A part left alone keeps the track before it.
            if musicId != nil && musicSections.count >= 2 {
                ForEach(1..<musicSections.count, id: \.self) { part in
                    HStack {
                        Text(Tf("Part %@", "\(part + 1)") + partTime(part))
                            .font(Theme.body).foregroundStyle(Theme.black)
                        Spacer()
                        Picker(T("Music"), selection: Binding(
                            get: { laterMusic[part] },
                            set: { laterMusic[part] = $0 })) {
                            Text(T("Same as before")).tag(String?.none)
                            ForEach(tracks) { track in
                                Text(track.title ?? T("Track")).tag(String?.some(track.trackId))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.black)
                    }
                    .accessibilityIdentifier("partMusic-\(part + 1)")
                }
            }
            if musicId != nil && hasBreaks && render.includeBreaks {
                HStack {
                    Text(T("Break sound")).font(Theme.body).foregroundStyle(Theme.black)
                    Spacer()
                    Picker(T("Break sound"), selection: $render.sfxId) {
                        Text(T("No sound")).tag(String?.none)
                        ForEach(tracks) { track in
                            Text(track.title ?? T("Track")).tag(String?.some(track.trackId))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.black)
                    .accessibilityIdentifier("breakSoundPicker")
                }
                NoteText(text: T("A short sound at each music break."))
            }
            HStack(spacing: 20) {
                if musicId != nil {
                    Button(musicPlayer.isPlaying ? T("Stop preview") : T("Listen")) {
                        Task { await toggleMusic() }
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                Button(T("Upload my own music")) { showMusicImporter = true }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("uploadMusicButton")
            }
            Toggle(T("Captions on the video"), isOn: $captions)
                .font(Theme.body).foregroundStyle(Theme.black)
                .tint(Theme.black)
            // D-448: the planner works out the cut - camera moves, soft entries and
            // the caption words to stress - and the server carries it out.
            Toggle(isOn: $render.smartEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(T("Smart edit")).font(Theme.body).foregroundStyle(Theme.black)
                    Text(T("Kinbir's AI adds camera moves, smooth scene changes and highlights key words."))
                        .font(Theme.small).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.black)
            .accessibilityIdentifier("smartEditToggle")
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
            english = job.language == "en"
            // Display and Typewriter are English-only fonts.
            if !english && !RenderOptions.fonts.contains(where: { $0.id == render.captionFont }) {
                render.captionFont = "standard"
            }
            // Clips and music are not needed to show the shots, so they load
            // alongside, not before (Geni, 2026-11-15: making the other shape
            // took long to open).
            Task {
                async let clipList = try? state.api.uploads(jobId: jobId)
                async let musicList = try? state.api.music()
                uploads = await clipList ?? uploads
                uploadsLoaded = true
                tracks = await musicList ?? []
                // No music is chosen for the customer: they pick a track if they want one,
                // as on the website (Geni, 2026-11-21).
            }
            if let running = UserDefaults.standard.string(forKey: videoJobKey) {
                // A video was started for this voiceover. If it is still being made, show
                // it, so it is never started (and paid for) a second time.
                if let status = try? await state.api.assembleStatus(id: running), !status.isOver {
                    planId = job.brollPlanId
                    if planId != nil { await reloadPlan() }
                    stage = .video(running)
                    return
                }
                UserDefaults.standard.removeObject(forKey: videoJobKey)
            }
            if let existing = job.brollPlanId {
                planId = existing
                await reloadPlan()
                stage = .shots
                Task { await loadMadeShapes() }
                Task { await quietTools() }
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
                                                         shotLength: shotLength, breaks: breaks)
            // Saved at once: planning is paid for, so it must never be submitted twice.
            UserDefaults.standard.set(submit.jobId, forKey: planJobKey)
            UserDefaults.standard.set(auto, forKey: planJobKey + ".auto")
            life.startedOneTap = auto
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
        // Only one check at a time, and none from a screen that has been left.
        guard !life.polling else { return }
        life.polling = true
        defer { life.polling = false }
        var misses = 0
        while !Task.isCancelled {
            if life.gone { return }
            do {
                let latest = try await state.api.planJob(id: planJob)
                misses = 0
                if latest.status == "done", let id = latest.result?.planId {
                    planId = id
                    beats = latest.result?.beats ?? []
                    musicSections = latest.result?.musicSections ?? []
                    UserDefaults.standard.removeObject(forKey: planJobKey)
                    await state.refresh()
                    await fillShots(stock: source != .own, own: source != .stock)
                    stage = .shots
                    // The one-tap token is used up before the video is started, so it can
                    // never start two.
                    let oneTap = auto
                    auto = false
                    UserDefaults.standard.removeObject(forKey: planJobKey + ".auto")
                    if oneTap && !life.startedOneTap {
                        // This screen was reopened, so the options chosen before are gone.
                        problem = T("Your shots are ready. Check the options below, then tap Make video.")
                    } else if oneTap && emptyShots.isEmpty && !beats.isEmpty && !life.gone {
                        await makeVideo()
                    } else if oneTap {
                        problem = T("Some shots have no footage yet, so the video was not made. Add footage to them, then tap Make video.")
                    }
                    auto = false
                    UserDefaults.standard.removeObject(forKey: planJobKey + ".auto")
                    if stage == .shots { Task { await quietTools() } }
                    return
                }
                // "done" with no shot list is a failure too; asking again would never end.
                if latest.status == "failed" || latest.status == "done" {
                    UserDefaults.standard.removeObject(forKey: planJobKey)
                    problem = latest.error.map(APIError.sentenceCase)
                        ?? "The plan could not be made. Your credits were returned."
                    stage = .setup
                    return
                }
            } catch {
                if Task.isCancelled { return }
                let wrapped = APIError.wrap(error)
                if wrapped.status == 404 {
                    // The plan job is gone (it expires). Start again instead of asking forever.
                    UserDefaults.standard.removeObject(forKey: planJobKey)
                    UserDefaults.standard.removeObject(forKey: planJobKey + ".auto")
                    problem = T("That shot list could not be found any more. Plan the shots again.")
                    stage = .setup
                    estimate = try? await state.api.footageEstimate(script: script)
                    return
                }
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
                                                                  beat: nil, query: nil,
                                                                  freshShape: freshShape)
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
        // Own footage only: no stock is on its way, so there is nothing to wait for.
        if stock { await settle() }
        working = nil
    }

    /// The server can still be placing footage when the search answers, which left shots
    /// looking empty until the screen was opened again (Geni, 2026-11-14). Look again a few
    /// times while shots are empty, stopping as soon as nothing more arrives.
    private func settle() async {
        guard !stockLimited else { return }
        var lastEmpty = emptyShots.count
        var still = 0
        for _ in 0..<10 where !emptyShots.isEmpty && !life.gone {
            try? await Task.sleep(nanoseconds: UInt64((Launch.isMock ? 0.2 : 3) * 1_000_000_000))
            await reloadPlan()
            if emptyShots.count < lastEmpty {
                lastEmpty = emptyShots.count
                still = 0
            } else {
                still += 1
                if still >= 3 { break }
            }
        }
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
            guard let fillJob = submit.jobId else {
                // Nothing to search, for example on an "Only mine" plan. Say why.
                checkNote = submit.note.map(APIError.sentenceCase)
                    ?? T("There is nothing to search for these shots. Add your own clips, or change Footage to Stock.")
                return
            }
            for _ in 0..<90 {
                if life.gone { return }
                let job = try await state.api.planJob(id: fillJob)
                if job.status == "done" { break }
                if job.status == "failed" {
                    problem = job.error.map(APIError.sentenceCase) ?? T("No footage was found. Try your own words on each shot.")
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(Launch.jobPollSeconds * 1_000_000_000))
            }
            await reloadPlan()
            await preferRightShape()
            await settle()
        } catch {
            problem = state.report(error)
        }
    }

    /// An "Only mine" list lets stock in for the shots that are still empty. Clips
    /// already placed stay where they are.
    private func useStockForEmpty() async {
        guard let planId, working == nil else { return }
        problem = nil
        // Marked busy at once, so a second tap cannot start a second search.
        working = T("Finding footage for your shots.")
        do {
            try await state.api.changeSource(planId: planId, source: .mix)
            source = .mix
        } catch {
            working = nil
            problem = state.report(error)
            return
        }
        await fillShots(stock: true, own: false)
    }

    /// Puts the last shot change back, then forgets it: the numbers it remembers may not
    /// be true after another change.
    private func undo(_ step: ShotUndo) async {
        guard let planId, !undoing else { return }
        undoing = true
        problem = nil
        defer { undoing = false }
        do {
            if step.action == "length", let seconds = step.seconds {
                _ = try await state.api.shotLength(planId: planId, beat: step.beat, seconds: seconds)
            } else {
                _ = try await state.api.shotTool(planId: planId, beat: step.beat, action: step.action,
                                                 withBeat: step.withBeat)
            }
            lastUndo = nil
            Haptics.success()
            await reloadPlan()
        } catch {
            problem = state.report(error)
        }
    }

    /// The plan has music breaks (shots with no footage, only music).
    private var hasBreaks: Bool { beats.contains { !$0.needsFootage } }

    /// " (0:40 to 1:20)" for a music part, or nothing when the times are not known.
    private func partTime(_ part: Int) -> String {
        guard musicSections.indices.contains(part), let start = musicSections[part].startSec,
              let end = musicSections[part].endSec else { return "" }
        return " (" + Fmt.clock(start) + " " + T("to") + " " + Fmt.clock(end) + ")"
    }

    private func reloadPlan() async {
        guard let planId else { return }
        do {
            let stored = try await state.api.plan(id: planId)
            beats = stored.beats ?? beats
            musicSections = stored.musicSections ?? []
            if let raw = stored.orientation, let saved = Shape(rawValue: raw) { shape = saved }
            if let raw = stored.source, let saved = FootageSource(rawValue: raw) { source = saved }
        } catch {
            problem = state.report(error)
        }
    }

    private func addClips(_ picked: [URL]) async {
        problem = nil
        var done = 0
        // A video longer than 10 minutes is not sent (the server refuses it too).
        var urls: [URL] = []
        var tooLong = 0
        for url in picked {
            if let seconds = await ClipLength.seconds(of: url), ClipRules.isTooLong(seconds: seconds) {
                tooLong += 1
            } else {
                urls.append(url)
            }
        }
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
        if tooLong > 0 && problem == nil {
            problem = ClipLength.tooLongMessage(count: tooLong)
        }
        working = nil
        // With a plan already made, new clips go straight onto the shots, then onto the
        // shots they match best, and the shots are checked again.
        if planId != nil && done > 0 {
            await fillShots(stock: false, own: true)
            await quietTools(newClips: true)
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
        // Not `starting`: one-tap mode calls this while the plan button's own work is
        // still running, and that must not stop the video from being made.
        guard let planId, !rendering else { return }
        rendering = true
        defer { rendering = false }
        starting = true
        problem = nil
        musicPlayer.stop()
        defer { starting = false }
        do {
            var picks: [String?] = [musicId]
            for part in 1..<max(1, musicSections.count) { picks.append(laterMusic[part]) }
            render.musicIds = musicId == nil ? [] : RenderOptions.musicArc(parts: musicSections.count, picks: picks)
            if musicId == nil || !hasBreaks { render.sfxId = nil }
            let submit = try await state.api.assemble(planId: planId, shape: shape,
                                                      musicId: musicId, captions: captions,
                                                      avatar: avatar.enabled ? avatar : nil,
                                                      options: render)
            UserDefaults.standard.set(submit.jobId, forKey: videoJobKey)
            await state.refresh()
            stage = .video(submit.jobId)
        } catch {
            problem = state.report(error)
        }
    }
}

/// How long a picked video is, read on the phone before it is uploaded.
enum ClipLength {
    static let videoEndings: Set<String> = ["mp4", "mov", "m4v", "webm"]

    /// Seconds, or nil for a picture or a file that cannot be read.
    static func seconds(of url: URL) async -> Double? {
        guard videoEndings.contains(url.pathExtension.lowercased()) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let time = try? await asset.load(.duration), time.isNumeric else { return nil }
        let value = CMTimeGetSeconds(time)
        return value.isFinite && value > 0 ? value : nil
    }

    static func tooLongMessage(count: Int) -> String {
        let start = count == 1 ? T("This video is longer than 10 minutes, so it was not added.")
                               : Tf("%@ videos are longer than 10 minutes, so they were not added.", "\(count)")
        return start + " " + T("A clip can be at most 10 minutes. Trim it in Photos and add it again. Only the part used in your video is kept in the video.")
    }
}

/// One shot in the list: its picture, its place in the video, the words it covers.
struct ShotRow: View {
    let beat: Beat
    var shape: Shape = .portrait
    /// What a check said is wrong with this shot, if anything.
    var flag: String?

    /// "Add footage", or "Change · 4 more" when other clips were found for it.
    private var changeLabel: String {
        if beat.isEmpty { return T("Add footage") }
        let more = max(0, (beat.candidates?.count ?? 0) - 1)
        return more > 0 ? Tf("Change · %@ more", "\(more)") : T("Change")
    }

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
                if let flag {
                    Text("! " + flag).font(Theme.smallMedium).foregroundStyle(Theme.black)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                // Says plainly that the shot can be changed, and how many other
                // clips are waiting (Geni, 2026-11-16).
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .bold))
                    Text(changeLabel).font(Theme.font(12, .bold, relativeTo: .caption))
                }
                .foregroundStyle(Theme.black)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Theme.lime))
                .overlay(Capsule().strokeBorder(Theme.black, lineWidth: 1))
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .card(fill: beat.isEmpty ? Theme.grey : Theme.white, padding: 12)
    }
}

/// A clip's picture, cropped to fill the frame it is given. Own clips get theirs from
/// the Kinbir server; a clip with no picture at all shows a film mark.
struct ClipThumb: View {
    let candidate: Candidate?

    var body: some View {
        // The picture is an overlay of a box with a fixed size, so a wide picture is cropped
        // to the box instead of spilling out of it.
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.grey)
            .overlay {
                if let url = candidate?.posterURL ?? (candidate?.isStill == true ? candidate?.previewURL : nil) {
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
    /// The voiceover, which own uploads belong to.
    var jobId: String = ""
    @State var beat: Beat
    let uploads: [UploadMeta]
    var shape: Shape = .portrait
    /// The shots before and after this one, for Move earlier / Move later.
    var previous: Int?
    var next: Int?
    /// Tells the shot list what the last change was, so it can be undone there.
    var onUndoable: (ShotUndo?) -> Void = { _ in }
    let onClose: () -> Void

    /// The new length asked for this shot, any shot (the website's "length").
    @State private var newLength: Double = 0
    @State private var settingLength = false
    @State private var aiBusy = false
    @State private var promptCopied = false

    @State private var query = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var note: String?
    /// The clip being watched. It is only used when "Use this clip" is tapped.
    @State private var watching: Candidate?
    @State private var showUpload = false
    @State private var uploading: String?
    /// How many seconds the user's own clip should play on this shot.
    @State private var playFor: Double = 0
    @State private var stretching = false
    @State private var stretchNote: String?

    /// How long this shot is on screen.
    private var length: Double? {
        if let dur = beat.dur, dur > 0 { return dur }
        if let start = beat.start, let end = beat.end, end > start { return end - start }
        return nil
    }

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
                        ProblemCard(message: problem, buy: openBuyCredits)
                    }

                    if let shown {
                        // A picture is shown as a picture; a clip plays. Never an empty box.
                        if shown.isStill {
                            StillPreview(url: shown.previewURL ?? shown.posterURL, shape: shape,
                                         aspect: shown.aspectRatio)
                                .id("still-\(shown.clipId)")
                        } else if let url = shown.previewURL {
                            LoopingPreview(url: url, shape: shape, aspect: shown.aspectRatio,
                                           poster: shown.posterURL)
                                .id(url.absoluteString)
                        } else {
                            StillPreview(url: shown.posterURL, shape: shape, aspect: shown.aspectRatio)
                                .id("poster-\(shown.clipId)")
                        }
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

                    uploadCard

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
                    if beat.needsFootage {
                        aiShotCard
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
        .sheet(isPresented: $showUpload) {
            ClipPicker(limit: 1) { urls in
                showUpload = false
                if let url = urls.first { Task { await uploadForShot(url) } }
            }
        }
    }

    /// Put a photo or a video of your own on just this shot, knowing how long it must be.
    private var uploadCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Use your own photo or video")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
            if let length {
                NoteText(text: Tf("This shot is on screen for %@ seconds. A longer video is cut to fit, a shorter one repeats, and a photo stays on screen for the whole shot.",
                                  String(format: "%.1f", length)))
                    .accessibilityIdentifier("shotLengthNote")
            }
            if let length, beat.chosen?.isOwn == true, next != nil, (beat.type ?? "talk") == "talk" {
                stretchRow(length: length)
            }
            if let uploading {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.black)
                    Text(uploading).font(Theme.small).foregroundStyle(Theme.black)
                }
            } else if Launch.isMock {
                Button(T("Add sample clip to this shot")) {
                    Task { await uploadForShot(FileManager.default.temporaryDirectory.appendingPathComponent("sample.mov")) }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(busy)
                .accessibilityIdentifier("shotUploadSample")
            } else {
                Button {
                    showUpload = true
                } label: {
                    Label(T("Upload a photo or video"), systemImage: "photo.on.rectangle")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(busy || jobId.isEmpty)
                .accessibilityIdentifier("shotUploadButton")
            }
            NoteText(text: T("Only use footage you filmed or have permission to use."))
        }
        .card(fill: Theme.grey, padding: 14)
    }

    /// The longest this shot's own clip can be asked to play: the clip's own length for a
    /// video, so it never has to repeat, and never under the shot's length now.
    private func longestPlay(_ length: Double) -> Double {
        var top = 30.0
        if let clip = beat.chosen, !clip.isStill, let duration = clip.duration, duration > 0.5 {
            top = min(top, duration)
        }
        return max(top, length, ClipRules.minShotSeconds + 0.5)
    }

    /// Set how long your own clip plays here. The next shots give or take the time.
    private func stretchRow(length: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: $playFor, in: ClipRules.minShotSeconds...longestPlay(length), step: 0.5) {
                Text(Tf("Your clip plays for %@ seconds", String(format: "%.1f", playFor)))
                    .font(Theme.bodyMedium).foregroundStyle(Theme.black)
            }
            .accessibilityIdentifier("shotPlayForStepper")
            Button {
                Task { await stretch() }
            } label: {
                BusyLabel(title: T("Set this length"), busy: stretching)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(busy || abs(playFor - length) < 0.05)
            .accessibilityIdentifier("shotPlayForButton")
            if let stretchNote {
                Text(stretchNote).font(Theme.small).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("shotPlayForNote")
            }
            NoteText(text: T("When this shot gets longer, the next shots get shorter by the same time, so your video still matches your voice. No shot gets shorter than 1.5 seconds."))
        }
        .onAppear { if playFor == 0 { playFor = length } }
    }

    private func stretch() async {
        problem = nil
        stretchNote = nil
        busy = true
        stretching = true
        defer { busy = false; stretching = false }
        do {
            let result = try await state.api.stretchShot(planId: planId, beat: beat.beat, seconds: playFor)
            if let fresh = result.beats?.first(where: { $0.beat == beat.beat }) {
                beat = fresh
            } else {
                await refresh()
            }
            if let got = result.durSec { playFor = got }
            Haptics.success()
            stretchNote = result.note.map(APIError.sentenceCase) ?? T("Done. The shot length is set.")
        } catch {
            problem = state.report(error)
        }
    }

    private func uploadForShot(_ url: URL) async {
        guard !jobId.isEmpty else { return }
        problem = nil
        if let seconds = await ClipLength.seconds(of: url), ClipRules.isTooLong(seconds: seconds) {
            problem = ClipLength.tooLongMessage(count: 1)
            return
        }
        busy = true
        uploading = T("Uploading")
        defer { busy = false; uploading = nil }
        do {
            let meta = try await state.api.uploadClip(fileURL: url, jobId: jobId) { fraction in
                uploading = T("Uploading") + " · \(Int(fraction * 100))%"
            }
            uploading = T("Putting it on this shot")
            _ = try await state.api.useUpload(planId: planId, beat: beat.beat, uploadId: meta.uploadId)
            Haptics.success()
            if let length, let duration = meta.duration, meta.kind != "still", duration > length + 0.3 {
                note = Tf("Your video is %@ seconds, so it is cut to this shot's %@ seconds.",
                          String(format: "%.1f", duration), String(format: "%.1f", length))
            } else if let length, let duration = meta.duration, meta.kind != "still", duration + 0.3 < length {
                note = Tf("Your video is %@ seconds, shorter than this %@-second shot, so it plays again to fill it. A clip at least as long looks better.",
                          String(format: "%.1f", duration), String(format: "%.1f", length))
            }
            if note == nil {
                note = T("Done. Your own footage is on this shot.")
            }
            await refresh()
        } catch {
            problem = state.report(error)
        }
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
            // Any shot's length, as on the website. Your own clip has its own control above.
            if let length, beat.chosen?.isOwn != true, (beat.type ?? "talk") == "talk" {
                Stepper(value: $newLength, in: 1...30, step: 0.5) {
                    Text(Tf("Shot length: %@ seconds", String(format: "%.1f", newLength)))
                        .font(Theme.body).foregroundStyle(Theme.black)
                }
                .accessibilityIdentifier("shotLengthStepper")
                .onAppear { if newLength == 0 { newLength = (length * 2).rounded() / 2 } }
                Button {
                    Task { await setLength(from: length) }
                } label: {
                    BusyLabel(title: T("Set this length"), busy: settingLength)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(busy || abs(newLength - length) < 0.05)
                .accessibilityIdentifier("shotLengthButton")
            }
        }
        .accessibilityIdentifier("shotTools")
    }

    /// Make this shot with AI, as on the website. The prompt can also be copied and used
    /// in any AI video tool, then added here as your own clip.
    private var aiShotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Make this shot with AI")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
            NoteText(text: T("When no clip fits, Kinbir can make this shot for you. It takes about a minute and becomes the chosen clip. The other clips stay underneath."))
            Button {
                Task { await makeAiShot() }
            } label: {
                BusyLabel(title: aiBusy ? T("Making this shot, about a minute")
                                        : Tf("Generate this shot · ≈%@ credits", "\(AiShot.creditsAbout)"),
                          busy: aiBusy)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(busy || aiBusy)
            .accessibilityIdentifier("aiShotButton")
            Button(promptCopied ? T("Copied") : T("Copy the prompt")) {
                UIPasteboard.general.string = AiShot.prompt(for: beat)
                promptCopied = true
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityIdentifier("aiPromptCopy")
            NoteText(text: T("Or paste the prompt into any AI video tool yourself, then add the result as your own clip."))
        }
        .card(fill: Theme.grey, padding: 14)
    }

    private func makeAiShot() async {
        guard !aiBusy else { return }
        aiBusy = true
        problem = nil
        note = nil
        defer { aiBusy = false }
        do {
            let submit = try await state.api.aiClip(planId: planId, beat: beat.beat, prompt: AiShot.prompt(for: beat))
            for _ in 0..<90 {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                let status = try await state.api.clipStatus(id: submit.clipId)
                if status.status == "failed" {
                    problem = status.error.map(APIError.sentenceCase) ?? T("This shot could not be made. Nothing was charged.")
                    return
                }
                if status.status == "done" {
                    await refresh()
                    Haptics.success()
                    note = T("Shot made. It is the chosen clip now, and the other clips are still underneath.")
                    onUndoable(nil)
                    return
                }
            }
            note = T("Making the shot is taking longer than usual. Look again in a minute.")
        } catch is CancellationError {
            return
        } catch {
            problem = state.report(error)
        }
    }

    /// Not enough credits on this shot (an AI-made shot): Buy credits opens on the
    /// Account tab and this sheet closes; the shot list stays as it is.
    private func openBuyCredits() {
        state.selectedTab = 2
        state.pendingAccountRoute = .buyCredits
        onClose()
    }

    private func setLength(from old: Double) async {
        busy = true
        settingLength = true
        problem = nil
        defer { busy = false; settingLength = false }
        do {
            _ = try await state.api.shotLength(planId: planId, beat: beat.beat, seconds: newLength)
            Haptics.success()
            onUndoable(ShotUndo(beat: beat.beat, action: "length", seconds: old, label: "Undo length"))
            onClose()
        } catch {
            // The server says why, for example a shot that is the whole sentence.
            problem = state.report(error)
        }
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
            // A move is undone by moving back, a split by merging. Anything else cannot be.
            switch action {
            case "swap": onUndoable(ShotUndo(beat: beat.beat, action: "swap", withBeat: other, label: "Undo move"))
            case "split": onUndoable(ShotUndo(beat: beat.beat, action: "merge", label: "Undo split"))
            default: onUndoable(nil)
            }
            onClose()
        } catch {
            problem = state.report(error)
        }
    }
}
