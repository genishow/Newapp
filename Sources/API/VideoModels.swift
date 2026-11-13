import Foundation

// Shapes for footage, music and the finished video. Same rules as Models.swift:
// snake_case keys arrive as camelCase and anything optional stays optional.

enum Shape: String, CaseIterable, Identifiable {
    case portrait, landscape
    var id: String { rawValue }
    var title: String { self == .portrait ? "Vertical 9:16" : "Horizontal 16:9" }
}

enum FootageSource: String, CaseIterable, Identifiable {
    case stock, mix, own
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stock: return "Stock"
        case .mix: return "Stock + mine"
        case .own: return "Only mine"
        }
    }
}

struct Candidate: Codable, Identifiable, Equatable {
    let clipId: Int
    var poster: String?
    var previewLink: String?
    var link: String?
    var duration: Double?
    var desc: String?
    var author: String?
    var ownUpload: Bool?

    var id: Int { clipId }
    var isOwn: Bool { ownUpload == true }
    var posterURL: URL? {
        guard let poster, poster.hasPrefix("http") else { return nil }
        return URL(string: poster)
    }
}

struct Beat: Codable, Identifiable, Equatable {
    let beat: Int
    var start: Double?
    var end: Double?
    var dur: Double?
    var says: String?
    var mustShow: String?
    var query: String?
    var type: String?
    var status: String?
    var candidates: [Candidate]?
    var exhausted: Bool?

    var id: Int { beat }
    /// Music breaks have no footage of their own to pick.
    var needsFootage: Bool { (type ?? "talk") != "gap" }
    /// The clip in use is always the first candidate.
    var chosen: Candidate? { candidates?.first }
    var isEmpty: Bool { needsFootage && chosen == nil }
}

struct PlanResult: Codable, Equatable {
    var planId: String?
    var beats: [Beat]?
    var creditsCharged: Double?
    var creditsBalance: Double?
}

struct PlanJob: Codable, Equatable {
    var status: String
    var error: String?
    var result: PlanResult?
}

struct StoredPlan: Codable, Equatable {
    var planId: String?
    var jobId: String?
    var orientation: String?
    var source: String?
    var beats: [Beat]?
}

struct PlanSubmit: Codable, Equatable {
    let jobId: String
    var status: String?
    var creditsEstimated: Double?
}

struct SearchResult: Codable, Equatable {
    var searched: Int?
    var remaining: Int?
    var gaps: [Int]?
    var beats: [Beat]?
    var retryAfter: Int?

    /// The stock libraries said "not now": nothing came back and work is left.
    var stockLimited: Bool {
        retryAfter != nil || ((searched ?? 0) == 0 && (remaining ?? 0) > 0)
    }
}

struct MatchResult: Codable, Equatable {
    var matched: Int?
    var pendingLabels: Int?
    var beats: [Beat]?
}

struct BeatsResult: Codable, Equatable {
    var beats: [Beat]?
}

struct UploadMeta: Codable, Identifiable, Equatable {
    let uploadId: String
    var name: String?
    var kind: String?
    var duration: Double?
    var labelStatus: String?

    var id: String { uploadId }
}

struct UploadList: Codable, Equatable {
    var uploads: [UploadMeta]
}

struct MusicTrack: Codable, Identifiable, Equatable {
    let trackId: String
    var kind: String?
    var title: String?

    var id: String { trackId }
}

struct MusicList: Codable, Equatable {
    var tracks: [MusicTrack]
}

struct AssembleSubmit: Codable, Equatable {
    let jobId: String
    var status: String?
    var creditsCharged: Double?
}

struct AssembleStatus: Codable, Equatable {
    var status: String
    var filesDone: Int?
    var filesTotal: Int?
    var durationSec: Double?
    var error: String?
    var previewUrl: String?
    var streamUrl: String?
    var downloadUrl: String?
    /// A sentence to show when some or all presenter appearances were dropped.
    var avatarSkipped: String?
    var avatarMode: String?
    /// True when the presenter was delivered as its own clip.
    var avatarFile: Bool?

    var isDone: Bool { status == "done" }
    var isOver: Bool { status == "done" || status == "failed" || status == "cancelled" }
    /// What the in-app player opens: the small copy when there is one.
    var playPath: String? { previewUrl ?? streamUrl }
}

struct StopResult: Codable, Equatable {
    var status: String?
    var creditsRefunded: Double?
}

struct VideoSummary: Codable, Identifiable, Equatable {
    let videoJobId: String
    var planId: String?
    var jobId: String?
    var orientation: String?
    var durationSec: Double?
    var finishedAt: String?
    var preview: String?

    var id: String { videoJobId }
}

struct VideoList: Codable, Equatable {
    var videos: [VideoSummary]
}

/// The rules for own footage, checked on the phone before uploading.
enum ClipRules {
    static let extensions: Set<String> = ["mp4", "mov", "m4v", "webm", "jpg", "jpeg", "png",
                                          "heic", "heif", "webp", "gif"]
    /// Each part of an upload. Small, so a phone never holds much in memory.
    static let chunkBytes = 16 * 1024 * 1024

    static func isAllowed(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static func partCount(bytes: Int) -> Int {
        max(1, Int((Double(bytes) / Double(chunkBytes)).rounded(.up)))
    }
}
