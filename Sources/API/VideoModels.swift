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

/// The website's render choices beyond music and captions.
struct RenderOptions: Equatable {
    static let qualities = ["1080p", "4k", "8k"]
    static let musicLevels: [(id: String, title: String)] = [
        ("subtle", "Quiet"), ("balanced", "Normal"), ("prominent", "Loud"),
    ]
    static let fonts: [(id: String, title: String)] = [("standard", "Standard"), ("serif", "Serif")]
    static let colors = ["gold", "blue", "red", "green", "purple", "white"]
    static let shotLengths: [(id: String, title: String)] = [
        ("auto", "Same as before"), ("quick", "Quick 2s"), ("normal", "Normal 3s"),
        ("relaxed", "Relaxed 5s"), ("calm", "Calm 7s"), ("mixed", "Mixed"), ("smart", "Smart mix"),
    ]

    /// The website's default is 4K.
    var quality = "4k"
    var musicLevel = "balanced"
    var captionFont = "standard"
    var graphics = false
    var graphicsColor = "gold"
    var logo = LogoChoice()
    /// False leaves the planned music breaks out of the video.
    var includeBreaks = true
    /// Claude plans camera moves, shot entries and caption highlights (D-448).
    var smartEdit = true

    /// What is added to the render request.
    func payload(music: Bool, captions: Bool) -> [String: Any] {
        var body: [String: Any] = ["quality": quality, "smart_edit": smartEdit]
        if music { body["music_level"] = musicLevel }
        if captions { body["caption_font"] = captionFont }
        if graphics {
            body["graphics"] = true
            body["graphics_color"] = graphicsColor
        }
        if logo.enabled { body["logo"] = logo.payload }
        if !includeBreaks { body["gaps_enabled"] = false }
        return body
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
    var width: Int?
    var height: Int?
    /// True when nothing was found in the asked shape, so the other shape was offered.
    var shapeFallback: Bool?
    /// "still" for a picture, "video" for a clip.
    var kind: String?
    /// Own clips only: a signed address of a frame of the clip, and of the clip itself.
    /// Both are paths on the Kinbir server, not full links.
    var posterUrl: String?
    var streamUrl: String?

    var id: Int { clipId }
    /// Whether the clip has the video's shape. A clip with no size given counts as fitting.
    func fits(_ shape: Shape) -> Bool {
        guard let width, let height, width > 0, height > 0 else { return shapeFallback != true }
        return shape == .portrait ? height > width : width >= height
    }
    /// "9:16" or "16:9", when the size is known.
    /// Width ÷ height, when the clip's size is known.
    var aspectRatio: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return Double(width) / Double(height)
    }

    var aspectLabel: String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return height > width ? "9:16" : "16:9"
    }
    var isOwn: Bool { ownUpload == true }
    /// The small picture. Own clips have theirs on the Kinbir server (Geni saw only a
    /// film icon on her own clips before, 2026-11-15).
    var posterURL: URL? {
        if let own = Candidate.serverURL(posterUrl) { return own }
        guard let poster, poster.hasPrefix("http") else { return nil }
        return URL(string: poster)
    }
    /// What the big preview shows: the clip, or the picture for a still.
    var previewURL: URL? {
        if let own = Candidate.serverURL(streamUrl) { return own }
        if let previewLink, previewLink.hasPrefix("http") { return URL(string: previewLink) }
        if isStill { return posterURL }
        return nil
    }
    /// A picture, not a clip: shown as an image, never in a video player.
    var isStill: Bool {
        if kind == "still" { return true }
        if kind == "video" { return false }
        let path = (previewLink ?? link ?? "").lowercased()
        let clean = path.split(separator: "?").first.map(String.init) ?? path
        return Candidate.imageEndings.contains { clean.hasSuffix($0) }
    }

    static let imageEndings = [".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".bmp", ".tif", ".tiff"]

    /// A path the server signed, made into a full link. Full links pass through.
    static func serverURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        guard path.hasPrefix("/") else { return nil }
        return URL(string: RequestBuilder.defaultBase.absoluteString + path)
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
    /// "Place all my clips": how many were placed, and a sentence about the rest.
    var placed: Int?
    var note: String?
}

struct BeatsResult: Codable, Equatable {
    var beats: [Beat]?
}

/// The answer to setting how long one shot plays. The next shots change too.
struct StretchResult: Codable, Equatable {
    var beats: [Beat]?
    /// The length the shot really got. It can be less than asked.
    var durSec: Double?
    var note: String?
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
    var orientation: String?
    var avatarSkipped: String?
    var avatarMode: String?
    /// True when the presenter was delivered as its own clip.
    var avatarFile: Bool?
    /// When it finished, from the server. The file is deleted 48 hours later.
    var finishedAt: String?

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
    /// One video may be at most 10 minutes long. The server says the same.
    static let maxSeconds: Double = 600
    /// The shortest a shot can be made when another shot gets longer.
    static let minShotSeconds: Double = 1.5

    static func isTooLong(seconds: Double) -> Bool { seconds > maxSeconds + 0.5 }

    /// How many own clips to suggest for a video with this many shots.
    /// 14 shots gives 5 to 15.
    static func suggestedClips(shots: Int) -> (low: Int, high: Int) {
        let count = max(1, shots)
        let low = max(1, Int((Double(count) / 3).rounded(.up)))
        let high = max(low, Int((Double(count) / 5).rounded(.up)) * 5)
        return (low, high)
    }

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

/// What the Library shows: items from the last 48 hours only (D-458).
struct LibraryCache: Codable, Equatable {
    var jobs: [JobSummary]
    var videos: [VideoSummary]

    static let keptHours: Double = 48

    /// Drops anything past 48 hours. Still being made counts as fresh.
    func fresh(now: Date = Date()) -> LibraryCache {
        func ok(_ iso: String?) -> Bool {
            guard let made = Fmt.date(fromServer: iso) else { return true }
            return now.timeIntervalSince(made) < Self.keptHours * 3600
        }
        return LibraryCache(jobs: jobs.filter { ok($0.finishedAt ?? $0.createdAt) },
                            videos: videos.filter { ok($0.finishedAt) })
    }
}
