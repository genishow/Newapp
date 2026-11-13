import Foundation

/// Everything the app asks of the Kinbir server. `LiveAPI` talks to api.kinbir.com;
/// `MockAPI` answers from memory for the end-to-end UI tests.
protocol KinbirAPI: AnyObject {
    // Sign in
    func requestCode(email: String) async throws
    func verify(email: String, code: String) async throws -> AuthResult

    // Account
    func whoami() async throws -> WhoAmI
    func deleteAccount(confirmEmail: String) async throws

    // Voices
    func activateVoice(id: String) async throws
    func renameVoice(id: String, name: String) async throws
    func deleteVoice(id: String) async throws
    func enrollScript(language: Lang) async throws -> String
    func enroll(videoURL: URL, language: Lang) async throws -> EnrollResult
    /// A short sample of this voice, as a local file. Free.
    func voicePreview(voiceId: String) async throws -> URL

    // Script
    func extract(url: String) async throws -> ExtractResult
    func rewriteEstimate(text: String, options: ScriptOptions) async throws -> Double
    func rewrite(text: String, options: ScriptOptions,
                 onDelta: @escaping @MainActor (String) -> Void) async throws -> RewriteResult
    func saveScriptRules(_ rules: String) async throws -> String
    /// Spoken Amharic to text. Free.
    func transcribe(audioURL: URL) async throws -> String

    // Voiceover
    func generate(text: String, draftId: String?, voice: VoiceOptions) async throws -> GenerateSubmit
    /// English only, free: changes how strongly pauses are read.
    func setEmphasis(jobId: String, emphasis: String) async throws

    // Fix a word
    func fixCandidates(word: String) async throws -> [FixOption]
    func fixPreview(word: String, optionId: Int?, custom: String?) async throws -> FixPreview
    func fixPreviewStatus(id: String) async throws -> FixPreview
    func fixPreviewAudio(id: String) async throws -> URL
    func fixApply(jobId: String, fix: FixEdit) async throws -> FixBatch
    func fixStatus(jobId: String, batchId: String) async throws -> FixBatch
    func jobs() async throws -> [JobSummary]
    func job(id: String) async throws -> JobStatus
    /// Small copy for the in-app player. Returns a local file.
    func playbackAudio(jobId: String) async throws -> URL
    /// Full quality wav for saving and sharing. Returns a local file.
    func downloadAudio(jobId: String) async throws -> URL

    // Demo, no account needed
    func demoGenerate(text: String) async throws -> DemoRef
    func demoStatus(id: String) async throws -> DemoRef
    func demoAudio(id: String) async throws -> URL

    // Footage
    func footageEstimate(script: String) async throws -> Double
    func planFootage(jobId: String, shape: Shape, source: FootageSource) async throws -> PlanSubmit
    func planJob(id: String) async throws -> PlanJob
    func plan(id: String) async throws -> StoredPlan
    /// One slice of the stock search. Pass `beat` to search a single shot again.
    func searchFootage(planId: String, shape: Shape?, beat: Int?, query: String?) async throws -> SearchResult
    func chooseClip(planId: String, beat: Int, clipId: Int) async throws
    /// Places the user's own clips on the shots.
    func matchOwnClips(planId: String, fill: Bool) async throws -> MatchResult
    func useUpload(planId: String, beat: Int, uploadId: String) async throws -> [Beat]
    func uploads(jobId: String) async throws -> [UploadMeta]
    func uploadClip(fileURL: URL, jobId: String,
                    onProgress: @escaping @MainActor (Double) -> Void) async throws -> UploadMeta

    // Music
    func music() async throws -> [MusicTrack]
    func musicAudio(trackId: String) async throws -> URL

    // Finished video
    func assemble(planId: String, shape: Shape, musicId: String?, captions: Bool,
                  avatar: AvatarChoice?) async throws -> AssembleSubmit
    func assembleStatus(id: String) async throws -> AssembleStatus
    func stopAssemble(id: String) async throws -> StopResult
    func downloadVideo(id: String) async throws -> URL
    func videos() async throws -> [VideoSummary]

    // Avatar
    func avatarInfo() async throws -> AvatarInfo
    /// The stored photo as a local file.
    func avatarPhoto() async throws -> URL
    func uploadAvatarPhoto(jpeg: Data) async throws -> AvatarInfo
    func deleteAvatarPhoto() async throws
    /// The presenter clip, when it was delivered as a separate file.
    func downloadAvatarClip(videoJobId: String) async throws -> URL
    /// The server answers with paths like "/assemble/x/preview.mp4?e=..". This makes them openable.
    func absoluteURL(_ path: String?) -> URL?
}

/// The Amharic-only calls from Build 1, kept so simple callers stay simple.
extension KinbirAPI {
    func enrollScript() async throws -> String { try await enrollScript(language: .am) }
    func enroll(videoURL: URL) async throws -> EnrollResult {
        try await enroll(videoURL: videoURL, language: .am)
    }
    func rewriteEstimate(text: String) async throws -> Double {
        try await rewriteEstimate(text: text, options: ScriptOptions())
    }
    func rewrite(text: String,
                 onDelta: @escaping @MainActor (String) -> Void) async throws -> RewriteResult {
        try await rewrite(text: text, options: ScriptOptions(), onDelta: onDelta)
    }
    func generate(text: String, draftId: String?) async throws -> GenerateSubmit {
        try await generate(text: text, draftId: draftId, voice: VoiceOptions())
    }
}

/// Builds requests the way the server expects them. Pure, so it is unit-tested.
struct RequestBuilder {
    static let defaultBase = URL(string: "https://api.kinbir.com")!

    let base: URL
    let accessCode: () -> String?

    init(base: URL = RequestBuilder.defaultBase, accessCode: @escaping () -> String?) {
        self.base = base
        self.accessCode = accessCode
    }

    func url(_ path: String) -> URL {
        URL(string: base.absoluteString + path)!
    }

    /// GET and DELETE carry the credential in a header, never in the URL.
    func get(_ path: String, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url(path))
        req.httpMethod = method
        req.setValue(accessCode() ?? "", forHTTPHeaderField: "X-Access-Code")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        return req
    }

    /// POST carries the credential in the JSON body, as the web app does.
    func post(_ path: String, body: [String: Any], authenticated: Bool = true) -> URLRequest {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload = body
        if authenticated, let code = accessCode() {
            payload["access_code"] = code
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return req
    }

    func absolute(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: base.absoluteString + (path.hasPrefix("/") ? path : "/" + path))
    }

    func multipart(_ path: String, form: Multipart) -> URLRequest {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = form.finished()
        req.timeoutInterval = 300
        return req
    }
}
