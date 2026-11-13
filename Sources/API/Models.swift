import Foundation

// Shapes of the Kinbir server's answers. Decoded with `.convertFromSnakeCase`, so
// `voice_id` arrives as `voiceId`. Every field the app can live without is optional:
// a server change must never crash the app.

struct VoiceSummary: Codable, Identifiable, Equatable {
    let voiceId: String
    var name: String?
    var active: Bool?
    var refLanguage: String?
    var badge: String?

    var id: String { voiceId }
    /// Voices enrolled before English mode carry no language and are Amharic.
    var isAmharic: Bool { (refLanguage ?? "am") == "am" }
}

struct WhoAmI: Codable, Equatable {
    var email: String?
    var voices: [VoiceSummary]?
    var activeVoiceId: String?
    var creditsBalance: Double?
    var tier: String?
    var hasPaid: Bool?
    var trialMaxChars: Int?

    var amharicVoices: [VoiceSummary] { (voices ?? []).filter { $0.isAmharic } }
    var hasVoice: Bool { !amharicVoices.isEmpty }
    var balance: Double { creditsBalance ?? 0 }
}

struct VoiceList: Codable, Equatable {
    var voices: [VoiceSummary]
    var activeVoiceId: String?
}

struct RequestCodeResult: Codable, Equatable {
    var sent: Bool?
    var expiresInMin: Int?
}

struct AuthResult: Codable, Equatable {
    let accessCode: String
    var email: String?
    var isNew: Bool?
    var hasVoice: Bool?
    var creditsBalance: Double?
}

struct EnrollScript: Codable, Equatable {
    var personal: String?
    var enrollText: String?

    var text: String { personal ?? enrollText ?? "" }
}

struct EnrollResult: Codable, Equatable {
    var status: String
    var voiceId: String?
    var advice: [String]?
    var needsReview: Bool?
    var creditsGranted: Double?
    var creditsBalance: Double?
    var message: String?

    var isApproved: Bool { status == "approved" }
}

struct ExtractResult: Codable, Equatable {
    var title: String?
    var text: String
    var chars: Int?
    var note: String?
}

struct RewriteEstimate: Codable, Equatable {
    var creditsEstimated: Double
}

struct RewriteResult: Codable, Equatable {
    var skipped: Bool?
    var reason: String?
    var amharic: String?
    var draftId: String?
    var warnings: [String]?
    var creditsCharged: Double?
    var creditsBalance: Double?
}

struct GenerateSubmit: Codable, Equatable {
    let jobId: String
    var status: String?
    var segmentsTotal: Int?
    var creditsReserved: Double?
    var creditsBalance: Double?
}

struct JobSummary: Codable, Identifiable, Equatable {
    let jobId: String
    var status: String
    var createdAt: String?
    var finishedAt: String?
    var audioSec: Double?
    var preview: String?

    var id: String { jobId }
}

struct JobsList: Codable, Equatable {
    var jobs: [JobSummary]
    var keptHours: Int?
}

struct JobStatus: Codable, Equatable {
    let jobId: String
    var type: String?
    var status: String
    var segmentsDone: Int?
    var segmentsTotal: Int?
    var error: String?
    var audioSec: Double?
    var segments: [String]?
    var creditsCharged: Double?
    var creditsBalance: Double?
    /// The newest footage plan made from this voiceover, when there is one.
    var brollPlanId: String?

    var isDone: Bool { status == "done" }
    var isFailed: Bool { status == "failed" }
    var isRunning: Bool { status == "running" }
    /// The customer's own script, as the server keeps it for display.
    var scriptText: String { (segments ?? []).joined(separator: " ") }
}

struct DemoRef: Codable, Equatable {
    let demoId: String
    var status: String
    var cached: Bool?
    var error: String?
    var audioSec: Double?

    var isDone: Bool { status == "done" }
    var isFailed: Bool { status == "failed" }
}

struct DeleteAccountResult: Codable, Equatable {
    var deleted: Bool?
    var note: String?
}

enum JSON {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
