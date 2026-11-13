import Foundation

/// The real server, https://api.kinbir.com.
final class LiveAPI: KinbirAPI {
    private let builder: RequestBuilder
    private let session: URLSession

    init(accessCode: @escaping () -> String?) {
        self.builder = RequestBuilder(accessCode: accessCode)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180      // the engine can take a while to wake
        config.timeoutIntervalForResource = 600
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        self.session = URLSession(configuration: config)
    }

    // MARK: plumbing

    private func send(_ request: URLRequest) async throws -> Data {
        let path = request.url?.path ?? ""
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw APIError.from(status: status, data: data, path: path)
            }
            return data
        } catch {
            throw APIError.wrap(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ request: URLRequest) async throws -> T {
        let data = try await send(request)
        do {
            return try JSON.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.wrap(error)
        }
    }

    /// Downloads audio to a temporary file. The extension follows the content type,
    /// because the player endpoint can answer mp3 or wav.
    private func downloadFile(_ request: URLRequest, name: String) async throws -> URL {
        let path = request.url?.path ?? ""
        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw APIError.from(status: status, data: data, path: path)
            }
            let type = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let ext = type.contains("mpeg") || type.contains("mp3") ? "mp3" : "wav"
            let url = TempFiles.url(name: name, ext: ext)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw APIError.wrap(error)
        }
    }

    // MARK: sign in

    func requestCode(email: String) async throws {
        _ = try await send(builder.post("/auth/request-code", body: ["email": email],
                                        authenticated: false))
    }

    func verify(email: String, code: String) async throws -> AuthResult {
        try await decode(AuthResult.self,
                         builder.post("/auth/verify", body: ["email": email, "code": code],
                                      authenticated: false))
    }

    // MARK: account

    func whoami() async throws -> WhoAmI {
        try await decode(WhoAmI.self, builder.get("/whoami"))
    }

    func deleteAccount(confirmEmail: String) async throws {
        _ = try await send(builder.post("/account/delete", body: ["confirm_email": confirmEmail]))
    }

    // MARK: voices

    func activateVoice(id: String) async throws {
        _ = try await send(builder.post("/voices/activate", body: ["voice_id": id]))
    }

    func renameVoice(id: String, name: String) async throws {
        _ = try await send(builder.post("/voices/rename", body: ["voice_id": id, "name": name]))
    }

    func deleteVoice(id: String) async throws {
        _ = try await send(builder.get("/voices/\(id)", method: "DELETE"))
    }

    func enrollScript(language: Lang) async throws -> String {
        let script = try await decode(EnrollScript.self, builder.get("/enroll/script"))
        return language == .en ? (script.personalEn ?? script.text) : script.text
    }

    func enroll(videoURL: URL, language: Lang) async throws -> EnrollResult {
        let data: Data
        do {
            data = try Data(contentsOf: videoURL, options: .mappedIfSafe)
        } catch {
            throw APIError(kind: .other, status: 0, message: "The video could not be read. Try again.")
        }
        let ext = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension.lowercased()
        var form = Multipart()
        form.addField(name: "access_code", value: builder.accessCode() ?? "")
        form.addField(name: "language", value: language.rawValue)
        form.addFile(name: "video", filename: "enroll." + ext,
                     mimeType: Multipart.mimeType(forExtension: ext), data: data)
        return try await decode(EnrollResult.self, builder.multipart("/enroll", form: form))
    }

    // MARK: script

    func extract(url: String) async throws -> ExtractResult {
        try await decode(ExtractResult.self,
                         builder.post("/extract", body: ["url": url, "owns_content": true]))
    }

    func rewriteEstimate(text: String, options: ScriptOptions) async throws -> Double {
        var body: [String: Any] = ["text": text]
        if options.language == .en { body["language"] = "en" }
        if let sec = options.targetSec, options.refineInstruction == nil { body["target_sec"] = sec }
        return try await decode(RewriteEstimate.self,
                                builder.post("/rewrite/estimate", body: body)).creditsEstimated
    }

    func rewrite(text: String, options: ScriptOptions,
                 onDelta: @escaping @MainActor (String) -> Void) async throws -> RewriteResult {
        var body: [String: Any] = ["text": text, "stream": true]
        for (key, value) in options.fields { body[key] = value }
        let request = builder.post("/rewrite", body: body)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let type = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()

            // Errors and the "already Amharic" answer arrive as plain JSON.
            if !(200..<300).contains(status) || !type.contains("text/event-stream") {
                var data = Data()
                for try await byte in bytes { data.append(byte) }
                guard (200..<300).contains(status) else {
                    throw APIError.from(status: status, data: data, path: "/rewrite")
                }
                return try JSON.decoder.decode(RewriteResult.self, from: data)
            }

            for try await line in bytes.lines {
                guard let event = SSEParser.parse(line: line) else { continue }
                switch event {
                case .delta(let text):
                    await onDelta(text)
                case .done(let result):
                    return result
                case .error(let message):
                    throw APIError(kind: .other, status: 0, message: APIError.sentenceCase(message))
                }
            }
            throw APIError(kind: .server, status: 0,
                           message: "The script stopped before it was finished. Try again.")
        } catch {
            throw APIError.wrap(error)
        }
    }

    // MARK: voiceover

    func generate(text: String, draftId: String?, voice: VoiceOptions) async throws -> GenerateSubmit {
        var body: [String: Any] = ["text": text]
        if let draftId { body["draft_id"] = draftId }
        for (key, value) in voice.fields { body[key] = value }
        return try await decode(GenerateSubmit.self, builder.post("/generate", body: body))
    }

    func jobs() async throws -> [JobSummary] {
        try await decode(JobsList.self, builder.get("/jobs")).jobs
    }

    func job(id: String) async throws -> JobStatus {
        try await decode(JobStatus.self, builder.get("/jobs/\(id)"))
    }

    func playbackAudio(jobId: String) async throws -> URL {
        try await downloadFile(builder.get("/jobs/\(jobId)/playback"), name: "play-" + jobId)
    }

    func downloadAudio(jobId: String) async throws -> URL {
        try await downloadFile(builder.get("/jobs/\(jobId)/audio"), name: "kinbir-voiceover-" + jobId)
    }

    // MARK: demo

    func demoGenerate(text: String) async throws -> DemoRef {
        try await decode(DemoRef.self,
                         builder.post("/demo/generate", body: ["text": text], authenticated: false))
    }

    func demoStatus(id: String) async throws -> DemoRef {
        try await decode(DemoRef.self, builder.get("/demo/\(id)"))
    }

    func demoAudio(id: String) async throws -> URL {
        try await downloadFile(builder.get("/demo/\(id)/audio"), name: "demo-" + id)
    }
}

