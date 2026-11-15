import Foundation

/// A pretend server that lives inside the app. It is switched on only by the launch
/// argument `-uiTestMock`, so the end-to-end UI tests can drive every screen without
/// the network, real email or real credits.
final class MockAPI: KinbirAPI {
    /// A server-style time `offset` seconds from now, so mock items stay
    /// inside the Library's 48 hours whatever day the tests run.
    static func recent(_ offset: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset))
    }

    struct Scenario {
        var noVoice = false
        var noCredits = false
    }

    static let email = "tester@example.com"
    static let goodCode = "123456"
    static let amharicScript = "ሰላም ለሁላችሁ። ይህ በቅንብር የተዘጋጀ የአማርኛ ጽሑፍ ነው።"
    static let enrollText = "ሰላም፣ ይህ የእኔ ድምፅ ነው። ቅንብር ድምፄን እንዲጠቀም እፈቅዳለሁ።"

    private let lock = NSLock()
    private var voices: [VoiceSummary]
    private var activeVoiceId: String?
    private var credits: Double
    private var jobStore: [String: JobStatus] = [:]
    private var jobOrder: [String] = []
    private var jobPolls: [String: Int] = [:]
    private var demoPolls: [String: Int] = [:]
    private var counter = 0
    let video = MockVideoState()

    init(scenario: Scenario = Scenario()) {
        if scenario.noVoice {
            voices = []
            activeVoiceId = nil
            credits = 0
        } else {
            voices = [VoiceSummary(voiceId: "v-mock-1", name: "My voice", active: true,
                                   refLanguage: "am", badge: "green")]
            activeVoiceId = "v-mock-1"
            credits = scenario.noCredits ? 0 : 20
        }
    }

    func pause() async {
        try? await Task.sleep(nanoseconds: 120_000_000)
    }

    private func locked<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }

    private func nextId(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)-mock-\(counter)"
    }

    // MARK: sign in

    func requestCode(email: String) async throws -> RequestCodeResult {
        await pause()
        guard email.contains("@") else {
            throw APIError(kind: .other, status: 400,
                           message: "That does not look like an email address")
        }
        return RequestCodeResult(sent: true, expiresInMin: 10, emailConfigured: true)
    }

    func verify(email: String, code: String) async throws -> AuthResult {
        await pause()
        guard code == MockAPI.goodCode else {
            throw APIError(kind: .other, status: 401, message: "That code is not right - 4 tries left")
        }
        return locked {
            AuthResult(accessCode: "am-mock-code", email: email, isNew: voices.isEmpty,
                       hasVoice: !voices.isEmpty, creditsBalance: credits)
        }
    }

    // MARK: account

    func whoami() async throws -> WhoAmI {
        await pause()
        return locked {
            let list = voices.map { v -> VoiceSummary in
                var copy = v
                copy.active = (v.voiceId == activeVoiceId)
                return copy
            }
            var me = WhoAmI(email: MockAPI.email, voices: list, activeVoiceId: activeVoiceId,
                            creditsBalance: credits, tier: nil, hasPaid: false, trialMaxChars: 900,
                            scriptRules: video.scriptRules, scriptRulesDefault: "Keep sentences short.",
                            enPace: "normal", enEmphasis: "none")
            me.stockFreeLeft = stockFreeLeft
            return me
        }
    }

    private var promos: [PromoSubmission] = []
    /// Free Kinbir-voice voiceovers left, as the server counts them.
    private var stockFreeLeft = 3

    func myPromos() async throws -> PromoList {
        await pause()
        return locked { PromoList(promos: promos, reward: 40, perPlatform: 10) }
    }

    func addPromoLinks(promoId: String, links: [String]) async throws -> PromoSubmission {
        await pause()
        return try locked {
            guard let i = promos.firstIndex(where: { $0.promoId == promoId }) else {
                throw APIError(kind: .other, status: 404, message: "Unknown video")
            }
            promos[i].links = promos[i].allLinks + links
            promos[i].status = "pending"
            return promos[i]
        }
    }

    func submitPromo(videoURL: URL, links: [String], note: String) async throws -> PromoSubmission {
        await pause()
        return locked {
            let made = PromoSubmission(promoId: "pr-mock\(promos.count)", status: "pending",
                                       createdAt: "2026-11-15T10:00:00Z", reviewedAt: nil,
                                       credits: 0, reason: nil, link: links.first, links: links,
                                       platforms: nil,
                                       durationSec: 75)
            promos.insert(made, at: 0)
            return made
        }
    }

    func reportApplePurchase(signedTransaction: String) async throws -> ApplePurchaseResult {
        await pause()
        return locked {
            credits += 110
            return ApplePurchaseResult(ok: true, creditsGranted: 110, alreadyAdded: false,
                                       creditsBalance: credits, tier: "starter")
        }
    }

    func registerDevice(token: String) async throws {}
    func unregisterDevice(token: String, accessCode: String) async throws {}

    func deleteAccount(confirmEmail: String) async throws {
        await pause()
        guard confirmEmail.lowercased() == MockAPI.email else {
            throw APIError(kind: .other, status: 400, message: "That email does not match this account")
        }
    }

    // MARK: voices

    func activateVoice(id: String) async throws {
        await pause()
        locked { activeVoiceId = id }
    }

    func renameVoice(id: String, name: String) async throws {
        await pause()
        locked {
            if let i = voices.firstIndex(where: { $0.voiceId == id }) { voices[i].name = name }
        }
    }

    func deleteVoice(id: String) async throws {
        await pause()
        locked {
            voices.removeAll { $0.voiceId == id }
            if activeVoiceId == id { activeVoiceId = voices.first?.voiceId }
        }
    }

    func enrollScript(language: Lang) async throws -> String {
        await pause()
        return language == .en ? "Hello, this is my voice." : MockAPI.enrollText
    }

    func enroll(videoURL: URL, language: Lang) async throws -> EnrollResult {
        await pause()
        return locked {
            let id = nextId("v")
            let first = voices.isEmpty
            voices.append(VoiceSummary(voiceId: id, name: nil, active: first,
                                       refLanguage: language.rawValue, badge: "green"))
            if first { activeVoiceId = id }
            let granted: Double = first ? 20 : 0
            credits += granted
            return EnrollResult(status: "approved", voiceId: id, advice: [], needsReview: false,
                                creditsGranted: granted, creditsBalance: credits,
                                message: "your voice is ready", active: first)
        }
    }

    func enrollCheck(videoURL: URL, language: Lang) async throws -> EnrollCheck {
        await pause()
        return EnrollCheck(badge: "green", advice: ["looks good - this recording should clone well"],
                           videoDurationSec: 12, durationOk: true)
    }

    // MARK: script

    func extract(url: String) async throws -> ExtractResult {
        await pause()
        return ExtractResult(title: "Sample article",
                             text: "Coffee was first discovered in Ethiopia many centuries ago.",
                             chars: 58, note: "")
    }

    func rewriteEstimate(text: String, options: ScriptOptions) async throws -> Double {
        await pause()
        return 1
    }

    func rewrite(text: String, options: ScriptOptions,
                 onDelta: @escaping @MainActor (String) -> Void) async throws -> RewriteResult {
        await pause()
        video.lastScriptOptions = options
        // As on the server: text already in the output language comes back unchanged and
        // free, unless the rewrite is forced.
        if !options.force, !options.fromIdea, (options.refineInstruction ?? "").isEmpty,
           ScriptOptions.sameLanguage(text, as: options.language) {
            return RewriteResult(skipped: true, reason: "input is already in that language",
                                 amharic: text, draftId: nil, warnings: [], creditsCharged: nil,
                                 creditsBalance: nil)
        }
        let enough = locked { credits >= 1 }
        guard enough else {
            throw APIError.from(status: 402,
                                data: Data(#"{"detail":"insufficient credits (need ~1, have 0.0)"}"#.utf8),
                                path: "/rewrite")
        }
        for piece in ["ሰላም ለሁላችሁ። ", "ይህ በቅንብር የተዘጋጀ "] {
            await onDelta(piece)
            await pause()
        }
        return locked {
            credits -= 1
            return RewriteResult(skipped: false, reason: nil, amharic: MockAPI.amharicScript,
                                 draftId: "draft-mock", warnings: [], creditsCharged: 1,
                                 creditsBalance: credits)
        }
    }

    // MARK: voiceover

    func generate(text: String, draftId: String?, voice: VoiceOptions) async throws -> GenerateSubmit {
        await pause()
        video.lastVoiceOptions = voice
        return try locked {
            guard activeVoiceId != nil || voice.useStockVoice else {
                throw APIError(kind: .other, status: 400,
                               message: "Clone your voice first - your account has no voice yet")
            }
            let freeTry = voice.useStockVoice && stockFreeLeft > 0
            if freeTry { stockFreeLeft -= 1 }
            guard freeTry || credits >= 2.5 else {
                throw APIError.from(
                    status: 402,
                    data: Data(#"{"detail":"insufficient credits (need ~2.5, have 0.0) - top up or upgrade your plan"}"#.utf8),
                    path: "/generate")
            }
            if !freeTry { credits -= 2.5 }
            let id = nextId("job")
            jobStore[id] = JobStatus(jobId: id, type: "generate", status: "queued", segmentsDone: 0,
                                 segmentsTotal: 2, error: nil, audioSec: nil, segments: [text],
                                 creditsCharged: nil, creditsBalance: credits, brollPlanId: nil,
                                 language: voice.language.rawValue, emphasis: voice.emphasis,
                                 fixedWords: [], voiceId: activeVoiceId,
                                 pace: voice.pace, pacesReady: nil, pacePrice: 2.5)
            jobOrder.insert(id, at: 0)
            jobPolls[id] = 0
            return GenerateSubmit(jobId: id, status: "queued", segmentsTotal: 2,
                                  creditsReserved: 2.5, creditsBalance: credits)
        }
    }

    func jobs() async throws -> [JobSummary] {
        await pause()
        return locked {
            jobOrder.compactMap { id -> JobSummary? in
                guard let j = jobStore[id] else { return nil }
                return JobSummary(jobId: id, status: j.status, createdAt: Self.recent(-3600),
                                  finishedAt: j.isDone ? Self.recent(-3540) : nil,
                                  audioSec: j.audioSec, preview: String(j.scriptText.prefix(90)),
                                  voiceId: "v-mock-1")
            }
        }
    }

    /// queued, then running, then done: one step per poll.
    func job(id: String) async throws -> JobStatus {
        await pause()
        return try locked {
            guard var j = jobStore[id] else {
                throw APIError(kind: .other, status: 404, message: "That voiceover was not found")
            }
            let polls = (jobPolls[id] ?? 0) + 1
            jobPolls[id] = polls
            if polls == 1 {
                j.status = "running"
                j.segmentsDone = 1
            } else if polls >= 2 {
                j.status = "done"
                j.segmentsDone = 2
                j.audioSec = 1
                j.creditsCharged = 2.5
            }
            jobStore[id] = j
            return j
        }
    }

    func playbackAudio(jobId: String) async throws -> URL {
        await pause()
        return try ToneFile.write(name: "play-" + jobId)
    }

    func downloadAudio(jobId: String) async throws -> URL {
        await pause()
        return try ToneFile.write(name: "kinbir-voiceover-" + jobId)
    }

    // MARK: demo

    func demoGenerate(text: String) async throws -> DemoRef {
        await pause()
        return locked {
            let id = nextId("demo")
            demoPolls[id] = 0
            return DemoRef(demoId: id, status: "queued", cached: false, error: nil, audioSec: nil)
        }
    }

    func demoStatus(id: String) async throws -> DemoRef {
        await pause()
        return locked {
            let polls = (demoPolls[id] ?? 0) + 1
            demoPolls[id] = polls
            return DemoRef(demoId: id, status: polls >= 1 ? "done" : "running", cached: false,
                           error: nil, audioSec: 1)
        }
    }

    func demoAudio(id: String) async throws -> URL {
        await pause()
        return try ToneFile.write(name: "demo-" + id)
    }
}

/// A one second, quiet 440 Hz tone as a wav file. Lets the mock server return
/// real audio that the player can open.
enum ToneFile {
    static func data(seconds: Double = 1.0, sampleRate: Int = 16_000) -> Data {
        let count = Int(Double(sampleRate) * seconds)
        var samples = Data(capacity: count * 2)
        for i in 0..<count {
            let value = sin(2.0 * Double.pi * 440.0 * Double(i) / Double(sampleRate)) * 3000.0
            var s = Int16(value).littleEndian
            withUnsafeBytes(of: &s) { samples.append(contentsOf: $0) }
        }

        func le32(_ v: UInt32) -> Data {
            var x = v.littleEndian
            return withUnsafeBytes(of: &x) { Data($0) }
        }
        func le16(_ v: UInt16) -> Data {
            var x = v.littleEndian
            return withUnsafeBytes(of: &x) { Data($0) }
        }

        var out = Data()
        out.append(Data("RIFF".utf8))
        out.append(le32(UInt32(36 + samples.count)))
        out.append(Data("WAVE".utf8))
        out.append(Data("fmt ".utf8))
        out.append(le32(16))
        out.append(le16(1))                              // PCM
        out.append(le16(1))                              // mono
        out.append(le32(UInt32(sampleRate)))
        out.append(le32(UInt32(sampleRate * 2)))         // byte rate
        out.append(le16(2))                              // block align
        out.append(le16(16))                             // bits per sample
        out.append(Data("data".utf8))
        out.append(le32(UInt32(samples.count)))
        out.append(samples)
        return out
    }

    static func write(name: String) throws -> URL {
        let url = TempFiles.url(name: name, ext: "wav")
        try data().write(to: url, options: .atomic)
        return url
    }
}

// MARK: - footage, music and the finished video (pretend)

/// Mutable state for the pretend footage flow. Kept apart so MockAPI's stored
/// properties stay in one place.
final class MockVideoState {
    var beats: [Beat] = []
    var searches = 0
    var uploads: [UploadMeta] = []
    var assemblePolls: [String: Int] = [:]
    var videos: [VideoSummary] = []
    var planPolls = 0
    /// Set by the `-mockStockLimit` launch argument: stock search answers "not now".
    var stockLimited = Launch.mockStockLimit
    var hasAvatarPhoto = false
    var lastAvatar: AvatarChoice?
    var scriptRules = ""
    var lastScriptOptions: ScriptOptions?
    var lastVoiceOptions: VoiceOptions?
    var fixPolls: [String: Int] = [:]
    var appliedFixes: [FixEdit] = []
    /// The speed sent with the last batch of changes, if any.
    var lastFixPace: String?
    /// Whether the last batch read the whole script again in the same voiceover.
    var lastFixWhole = false
    var warmCalls = 0
}

extension MockAPI {
    func voicePreview(voiceId: String) async throws -> URL {
        await pause()
        return try ToneFile.write(name: "voice-" + voiceId)
    }

    func saveScriptRules(_ rules: String) async throws -> String {
        await pause()
        video.scriptRules = rules
        return rules
    }

    func dictationAddress() -> (base: URL, accessCode: String)? { nil }

    func warmDictation() async {}

    func transcribe(audioURL: URL) async throws -> String {
        await pause()
        return "ሰላም ለሁላችሁ።"
    }

    func setEmphasis(jobId: String, emphasis: String) async throws {
        await pause()
    }

    func fixCandidates(word: String) async throws -> [FixOption] {
        await pause()
        return [FixOption(optionId: 0, label: "Option A"), FixOption(optionId: 1, label: "Option B")]
    }

    func fixPreview(word: String, optionId: Int?, custom: String?) async throws -> FixPreview {
        await pause()
        return FixPreview(previewId: "pv-\(optionId ?? 99)", status: "done", firstEver: false)
    }

    func fixPreviewStatus(id: String) async throws -> FixPreview {
        await pause()
        return FixPreview(previewId: id, status: "done", firstEver: false)
    }

    func fixPreviewAudio(id: String) async throws -> URL {
        await pause()
        return try ToneFile.write(name: "fix-" + id)
    }

    func fixByEar(jobId: String, word: String, audioURL: URL) async throws -> String {
        await pause()
        return "ear-1"
    }

    func fixByEarStatus(matchId: String) async throws -> ByEarResult {
        await pause()
        return ByEarResult(status: "done",
                           ranked: [ByEarMatch(optionId: 1001, previewId: "pv-ear-1", match: 92),
                                    ByEarMatch(optionId: 1002, previewId: "pv-ear-2", match: 71)],
                           error: nil)
    }

    func fixApply(jobId: String, fixes: [FixEdit], pace: String?, whole: Bool) async throws -> FixBatch {
        await pause()
        video.appliedFixes.append(contentsOf: fixes)
        video.lastFixPace = pace
        video.lastFixWhole = whole
        if let pace, var job = jobStore[jobId] {
            job.pace = pace
            jobStore[jobId] = job
        }
        video.fixPolls["fx-1"] = 0
        return FixBatch(batchId: "fx-1", status: "queued", error: nil)
    }

    func changePace(jobId: String, pace: String) async throws -> FixBatch {
        await pause()
        guard var job = jobStore[jobId] else {
            throw APIError(kind: .other, status: 404, message: "That voiceover is gone")
        }
        let ready = (job.pacesReady ?? []).contains { $0.pace == pace }
        if !ready {
            let price = job.pacePrice ?? 2.5
            guard credits >= price else {
                throw APIError(kind: .needsCredits, status: 402, message: "Not enough credits")
            }
            credits -= price
        }
        var takes = job.pacesReady ?? []
        if !takes.contains(where: { $0.pace == (job.pace ?? "normal") }) {
            takes.append(PaceTake(pace: job.pace ?? "normal", audioSec: job.audioSec))
        }
        if !takes.contains(where: { $0.pace == pace }) {
            takes.append(PaceTake(pace: pace, audioSec: job.audioSec))
        }
        job.pace = pace
        job.pacesReady = takes
        jobStore[jobId] = job
        let id = "pace-" + pace
        video.fixPolls[id] = ready ? 5 : 0
        return FixBatch(batchId: id, status: ready ? "done" : "queued", error: nil)
    }

    func fixCancel(jobId: String, batchId: String) async throws {
        await pause()
    }

    func warmEngine() async {
        video.warmCalls += 1
    }

    func recentScripts() async throws -> [SavedScript] {
        await pause()
        return []
    }

    func fixStatus(jobId: String, batchId: String) async throws -> FixBatch {
        await pause()
        let polls = (video.fixPolls[batchId] ?? 0) + 1
        video.fixPolls[batchId] = polls
        return FixBatch(batchId: batchId, status: polls >= 2 ? "done" : "running", error: nil)
    }
}

extension MockAPI {
    private static func stockClip(_ id: Int) -> Candidate {
        Candidate(clipId: id, poster: nil, previewLink: nil, link: nil, duration: 6,
                  desc: "Stock clip \(id)", author: "Mock", ownUpload: false)
    }

    func footageEstimate(script: String) async throws -> Double {
        await pause()
        return 3
    }

    func placeAllClips(planId: String) async throws -> MatchResult {
        await pause()
        return MatchResult(matched: video.uploads.count, pendingLabels: 0, beats: video.beats)
    }

    func changeSource(planId: String, source: FootageSource) async throws {
        await pause()
    }

    func rescanFootage(planId: String) async throws -> PlanSubmit {
        await pause()
        return PlanSubmit(jobId: "scan-mock", status: "queued", creditsEstimated: nil)
    }

    func footageCheck(jobId: String) async throws -> FootageCheckJob {
        await pause()
        return FootageCheckJob(status: "done", error: nil,
                               result: FootageCheckResult(scanned: video.beats.count, mismatched: [],
                                                          note: nil))
    }

    func verifyShots(planId: String, beats: [Int]) async throws -> VerifyResult {
        await pause()
        return VerifyResult(checks: beats.map { ShotVerdict(beat: $0, verdict: "yes", why: nil) },
                            autoReplaced: [], flagged: 0, beats: video.beats, creditsCharged: 2, note: nil)
    }

    func uploadMusic(fileURL: URL) async throws -> MusicTrack {
        await pause()
        return MusicTrack(trackId: "mine.mp3", kind: "yours", title: "My music")
    }

    func hasLogo() async throws -> Bool {
        await pause()
        return false
    }

    func uploadLogo(image: Data, filename: String, mimeType: String) async throws -> Bool {
        await pause()
        return true
    }

    func planFootage(jobId: String, shape: Shape, source: FootageSource,
                     shotLength: String, breaks: MusicBreaks) async throws -> PlanSubmit {
        await pause()
        video.planPolls = 0
        video.searches = 0
        video.beats = [
            Beat(beat: 1, start: 0, end: 3, dur: 3, says: "ሰላም ለሁላችሁ።", mustShow: "people waving",
                 query: "people waving", type: "talk", status: nil, candidates: nil, exhausted: nil),
            Beat(beat: 2, start: 3, end: 6, dur: 3, says: "ይህ የአማርኛ ጽሑፍ ነው።", mustShow: "writing",
                 query: "writing", type: "talk", status: nil, candidates: nil, exhausted: nil),
        ]
        return PlanSubmit(jobId: "job-mock-plan", status: "queued", creditsEstimated: 3)
    }

    func planJob(id: String) async throws -> PlanJob {
        await pause()
        video.planPolls += 1
        guard video.planPolls >= 2 else { return PlanJob(status: "running", error: nil, result: nil) }
        return PlanJob(status: "done", error: nil,
                       result: PlanResult(planId: "bp-mock", beats: video.beats,
                                          creditsCharged: 3, creditsBalance: nil))
    }

    func plan(id: String) async throws -> StoredPlan {
        await pause()
        return StoredPlan(planId: id, jobId: nil, orientation: "portrait", source: "stock",
                          beats: video.beats)
    }

    func searchFootage(planId: String, shape: Shape?, beat: Int?,
                       query: String?) async throws -> SearchResult {
        await pause()
        if video.stockLimited {
            return SearchResult(searched: 0, remaining: video.beats.count, gaps: [],
                                beats: video.beats, retryAfter: 1)
        }
        video.searches += 1
        for i in video.beats.indices where beat == nil || video.beats[i].beat == beat {
            let base = video.beats[i].beat * 100 + video.searches * 10
            video.beats[i].candidates = [MockAPI.stockClip(base), MockAPI.stockClip(base + 1)]
            video.beats[i].status = "ok"
        }
        return SearchResult(searched: video.beats.count, remaining: 0, gaps: [],
                            beats: video.beats, retryAfter: nil)
    }

    func chooseClip(planId: String, beat: Int, clipId: Int) async throws {
        await pause()
        guard let i = video.beats.firstIndex(where: { $0.beat == beat }),
              var list = video.beats[i].candidates,
              let j = list.firstIndex(where: { $0.clipId == clipId }) else { return }
        let picked = list.remove(at: j)
        list.insert(picked, at: 0)
        video.beats[i].candidates = list
    }

    func shotTool(planId: String, beat: Int, action: String, withBeat: Int?) async throws -> [Beat] {
        await pause()
        guard let i = video.beats.firstIndex(where: { $0.beat == beat }) else { return video.beats }
        switch action {
        case "clear":
            video.beats[i].candidates = []
        case "swap":
            if let other = withBeat, let j = video.beats.firstIndex(where: { $0.beat == other }) {
                let mine = video.beats[i].candidates
                video.beats[i].candidates = video.beats[j].candidates
                video.beats[j].candidates = mine
            }
        default:
            break
        }
        return video.beats
    }

    func stretchShot(planId: String, beat: Int, seconds: Double) async throws -> StretchResult {
        await pause()
        guard let i = video.beats.firstIndex(where: { $0.beat == beat }),
              video.beats.indices.contains(i + 1) else {
            throw APIError(kind: .other, status: 409, message: "This shot's length is set by your voiceover")
        }
        let now = video.beats[i].dur ?? 3
        let next = video.beats[i + 1].dur ?? 3
        let got = min(max(ClipRules.minShotSeconds, seconds), now + next - ClipRules.minShotSeconds)
        let start = video.beats[i].start ?? 0
        video.beats[i].dur = got
        video.beats[i].end = start + got
        video.beats[i + 1].start = start + got
        video.beats[i + 1].dur = now + next - got
        return StretchResult(beats: video.beats, durSec: got,
                             note: "This shot is now " + String(format: "%.1f", got) + " seconds.")
    }

    func autofill(planId: String) async throws -> AutofillSubmit {
        await pause()
        for i in video.beats.indices where video.beats[i].candidates?.isEmpty != false {
            video.beats[i].candidates = [MockAPI.stockClip(700 + i)]
        }
        video.planPolls = 2
        return AutofillSubmit(jobId: "fill-mock", status: "queued", note: nil)
    }

    func matchOwnClips(planId: String, fill: Bool) async throws -> MatchResult {
        await pause()
        guard !video.uploads.isEmpty else {
            return MatchResult(matched: 0, pendingLabels: 0, beats: video.beats)
        }
        var placed = 0
        for i in video.beats.indices where video.beats[i].chosen == nil {
            video.beats[i].candidates = [Candidate(clipId: 9000 + i, poster: nil, previewLink: nil,
                                                   link: nil, duration: 5, desc: "My clip",
                                                   author: nil, ownUpload: true)]
            video.beats[i].status = "ok"
            placed += 1
        }
        return MatchResult(matched: placed, pendingLabels: 0, beats: video.beats)
    }

    func useUpload(planId: String, beat: Int, uploadId: String) async throws -> [Beat] {
        await pause()
        if let i = video.beats.firstIndex(where: { $0.beat == beat }) {
            let mine = Candidate(clipId: 9500 + beat, poster: nil, previewLink: nil, link: nil,
                                 duration: 5, desc: "My clip", author: nil, ownUpload: true)
            video.beats[i].candidates = [mine] + (video.beats[i].candidates ?? [])
            video.beats[i].status = "ok"
        }
        return video.beats
    }

    func uploads(jobId: String) async throws -> [UploadMeta] {
        await pause()
        return video.uploads
    }

    func uploadClip(fileURL: URL, jobId: String,
                    onProgress: @escaping @MainActor (Double) -> Void) async throws -> UploadMeta {
        await pause()
        await onProgress(1)
        let meta = UploadMeta(uploadId: "up-mock-\(video.uploads.count + 1).mov",
                              name: "My clip \(video.uploads.count + 1)", kind: "video",
                              duration: 5, labelStatus: "done")
        video.uploads.append(meta)
        return meta
    }

    func music() async throws -> [MusicTrack] {
        await pause()
        return [MusicTrack(trackId: "calm.mp3", kind: "kinbir", title: "Calm"),
                MusicTrack(trackId: "bright.mp3", kind: "kinbir", title: "Bright")]
    }

    func musicAudio(trackId: String) async throws -> URL {
        await pause()
        return try ToneFile.write(name: "music-" + trackId)
    }

    func assemble(planId: String, shape: Shape, musicId: String?, captions: Bool,
                  avatar: AvatarChoice?, options: RenderOptions) async throws -> AssembleSubmit {
        await pause()
        if let avatar, avatar.enabled {
            guard video.hasAvatarPhoto else {
                throw APIError(kind: .other, status: 400, message: "Upload an avatar photo first")
            }
            video.lastAvatar = avatar
        } else {
            video.lastAvatar = nil
        }
        if video.beats.contains(where: { $0.isEmpty }) {
            throw APIError(kind: .other, status: 409,
                           message: "Some shots have no footage yet. Nothing was charged.")
        }
        let id = "vid-mock-\(video.videos.count + 1)"
        video.assemblePolls[id] = 0
        return AssembleSubmit(jobId: id, status: "queued", creditsCharged: 2)
    }

    func assembleStatus(id: String) async throws -> AssembleStatus {
        await pause()
        let polls = (video.assemblePolls[id] ?? 0) + 1
        video.assemblePolls[id] = polls
        guard polls >= 2 else {
            return AssembleStatus(status: "running", filesDone: 1, filesTotal: 2, durationSec: nil,
                                  error: nil, previewUrl: nil, streamUrl: nil, downloadUrl: nil,
                                  orientation: "portrait", avatarSkipped: nil, avatarMode: nil, avatarFile: nil)
        }
        if !video.videos.contains(where: { $0.videoJobId == id }) {
            video.videos.insert(VideoSummary(videoJobId: id, planId: "bp-mock", jobId: nil,
                                             orientation: "portrait", durationSec: 6,
                                             finishedAt: Self.recent(-3300), preview: "ሰላም ለሁላችሁ።"),
                                at: 0)
        }
        let separate = video.lastAvatar?.mode == .separate
        return AssembleStatus(status: "done", filesDone: 2, filesTotal: 2, durationSec: 6, error: nil,
                              previewUrl: nil, streamUrl: nil,
                              downloadUrl: "/assemble/\(id)/video.mp4", orientation: "portrait",
                              avatarSkipped: nil,
                              avatarMode: video.lastAvatar?.mode.rawValue,
                              avatarFile: separate)
    }

    func stopAssemble(id: String) async throws -> StopResult {
        await pause()
        return StopResult(status: "cancelled", creditsRefunded: 2)
    }

    func downloadVideo(id: String) async throws -> URL {
        await pause()
        let url = TempFiles.url(name: "kinbir-" + id, ext: "mp4")
        try Data("mock video".utf8).write(to: url)
        return url
    }

    func videos() async throws -> [VideoSummary] {
        await pause()
        return video.videos
    }

    func absoluteURL(_ path: String?) -> URL? { nil }

    func avatarInfo() async throws -> AvatarInfo {
        await pause()
        return AvatarInfo(hasPhoto: video.hasAvatarPhoto, verified: video.hasAvatarPhoto)
    }

    func avatarPhoto() async throws -> URL {
        await pause()
        throw APIError(kind: .other, status: 404, message: "No avatar photo on this account")
    }

    func uploadAvatarPhoto(jpeg: Data) async throws -> AvatarInfo {
        await pause()
        video.hasAvatarPhoto = true
        return AvatarInfo(hasPhoto: true, verified: true)
    }

    func deleteAvatarPhoto() async throws {
        await pause()
        video.hasAvatarPhoto = false
    }

    func downloadAvatarClip(videoJobId: String) async throws -> URL {
        await pause()
        let url = TempFiles.url(name: "kinbir-avatar-" + videoJobId, ext: "mp4")
        try Data("mock avatar".utf8).write(to: url)
        return url
    }

    /// One clip per appearance the last video asked for, 30 seconds apart.
    func avatarClips(videoJobId: String) async throws -> [[Double]] {
        await pause()
        guard let avatar = video.lastAvatar, avatar.mode == .separate, !avatar.wholeVideo else { return [] }
        let count = (avatar.atStart ? 1 : 0) + avatar.middles.count + (avatar.atEnd ? 1 : 0)
        return (0..<count).map { [Double($0) * 30, Double(avatar.seconds)] }
    }

    func downloadAvatarClip(videoJobId: String, index: Int) async throws -> URL {
        await pause()
        let url = TempFiles.url(name: "kinbir-avatar-" + videoJobId + "-\(index)", ext: "mp4")
        try Data("mock avatar \(index)".utf8).write(to: url)
        return url
    }
}
