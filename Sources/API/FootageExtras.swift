import Foundation

// The website's whole-plan footage tools and finishing extras.

/// Music breaks chosen at planning: none, let Kinbir decide, or a set number.
struct MusicBreaks: Equatable {
    static let choices: [(id: String, title: String)] =
        [("none", "None"), ("auto", "Auto")] + (1...8).map { ("\($0)", "\($0)") }

    var choice = "none"

    var payload: [String: Any] {
        if choice == "none" || choice == "auto" { return ["mode": choice] }
        return ["mode": "count", "count": Int(choice) ?? 1]
    }
}

/// Your logo in a corner of the video.
struct LogoChoice: Equatable {
    static let corners: [(id: String, title: String)] = [
        ("tl", "Top left"), ("tr", "Top right"), ("bl", "Bottom left"), ("br", "Bottom right"),
    ]
    var enabled = false
    var corner = "tr"
    /// Width as a share of the video, 5 to 30 percent.
    var scale = 12

    var payload: [String: Any] {
        ["enabled": true, "corner": corner, "scale": min(30, max(5, scale))]
    }
}

struct LogoStatus: Codable, Equatable {
    var hasLogo: Bool?
}

/// A shot whose footage does not seem to match its words (the free check).
struct Mismatch: Codable, Equatable, Identifiable {
    let beat: Int
    var line: String?
    var id: Int { beat }
}

struct FootageCheckResult: Codable, Equatable {
    var scanned: Int?
    var mismatched: [Mismatch]?
    var note: String?
}

struct FootageCheckJob: Codable, Equatable {
    var status: String
    var error: String?
    var result: FootageCheckResult?
    // The server puts the answer at the top level of the job, not under "result".
    var scanned: Int?
    var mismatched: [Mismatch]?
    var note: String?

    /// The shots that may not match, wherever the server put them.
    var wrongShots: [Mismatch] { mismatched ?? result?.mismatched ?? [] }
}

/// The answer to "find footage for the empty shots". There is no job to wait for when
/// nothing can be searched, for example on an "Only mine" plan: then `note` says why.
struct AutofillSubmit: Codable, Equatable {
    var jobId: String?
    var status: String?
    var note: String?
}

/// One verdict from the paid check: "yes", "weak" or "no", and why.
struct ShotVerdict: Codable, Equatable, Identifiable {
    let beat: Int
    var verdict: String?
    var why: String?
    var id: Int { beat }
}

struct VerifyResult: Codable, Equatable {
    var checks: [ShotVerdict]?
    var autoReplaced: [Int]?
    var flagged: Int?
    var beats: [Beat]?
    var creditsCharged: Double?
    var note: String?

    /// The website's quote: 2 credits, or one per 30 shots when that is more.
    static func credits(shots: Int) -> Int {
        max(2, Int((Double(shots) / 30).rounded(.up)))
    }
}

struct SourceResult: Codable, Equatable {
    var ok: Bool?
    var source: String?
}
