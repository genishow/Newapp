import Foundation

/// What the script box currently holds. It decides what the main button does.
enum TextKind: Equatable {
    case empty
    case link
    case english
    case amharic

    static func detect(_ raw: String) -> TextKind {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .empty }
        if isLink(text) { return .link }

        var ethiopic = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if isEthiopic(scalar) {
                ethiopic += 1
            } else if (scalar.value >= 0x41 && scalar.value <= 0x5A)
                        || (scalar.value >= 0x61 && scalar.value <= 0x7A) {
                latin += 1
            }
        }
        if ethiopic == 0 && latin == 0 { return .amharic }   // digits or punctuation only
        // Mostly Ethiopic letters means the script is ready for the voice.
        return Double(ethiopic) >= Double(ethiopic + latin) * 0.5 ? .amharic : .english
    }

    /// One web address and nothing else.
    static func isLink(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: { $0.isWhitespace }) else { return false }
        let lower = t.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return false }
        guard let url = URL(string: t), let host = url.host else { return false }
        return host.contains(".")
    }

    static func isEthiopic(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 0x1200 && scalar.value <= 0x137F)
            || (scalar.value >= 0x1380 && scalar.value <= 0x139F)
            || (scalar.value >= 0x2D80 && scalar.value <= 0x2DDF)
    }

    /// Ethiopic letters only, the way the server counts the free-trial limit.
    static func ethiopicLetterCount(_ text: String) -> Int {
        text.unicodeScalars.filter { $0.value >= 0x1200 && $0.value <= 0x135A }.count
    }
}

/// The rules the server applies to an enrollment video, checked on the phone first
/// so nobody waits for an upload that will be refused.
enum EnrollRules {
    static let minSeconds = 10.0
    static let maxSeconds = 40.0
    static let maxBytes = 60 * 1024 * 1024

    static func problem(seconds: Double, bytes: Int) -> String? {
        if seconds < minSeconds {
            return "That video is too short. Read for at least 10 seconds."
        }
        if seconds > maxSeconds {
            return "That video is too long. Keep it under 40 seconds."
        }
        if bytes > maxBytes {
            return "That video file is too large. Record a shorter one."
        }
        return nil
    }
}

enum EmailRules {
    static func looksValid(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.contains(where: { $0.isWhitespace }) else { return false }
        let parts = s.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        guard let dot = domain.lastIndex(of: "."), dot != domain.startIndex else { return false }
        return domain.index(after: dot) != domain.endIndex
    }
}
