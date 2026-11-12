import Foundation

/// A pretend server that lives inside the app. It is switched on only by the launch
/// argument `-uiTestMock`, so the end-to-end UI tests can drive every screen without
/// the network, real email or real credits.
final class MockAPI: KinbirAPI {
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

    private func pause() async {
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

    func requestCode(email: String) async throws {
        await pause()
        guard email.contains("@") else {
            throw APIError(kind: .other, status: 400,
                           message: "That does not look like an email address")
        }
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
            return WhoAmI(email: MockAPI.email, voices: list, activeVoiceId: activeVoiceId,
                          creditsBalance: credits, tier: nil, hasPaid: false, trialMaxChars: 900)
        }
    }

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

    func enrollScript() async throws -> String {
        await pause()
        return MockAPI.enrollText
    }

    func enroll(videoURL: URL) async throws -> EnrollResult {
        await pause()
        return locked {
            let id = nextId("v")
            let first = voices.isEmpty
            voices.append(VoiceSummary(voiceId: id, name: nil, active: first,
                                       refLanguage: "am", badge: "green"))
            if first { activeVoiceId = id }
            let granted: Double = first ? 20 : 0
            credits += granted
            return EnrollResult(status: "approved", voiceId: id, advice: [], needsReview: false,
                                creditsGranted: granted, creditsBalance: credits,
                                message: "your voice is ready")
        }
    }

    // MARK: script

    func extract(url: String) async throws -> ExtractResult {
        await pause()
        return ExtractResult(title: "Sample article",
                             text: "Coffee was first discovered in Ethiopia many centuries ago.",
                             chars: 58, note: "")
    }

    func rewriteEstimate(text: String) async throws -> Double {
        await pause()
        return 1
    }

    func rewrite(text: String,
                 onDelta: @escaping @MainActor (String) -> Void) async throws -> RewriteResult {
        await pause()
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

    func generate(text: String, draftId: String?) async throws -> GenerateSubmit {
        await pause()
        return try locked {
            guard activeVoiceId != nil else {
                throw APIError(kind: .other, status: 400,
                               message: "Clone your voice first - your account has no voice yet")
            }
            guard credits >= 2.5 else {
                throw APIError.from(
                    status: 402,
                    data: Data(#"{"detail":"insufficient credits (need ~2.5, have 0.0) - top up or upgrade your plan"}"#.utf8),
                    path: "/generate")
            }
            credits -= 2.5
            let id = nextId("job")
            jobStore[id] = JobStatus(jobId: id, type: "generate", status: "queued", segmentsDone: 0,
                                 segmentsTotal: 2, error: nil, audioSec: nil, segments: [text],
                                 creditsCharged: nil, creditsBalance: credits)
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
                return JobSummary(jobId: id, status: j.status, createdAt: "2026-11-12T10:00:00Z",
                                  finishedAt: j.isDone ? "2026-11-12T10:01:00Z" : nil,
                                  audioSec: j.audioSec, preview: String(j.scriptText.prefix(90)))
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