// MARK: - footage, music and the finished video

extension LiveAPI {
    func footageEstimate(script: String) async throws -> Double {
        try await decode(RewriteEstimate.self,
                         builder.post("/broll/estimate", body: ["text": script])).creditsEstimated
    }

    func planFootage(jobId: String, shape: Shape, source: FootageSource) async throws -> PlanSubmit {
        try await decode(PlanSubmit.self, builder.post("/broll/plan", body: [
            "job_id": jobId, "model": "sonnet", "orientation": shape.rawValue,
            "source": source.rawValue,
        ]))
    }

    func planJob(id: String) async throws -> PlanJob {
        try await decode(PlanJob.self, builder.get("/jobs/\(id)"))
    }

    func plan(id: String) async throws -> StoredPlan {
        try await decode(StoredPlan.self, builder.get("/broll/plan/\(id)"))
    }

    func searchFootage(planId: String, shape: Shape?, beat: Int?,
                       query: String?) async throws -> SearchResult {
        var body: [String: Any] = ["plan_id": planId]
        if let beat {
            // A single shot keeps the plan's own shape, so no orientation is sent.
            body["beat"] = beat
            if let query, !query.isEmpty { body["query"] = String(query.prefix(120)) }
        } else {
            body["beats_limit"] = 20
            if let shape { body["orientation"] = shape.rawValue }
        }
        return try await decode(SearchResult.self, builder.post("/broll/search", body: body))
    }

