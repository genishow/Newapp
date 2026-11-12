import Foundation

enum Fmt {
    /// 12 -> "12", 2.5 -> "2.5", 17.56 -> "17.6"
    static func credits(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }

    /// 75 -> "1:15"
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 75 -> "1 min 15 sec", 20 -> "20 sec"
    static func length(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) sec" }
        let s = total % 60
        return s == 0 ? "\(total / 60) min" : "\(total / 60) min \(s) sec"
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(fromServer iso: String?) -> Date? {
        guard let iso, iso.count >= 19 else { return nil }
        // The server writes "2026-11-12T10:00:00Z", sometimes with fractions or no Z.
        return isoParser.date(from: String(iso.prefix(19)) + "Z")
    }

    static func ago(_ iso: String?, now: Date = Date()) -> String {
        guard let date = date(fromServer: iso) else { return "" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h ago" }
        return "\(Int(seconds / 86_400)) d ago"
    }

    /// A stable short tag for an access code, used to key the saved draft.
    static func ownerTag(_ code: String) -> String {
        var h: UInt32 = 5381
        for byte in code.utf8 { h = (h &* 33) &+ UInt32(byte) }
        return String(h, radix: 36)
    }
}
