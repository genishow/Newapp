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
    /// The server keeps appearances at least this far apart (MID_MIN_GAP_SEC).
    static let minGapSeconds = 20.0
    /// The most middle appearances the server takes (MID_MAX).
    static let maxMiddles = 40
    /// One appearance is 3 to 14 seconds.
    static let minSeconds = 3
    static let maxSeconds = 14

    var enabled = false
    /// The length an appearance uses until it is given its own.
    var seconds = 14
    var atStart = true
    var atEnd = false
    var wholeVideo = false
    var mode: Mode = .inVideo
    /// Own lengths for the start and the end. Nil follows `seconds`.
    var startSeconds: Int?
    var endSeconds: Int?
    /// One length per middle appearance. The count is how many there are.
    var middles: [Int] = []

    /// The `avatar` object the server expects, the same fields the website sends.
    var payload: [String: Any] {
        var placements: [String: Any] = [
            "start": atStart, "end": atEnd, "middle": middles.count, "full": wholeVideo,
        ]
        if let startSeconds { placements["start_sec"] = startSeconds }
        if let endSeconds { placements["end_sec"] = endSeconds }
        if !middles.isEmpty { placements["middles"] = Array(middles.prefix(AvatarChoice.maxMiddles)) }
        return ["enabled": true, "seconds": seconds, "mode": mode.rawValue, "placements": placements]
    }

    /// Changes how many middle appearances there are. New ones start at the usual length.
    mutating func setMiddleCount(_ count: Int) {
        let want = max(0, min(AvatarChoice.maxMiddles, count))
        if want < middles.count {
            middles = Array(middles.prefix(want))
        } else {
            while middles.count < want { middles.append(seconds) }
        }
    }

    /// The server's own clamp for one appearance (clamp_hook_sec): 3 to 14 seconds,
    /// and never longer than the voiceover.
    static func clamp(_ value: Int, audioSec: Double) -> Int {
        let capped = max(minSeconds, min(value, maxSeconds))
        return max(1, min(capped, Int(audioSec.rounded(.down))))
    }

    /// Seconds of presenter the server will make for a voiceover this long, whatever the
    /// on/off switch says. The same counting as the website's quote.
    func fitSeconds(audioSec: Double) -> Double {
        guard audioSec > 0 else { return 0 }
        if wholeVideo {
            var t = 0.0
            var total = 0.0
            while t < audioSec - 1 {
                var sec = min(14, audioSec - t).rounded(.down)
                let after = audioSec - t - sec
                // A leftover of 1 to 2 seconds borrows a second so it can still be made.
                if sec == 14 && after >= 1 && after < 2 { sec -= 1 }
                if sec < 2 { break }
                total += sec
                t += sec
            }
            return total
        }
        var placed: [(start: Double, sec: Double)] = []
        func fits(_ t0: Double, _ sec: Double) -> Bool {
            guard t0 >= 0, t0 + sec <= audioSec + 0.01 else { return false }
            return placed.allSatisfy { other in
                t0 >= other.start + other.sec + AvatarChoice.minGapSeconds
                    || t0 + sec + AvatarChoice.minGapSeconds <= other.start
            }
        }
        if atStart {
            placed.append((0, Double(AvatarChoice.clamp(startSeconds ?? seconds, audioSec: audioSec))))
        }
        if atEnd {
            let sec = Double(AvatarChoice.clamp(endSeconds ?? seconds, audioSec: audioSec))
            let t0 = audioSec - sec
            if fits(t0, sec) { placed.append((t0, sec)) }
        }
        let list = middles.prefix(AvatarChoice.maxMiddles).map {
            Double(AvatarChoice.clamp($0, audioSec: audioSec))
        }
        for (i, sec) in list.enumerated() {
            let t0 = audioSec * Double(i + 1) / Double(list.count + 1)
            if fits(t0, sec) { placed.append((t0, sec)) }
        }
        return placed.reduce(0) { $0 + $1.sec }
    }

    /// Seconds of presenter the server will try to make for a voiceover this long.
    func totalSeconds(audioSec: Double) -> Double {
        guard enabled else { return 0 }
        return fitSeconds(audioSec: audioSec)
    }

    /// Whether an end appearance fits next to the start one.
    func endFits(audioSec: Double) -> Bool {
        var probe = AvatarChoice()
        probe.seconds = seconds
        probe.atStart = atStart
        probe.atEnd = true
        return probe.fitSeconds(audioSec: audioSec) > (atStart ? Double(seconds) : 0)
    }

    private func withMiddles(_ list: [Int]) -> AvatarChoice {
        var copy = self
        copy.wholeVideo = false
        copy.middles = list
        return copy
    }

    /// Whether even one middle appearance fits between the others.
    func middleFits(audioSec: Double) -> Bool {
        withMiddles([seconds]).fitSeconds(audioSec: audioSec)
            > withMiddles([]).fitSeconds(audioSec: audioSec)
    }

    /// How many of the asked-for middle appearances really land. The rest are not charged.
    func middlesThatFit(audioSec: Double) -> Int {
        let none = withMiddles([]).fitSeconds(audioSec: audioSec)
        let list = Array(middles.prefix(AvatarChoice.maxMiddles))
        var count = 0
        for k in stride(from: 1, through: list.count, by: 1) {
            let want = Array(list.prefix(k))
            let got = withMiddles(want).fitSeconds(audioSec: audioSec)
            if got - none < Double(want.reduce(0, +)) { break }
            count = k
        }
        return count
    }

    /// The same formula the server charges with (api/avatar.py). `fullFrame` is true when
    /// the photo and the video have the same shape, which costs four times as much.
    /// The dollars are rounded to six places first, as the server does.
    static func credits(seconds: Double, fullFrame: Bool) -> Double {
        guard seconds > 0 else { return 0 }
        let rate = fullFrame ? 0.06 : 0.015
        let usd = (seconds * rate * 1e6).rounded() / 1e6
        let raw = usd * 4 / 0.155
        return max(0.5, (raw * 2).rounded(.up) / 2)
    }
}

/// The one part of `GET /assemble/{id}` that lists the presenter clips of a
/// "separate file" video: a start time and a length for each.
struct AvatarClipList: Codable, Equatable {
    var avatarFiles: [[Double]]?

    var clips: [[Double]] { avatarFiles ?? [] }

    /// Clip 1 keeps the old address. Later clips carry their number.
    static func path(videoJobId: String, index: Int) -> String {
        index > 1 ? "/assemble/\(videoJobId)/avatar-\(index).mp4" : "/assemble/\(videoJobId)/avatar.mp4"
    }
}
