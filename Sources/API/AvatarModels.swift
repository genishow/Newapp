import Foundation

struct AvatarInfo: Codable, Equatable {
    var hasPhoto: Bool?
    var verified: Bool?

    /// Only a verified photo can be used in a video.
    var isReady: Bool { hasPhoto == true && verified == true }
}

/// What the user picked for the talking presenter. Sent inside `/assemble`.
struct AvatarChoice: Equatable {
    enum Mode: String, CaseIterable, Identifiable {
        case inVideo = "in_video"
        case separate
        var id: String { rawValue }
        var title: String { self == .inVideo ? "In the video" : "Separate file" }
    }

    static let lengths = [5, 8, 10, 14]
    /// The server keeps appearances at least this far apart.
    static let minGapSeconds = 20.0

    var enabled = false
    var seconds = 14
    var atStart = true
    var atEnd = false
    var wholeVideo = false
    var mode: Mode = .inVideo

    /// The `avatar` object the server expects.
    var payload: [String: Any] {
        ["enabled": true, "seconds": seconds, "mode": mode.rawValue,
         "placements": ["start": atStart, "end": atEnd, "middle": 0, "full": wholeVideo]]
    }

    /// Seconds of presenter the server will try to make for a voiceover this long.
    func totalSeconds(audioSec: Double) -> Double {
        guard enabled, audioSec > 0 else { return 0 }
        if wholeVideo { return audioSec }
        let each = min(Double(seconds), audioSec)
        var total = 0.0
        if atStart { total += each }
        // The end appearance only fits when it sits far enough from the start one.
        if atEnd && (!atStart || audioSec - 2 * each >= AvatarChoice.minGapSeconds) { total += each }
        return total
    }

    /// The same formula the server charges with (api/avatar.py). `fullFrame` is true when
    /// the photo and the video have the same shape, which costs four times as much.
    static func credits(seconds: Double, fullFrame: Bool) -> Double {
        guard seconds > 0 else { return 0 }
        let rate = fullFrame ? 0.06 : 0.015
        let raw = seconds * rate * 4 / 0.155
        return max(0.5, (raw * 2).rounded(.up) / 2)
    }
}
