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

    /// Hours until the server deletes something made at `iso`. Nil when unknown or gone.
    static func hoursLeft(_ iso: String?, keptHours: Double = 48, now: Date = Date()) -> Int? {
        guard let made = date(fromServer: iso) else { return nil }
        let left = keptHours * 3600 - now.timeIntervalSince(made)
        return left > 0 ? max(1, Int((left / 3600).rounded(.up))) : nil
    }

    /// A stable short tag for an access code, used to key the saved draft.
    static func ownerTag(_ code: String) -> String {
        var h: UInt32 = 5381
        for byte in code.utf8 { h = (h &* 33) &+ UInt32(byte) }
        return String(h, radix: 36)
    }
}

/// What a saved file is called: "Kinbir - " and the first few words of its
/// script, so videos and voiceovers are easy to find in Files and Photos.
enum SaveName {
    static let maxWords = 5
    static let maxChars = 40

    static func base(script: String?) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|\n\r\t")
        let cleaned = (script ?? "").components(separatedBy: bad).joined(separator: " ")
        var words: [String] = []
        var length = 0
        for word in cleaned.split(whereSeparator: { $0 == " " }).map(String.init) {
            if words.count == maxWords || length + word.count > maxChars { break }
            words.append(word)
            length += word.count + 1
        }
        // a word longer than the limit still gives a name, just cut short
        if words.isEmpty, let first = cleaned.split(separator: " ").first {
            words = [String(first.prefix(maxChars))]
        }
        let ending = CharacterSet(charactersIn: ".,!…።፣፤፥፦፧፨ ").union(.whitespaces)
        let head = words.joined(separator: " ").trimmingCharacters(in: ending)
        return head.isEmpty ? "Kinbir" : "Kinbir - " + head
    }

    /// A copy of `file` under the friendly name, in its own folder so two
    /// items with the same first words never overwrite each other.
    static func renamed(_ file: URL, script: String?) -> URL {
        let folder = TempFiles.folder.appendingPathComponent("named-" + file.deletingPathExtension().lastPathComponent,
                                                             isDirectory: true)
        let target = folder.appendingPathComponent(base(script: script))
            .appendingPathExtension(file.pathExtension)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: file, to: target)
            return target
        } catch {
            return file
        }
    }
}

/// What one App Store purchase came to once the server had seen it.
enum PurchaseOutcome: Equatable {
    case confirmed            // the server has it; credits are on the account
    case later                // could not reach the server; it is sent again
    case refused(String)      // the server will never accept it, and says why
    case unverified           // Apple's own check failed

    /// The sentence after Restore. A refusal is said in the server's words, and
    /// "up to date" is only said when the server really confirmed something.
    static func restoreMessage(_ outcomes: [PurchaseOutcome]) -> String {
        for case .refused(let why) in outcomes { return why }
        if outcomes.contains(.later) {
            return T("Could not reach Kinbir to check your purchases. Try again in a moment.")
        }
        if outcomes.contains(.confirmed) { return T("Your purchases are up to date.") }
        return T("No purchases found for this Apple ID.")
    }

    /// Answers that will not change on a retry: not a Kinbir product (400), a test
    /// purchase (403), or one that belongs to another account or was refunded (409).
    static func isFinal(status: Int) -> Bool { [400, 403, 409].contains(status) }
}