    func chooseClip(planId: String, beat: Int, clipId: Int) async throws {
        _ = try await send(builder.post("/broll/choose", body: [
            "plan_id": planId, "beat": beat, "clip_id": clipId,
        ]))
    }

    func shotTool(planId: String, beat: Int, action: String, withBeat: Int?) async throws -> [Beat] {
        var body: [String: Any] = ["plan_id": planId, "beat": beat, "action": action]
        if let withBeat { body["with_beat"] = withBeat }
        return try await decode(BeatsResult.self, builder.post("/broll/shot-length", body: body)).beats ?? []
    }

    func autofill(planId: String) async throws -> PlanSubmit {
        try await decode(PlanSubmit.self, builder.post("/broll/autofill", body: ["plan_id": planId]))
    }

    func matchOwnClips(planId: String, fill: Bool) async throws -> MatchResult {
        try await decode(MatchResult.self,
                         builder.post("/broll/match", body: ["plan_id": planId, "fill": fill]))
    }

    func useUpload(planId: String, beat: Int, uploadId: String) async throws -> [Beat] {
        try await decode(BeatsResult.self, builder.post("/broll/use-upload", body: [
            "plan_id": planId, "beat": beat, "upload_id": uploadId, "start_sec": 0,
        ])).beats ?? []
    }

    func uploads(jobId: String) async throws -> [UploadMeta] {
        let query = jobId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? jobId
        return try await decode(UploadList.self, builder.get("/uploads?job_id=" + query)).uploads
    }

    /// Sends the file in order, one small part at a time. The last part finishes the upload.
    func uploadClip(fileURL: URL, jobId: String,
                    onProgress: @escaping @MainActor (Double) -> Void) async throws -> UploadMeta {
        let total = VideoFiles.bytes(of: fileURL)
        guard total > 0, let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw APIError(kind: .other, status: 0, message: "That clip could not be read. Try another.")
        }
        defer { try? handle.close() }

        let session = UUID().uuidString
        let name = fileURL.lastPathComponent
        let ext = fileURL.pathExtension.lowercased()
        let parts = ClipRules.partCount(bytes: total)
        var sent = 0

