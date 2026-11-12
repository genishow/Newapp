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

    func enrollScript() async throws -> String {
        try await decode(EnrollScript.self, builder.get("/enroll/script")).text
    }

    func enroll(videoURL: URL) async throws -> EnrollResult {
        let data: Data
        do {
            data = try Data(contentsOf: videoURL, options: .mappedIfSafe)
        } catch {
            throw APIError(kind: .other, status: 0, message: "The video could not be read. Try again.")
        }
        let ext = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension.lowercased()
        var form = Multipart()
        form.addField(name: "access_code", value: builder.accessCode() ?? "")
        form.addField(name: "language", value: "am")
        form.addFile(name: "video", filename: "enroll." + ext,
                     mimeType: Multipart.mimeType(forExtension: ext), data: data)
        return try await decode(EnrollResult.self, builder.multipart("/enroll", form: form))
    }

    // MARK: script

    func extract(url: String) async throws -> ExtractResult {
        try await decode(ExtractResult.self,
                         builder.post("/extract", body: ["url": url, "owns_content": true]))
    }

    func rewriteEstimate(text: String) async throws -> Double {
        try await decode(RewriteEstimate.self,
                         builder.post("/rewrite/estimate", body: ["text": text])).creditsEstimated
    }

    func rewrite(text: String,
                 onDelta: @escaping @MainActor (String) -> Void) async throws -> RewriteResult {
        let request = builder.post("/rewrite", body: ["text": text, "stream": true])
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

    func generate(text: String, draftId: String?) async throws -> GenerateSubmit {
        var body: [String: Any] = ["text": text]
        if let draftId { body["draft_id"] = draftId }
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

/// Downloaded audio lives in one temporary folder that is emptied at launch.
enum TempFiles {
    static var folder: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kinbir-audio",
                                                                                 isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(name: String, ext: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        return folder.appendingPathComponent(safe).appendingPathExtension(ext)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: folder)
    }
}
