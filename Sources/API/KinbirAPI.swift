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
    func enrollScript() async throws -> String
    func enroll(videoURL: URL) async throws -> EnrollResult

    // Script
    func extract(url: String) async throws -> ExtractResult
    func rewriteEstimate(text: String) async throws -> Double
    func rewrite(text: String, onDelta: @escaping @MainActor (String) -> Void) async throws -> RewriteResult

    // Voiceover
    func generate(text: String, draftId: String?) async throws -> GenerateSubmit
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

    func multipart(_ path: String, form: Multipart) -> URLRequest {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = form.finished()
        req.timeoutInterval = 300
        return req
    }
}