        for seq in 0..<parts {
            try Task.checkCancellation()
            let data = (try? handle.read(upToCount: ClipRules.chunkBytes)) ?? Data()
            let isLast = seq == parts - 1
            var form = Multipart()
            form.addField(name: "access_code", value: builder.accessCode() ?? "")
            form.addField(name: "upload_session", value: session)
            form.addField(name: "seq", value: String(seq))
            form.addField(name: "last", value: isLast ? "true" : "false")
            form.addField(name: "filename", value: name)
            form.addField(name: "owned", value: "true")
            form.addField(name: "job_id", value: jobId)
            form.addFile(name: "file", filename: name,
                         mimeType: Multipart.mimeType(forExtension: ext), data: data)
            let answer = try await sendPart(builder.multipart("/uploads/chunk", form: form))
            sent += data.count
            await onProgress(min(1, Double(sent) / Double(total)))
            if isLast {
                do {
                    return try JSON.decoder.decode(UploadMeta.self, from: answer)
                } catch {
                    throw APIError.wrap(error)
                }
            }
        }
        throw APIError(kind: .other, status: 0, message: "The upload did not finish. Try again.")
    }

    /// One part, retried on a dropped connection or a server hiccup. Re-sending a part is safe.
    private func sendPart(_ request: URLRequest) async throws -> Data {
        var wait: UInt64 = 1
        var lastError = APIError.network
        for _ in 0..<4 {
            do {
                return try await send(request)
            } catch {
                let e = APIError.wrap(error)
                guard e.kind == .network || e.kind == .server else { throw e }
                lastError = e
                try await Task.sleep(nanoseconds: wait * 1_000_000_000)
                wait *= 2
            }
        }
        throw lastError
    }

    func music() async throws -> [MusicTrack] {
        try await decode(MusicList.self, builder.get("/music")).tracks
    }

    func musicAudio(trackId: String) async throws -> URL {
        let safe = trackId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trackId
        return try await downloadFile(builder.get("/music/\(safe)/audio"), name: "music-" + trackId)
    }

    func assemble(planId: String, shape: Shape, musicId: String?, captions: Bool,
                  avatar: AvatarChoice?) async throws -> AssembleSubmit {
        var body: [String: Any] = [
            "plan_id": planId, "orientation": shape.rawValue, "captions": captions,
            "quality": "1080p",
        ]
        if let musicId {
            body["music_id"] = musicId
            body["music_level"] = "balanced"
        }
        if let avatar, avatar.enabled { body["avatar"] = avatar.payload }
        return try await decode(AssembleSubmit.self, builder.post("/assemble", body: body))
    }

    func assembleStatus(id: String) async throws -> AssembleStatus {
        try await decode(AssembleStatus.self, builder.get("/assemble/\(id)"))
    }

    func stopAssemble(id: String) async throws -> StopResult {
        try await decode(StopResult.self, builder.post("/assemble/\(id)/stop", body: [:]))
    }

    /// The full file, saved to a temporary .mp4 so the share sheet can offer Save Video.
    func downloadVideo(id: String) async throws -> URL {
        try await downloadMP4(path: "/assemble/\(id)/video.mp4", name: "kinbir-" + id)
    }

    func downloadAvatarClip(videoJobId: String) async throws -> URL {
        try await downloadMP4(path: "/assemble/\(videoJobId)/avatar.mp4",
                              name: "kinbir-avatar-" + videoJobId)
    }

    private func downloadMP4(path: String, name: String) async throws -> URL {
        let request = builder.get(path)
        do {
            let (temp, response) = try await session.download(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let data = (try? Data(contentsOf: temp)) ?? Data()
                throw APIError.from(status: status, data: data, path: "/assemble")
            }
            let target = TempFiles.url(name: name, ext: "mp4")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: temp, to: target)
            return target
        } catch {
            throw APIError.wrap(error)
        }
    }

    func videos() async throws -> [VideoSummary] {
        try await decode(VideoList.self, builder.get("/videos")).videos
    }

    func absoluteURL(_ path: String?) -> URL? {
        builder.absolute(path)
    }

    // MARK: avatar

    func avatarInfo() async throws -> AvatarInfo {
        try await decode(AvatarInfo.self, builder.get("/avatar"))
    }

    func avatarPhoto() async throws -> URL {
        do {
            let data = try await send(builder.get("/avatar/photo.jpg"))
            let url = TempFiles.url(name: "avatar-photo", ext: "jpg")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw APIError.wrap(error)
        }
    }

    func uploadAvatarPhoto(jpeg: Data) async throws -> AvatarInfo {
        var form = Multipart()
        form.addField(name: "access_code", value: builder.accessCode() ?? "")
        form.addField(name: "owned", value: "true")
        form.addFile(name: "file", filename: "avatar.jpg", mimeType: "image/jpeg", data: jpeg)
        return try await decode(AvatarInfo.self, builder.multipart("/avatar/photo", form: form))
    }

    func deleteAvatarPhoto() async throws {
        _ = try await send(builder.get("/avatar/photo", method: "DELETE"))
    }
}

// MARK: - voice extras

extension LiveAPI {
    func voicePreview(voiceId: String) async throws -> URL {
        // Renders any missing samples for the account's voices, then the file is ready.
        _ = try await send(builder.post("/voices/preview", body: [:]))
        return try await downloadFile(builder.get("/voices/\(voiceId)/preview.wav"),
                                      name: "voice-" + voiceId)
    }

