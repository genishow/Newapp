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
    /// Standing instructions applied to every script Kinbir writes.
    var scriptRules: String?
    var scriptRulesDefault: String?
    /// The English speed and emphasis used last, to preselect.
    var enPace: String?
    var enEmphasis: String?
    /// True when a paid subscription is running. Deleting the account cancels it first.
    var hasSubscription: Bool?
    /// Where the plan is paid: "web" (kinbir.com) or "apple" (App Store), nil for none.
    var planVia: String?
    /// Attached to every App Store purchase so Apple's later notices name this account.
    var appleAccountToken: String?
    /// Free voiceovers left in the Kinbir voice (no clone needed).
    var stockFreeLeft: Int?
    /// Presenter tries left before the first purchase. Nil means no limit.
    var avatarFreeLeft: Int?

    var amharicVoices: [VoiceSummary] { (voices ?? []).filter { $0.isAmharic } }
    var allVoices: [VoiceSummary] { voices ?? [] }
    var hasVoice: Bool { !allVoices.isEmpty }
    var balance: Double { creditsBalance ?? 0 }
}

struct VoiceList: Codable, Equatable {
    var voices: [VoiceSummary]
    var activeVoiceId: String?
}

struct RequestCodeResult: Codable, Equatable {
    var sent: Bool?
    var expiresInMin: Int?
    /// False while the server cannot send email, so no code will arrive.
    var emailConfigured: Bool?

    /// What to tell the person after "Send me a code", as the website words it.
    func notice(email: String) -> String {
        if emailConfigured == false {
            return "Email is not switched on yet, so the code cannot reach you. Email support@kinbir.com and we will let you in."
        }
        return "We sent a 6-digit code to \(email). It works for \(expiresInMin ?? 10) minutes."
    }
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
    var personalEn: String?
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
    /// True when the new voice is the one in use. A second voice is added but not
    /// switched to, so this is false for it.
    var active: Bool?

    var isApproved: Bool { status == "approved" }
}

/// The free quality check on a recording, before it is sent (`POST /enroll/check`).
struct EnrollCheck: Codable, Equatable {
    var badge: String?
    var advice: [String]?
    var videoDurationSec: Double?
    var durationOk: Bool?

    /// The website's three labels.
    var title: String {
        switch badge {
        case "green": return "Great take"
        case "yellow": return "Good enough"
        default: return "Needs a retake"
        }
    }

    /// "12.3s recording"
    var lengthLine: String {
        String(format: "%.1fs recording", videoDurationSec ?? 0)
    }
}

/// The answer of `POST /voices/preview`: one line per voice, each with its own verdict.
struct VoicePreviewBatch: Codable, Equatable {
    struct Clip: Codable, Equatable {
        var voiceId: String
        var ok: Bool?
        var error: String?
    }

    var clips: [Clip]?

    /// The server's own reason when this voice's sample could not be made. Nil when it is fine.
    func problem(voiceId: String) -> String? {
        guard let mine = (clips ?? []).first(where: { $0.voiceId == voiceId }), mine.ok == false else {
            return nil
        }
        return mine.error ?? "This voice could not be previewed."
    }
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
    var voiceId: String?

    var id: String { jobId }

    /// The server lists every kind of job here: script writing, footage plans and renders
    /// as well as voiceovers. Only a finished voiceover has audio to open.
    var isFinishedVoiceover: Bool {
        jobId.hasPrefix("job-") && status == "done" && (audioSec ?? 0) > 0
            && !(preview ?? "").isEmpty
    }

    /// A voiceover still being made. Other running jobs carry no voice.
    var isRunningVoiceover: Bool {
        jobId.hasPrefix("job-") && (status == "queued" || status == "running")
            && !(voiceId ?? "").isEmpty
    }

    var belongsInLibrary: Bool { isFinishedVoiceover || isRunningVoiceover }
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
    /// Absent means Amharic.
    var language: String?
    var emphasis: String?
    var fixedWords: [String]?
    /// The voice this voiceover was made with.
    var voiceId: String?
    /// The reading speed of the current audio: slow, normal or fast.
    var pace: String?
    /// Speeds already recorded for this script. Switching to one is free and instant.
    var pacesReady: [PaceTake]?
    /// Credits to record the script at a speed not yet made.
    var pacePrice: Double?
    /// Credits for one round of word fixes on this voiceover, from the server.
    var fixPrice: Double?
    /// When it finished, from the server. The audio is deleted 48 hours later.
    var finishedAt: String?

    var isEnglish: Bool { language == "en" }
    var isDone: Bool { status == "done" }
    var isFailed: Bool { status == "failed" }
    var isRunning: Bool { status == "running" }
    /// The customer's own script, as the server keeps it for display.
    var scriptText: String { (segments ?? []).joined(separator: " ") }
}

struct PaceTake: Codable, Equatable {
    let pace: String
    var audioSec: Double?
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

/// The server's answer after it checked an App Store purchase with Apple.
struct ApplePurchaseResult: Codable, Equatable {
    var ok: Bool?
    var creditsGranted: Double?
    var alreadyAdded: Bool?
    var creditsBalance: Double?
    var tier: String?
}

/// A promo video the customer sent (D-450), as the server reports it.
struct PromoSubmission: Codable, Equatable, Identifiable {
    let promoId: String
    var status: String
    var createdAt: String?
    var reviewedAt: String?
    var credits: Double?
    var reason: String?
    var link: String?
    /// Every post link sent for this video.
    var links: [String]?
    /// "TikTok", "Instagram"... from those links.
    var platforms: [String]?
    var durationSec: Double?

    var id: String { promoId }
    var allLinks: [String] { links ?? (link.map { [$0] } ?? []) }
}

/// What the account was given, bought and used (GET /credits/history).
struct CreditHistory: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var at: String
        /// "gift", "bought", "used" or "other".
        var kind: String
        var label: String
        /// Positive when credits came in, negative when they were used.
        var credits: Double
        var id: String { at + label + String(credits) }
    }
    var gifts: Double
    var bought: Double
    var used: Double
    var items: [Item]

    /// "+13" or "-2.5": the sign is always shown.
    static func signed(_ credits: Double) -> String {
        (credits > 0 ? "+" : "-") + Fmt.credits(abs(credits))
    }
}

struct PromoList: Codable, Equatable {
    var promos: [PromoSubmission]
    /// The full reward in credits (all four platforms), to show before sending.
    var reward: Double?
    /// Credits for each rewarded platform posted on.
    var perPlatform: Double?
    /// Most promo videos one account can send (rejected ones do not count).
    var maxVideos: Int?
    var videosLeft: Int?
}