    func saveScriptRules(_ rules: String) async throws -> String {
        try await decode(ScriptRulesResult.self,
                         builder.post("/account/script-rules", body: ["rules": rules])).scriptRules ?? rules
    }

    func dictationAddress() -> (base: URL, accessCode: String)? {
        guard let code = builder.accessCode() else { return nil }
        return (builder.base, code)
    }

    func warmDictation() async {
        _ = try? await send(builder.post("/transcribe/warm", body: [:]))
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let data = try? Data(contentsOf: audioURL), !data.isEmpty else {
            throw APIError(kind: .other, status: 0, message: "The recording could not be read. Try again.")
        }
        var form = Multipart()
        form.addField(name: "access_code", value: builder.accessCode() ?? "")
        let wav = audioURL.pathExtension.lowercased() == "wav"
        form.addFile(name: "audio", filename: wav ? "speech.wav" : "speech.m4a",
                     mimeType: wav ? "audio/wav" : "audio/mp4", data: data)
        return try await decode(TranscribeResult.self,
                                builder.multipart("/transcribe/live", form: form)).text ?? ""
    }

    func setEmphasis(jobId: String, emphasis: String) async throws {
        _ = try await send(builder.post("/jobs/\(jobId)/emphasis", body: ["emphasis": emphasis]))
    }

    func fixCandidates(word: String) async throws -> [FixOption] {
        try await decode(FixCandidates.self,
                         builder.post("/fix-word/candidates", body: ["word": word])).options ?? []
    }

    func fixPreview(word: String, optionId: Int?, custom: String?) async throws -> FixPreview {
        var body: [String: Any] = ["word": word]
        if let optionId { body["option_id"] = optionId }
        if let custom { body["custom"] = custom }
        return try await decode(FixPreview.self, builder.post("/fix-word/preview", body: body))
    }

    func fixPreviewStatus(id: String) async throws -> FixPreview {
        try await decode(FixPreview.self, builder.get("/fix-word/preview/\(id)"))
    }

    func fixPreviewAudio(id: String) async throws -> URL {
        try await downloadFile(builder.get("/fix-word/preview/\(id).wav"), name: "fix-" + id)
    }

    func fixByEar(jobId: String, word: String, audioURL: URL) async throws -> String {
        guard let data = try? Data(contentsOf: audioURL), !data.isEmpty else {
            throw APIError(kind: .other, status: 0, message: "The recording could not be read. Try again.")
        }
        var form = Multipart()
        form.addField(name: "access_code", value: builder.accessCode() ?? "")
        form.addField(name: "job_id", value: jobId)
        form.addField(name: "word", value: word)
        form.addFile(name: "audio", filename: "word.m4a", mimeType: "audio/mp4", data: data)
        return try await decode(ByEarStart.self, builder.multipart("/fix-word/by-ear", form: form)).matchId
    }

    func fixByEarStatus(matchId: String) async throws -> ByEarResult {
        try await decode(ByEarResult.self, builder.get("/fix-word/by-ear/\(matchId)"))
    }

    func fixApply(jobId: String, fixes: [FixEdit]) async throws -> FixBatch {
        try await decode(FixBatch.self, builder.post("/fix-word/apply", body: [
            "job_id": jobId, "fixes": fixes.prefix(FixEdit.maxPerBatch).map { $0.payload },
        ]))
    }

    func fixCancel(jobId: String, batchId: String) async throws {
        _ = try await send(builder.post("/fix-word/apply/\(batchId)/cancel", body: ["job_id": jobId]))
    }

    func warmEngine() async {
        _ = try? await send(builder.post("/fix-word/warm", body: [:]))
    }

    func recentScripts() async throws -> [SavedScript] {
        try await decode(SavedScripts.self, builder.get("/scripts?limit=10&full=true")).scripts
    }

    func fixStatus(jobId: String, batchId: String) async throws -> FixBatch {
        let query = jobId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? jobId
        return try await decode(FixBatch.self,
                                builder.get("/fix-word/apply/\(batchId)?job_id=" + query))
    }
}
