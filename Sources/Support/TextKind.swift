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

/// The no-account demo on the first screen. The server is the authority; these mirror its
/// limits so the screen can say "too long" before the refusal.
enum DemoRules {
    /// The server's raw size wall (DEMO_MAX_CHARS).
    static let maxChars = 600
    /// Typed Amharic is capped by Ethiopic syllables (DEMO_MAX_SYL), about 15 seconds.
    static let maxSyllables = 120
    /// Typed English is capped by words (DEMO_MAX_WORDS_EN).
    static let maxWordsEnglish = 40

    /// The official samples. They must stay letter for letter what the server holds:
    /// it only lets these two run past the caps.
    static let sampleAmharic = "በቅንብር ዌብሳይት ተጠቅማችሁ ፅሁፋችሁን በዚህ መልኩ በኤአይ ማስነበብ ትችላላችሁ። ድምፁ የእናንተን እንዲመስል አካውንት ከፍታችሁ ድምፃችሁን መቅዳት ወይንም ክሎን ማድረግ ይኖርባችኋል። ድምፃችሁን ክሎን ካደረጋችሁ በህዋላ፣ ፅሁፋችሁን በራሳችሁ ድምፅ ማግኘት ትችላላችሁ። ቅንብር የሚለየውም የቪዲዮአችሁን ፅሁፍ ፅፎ፣ በድምፃችሁ አንብቦ፣ ቪዲዮን ካብሽንን ሙዚቃን እና አቫተርን አቀናብሮ ለሶሻል ሚዲያችሁ ፖስት ለመደረግ ዝግጁ የሆነ ቪዲዮዎችን በመስጠቱ ነው። በሶሻል ሚዲያ ገንዘብ ለመስራት አሁኑኑ በነፃ ይሞክሩት።"
    static let sampleEnglish = "This is the Kinbir voice, reading in English. Type your script, or describe your idea and Kinbir writes it for you. Clone your own voice in about two minutes, and every video you make speaks as you. Music, captions, footage, one finished video, ready to post. Try it free."

    /// Ethiopic syllable letters, ሀ to ፚ, as the website counts them.
    static func syllables(_ text: String) -> Int {
        text.unicodeScalars.filter { $0.value >= 0x1200 && $0.value <= 0x135A }.count
    }

    static func words(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// No Ethiopic at all plus some Latin letters.
    static func looksEnglish(_ text: String) -> Bool {
        syllables(text) == 0 && text.unicodeScalars.contains {
            ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A)
        }
    }

    /// Too long for the demo. The two official samples never are.
    static func isOver(_ text: String) -> Bool {
        if looksEnglish(text) {
            return text != sampleEnglish && words(text) > maxWordsEnglish
        }
        return text != sampleAmharic && syllables(text) > maxSyllables
    }

    /// The small line under the field, with the website's wording.
    static func meta(_ text: String) -> String {
        if isOver(text) {
            return "The demo reads about 15 seconds. Trim it, or sign up free for full scripts"
        }
        if text == sampleAmharic { return "the full Kinbir story · ≈ 36s" }
        if text == sampleEnglish { return "the Kinbir story in English · ≈ 20s" }
        if looksEnglish(text) {
            return "≈ \(Int((Double(words(text)) / 2.5).rounded()))s of the ~15s demo"
        }
        let syl = syllables(text)
        if syl == 0 { return "free · your own text up to ~15 seconds, or a full sample" }
        return "≈ \(Int((Double(syl) / 7.17).rounded()))s of the ~15s demo"
    }
}

/// Reading time and voiceover price, by the website's own formulas (studio page).
enum ScriptMath {
    /// English: 2.2 words a second. Amharic: syllables / 7.87 * 1.12.
    static func seconds(_ script: String, language: Lang) -> Double {
        if language == .en {
            let words = script.split(whereSeparator: { $0.isWhitespace }).count
            return words > 0 ? Double(words) / 2.2 : 0
        }
        let syllables = TextKind.ethiopicLetterCount(script)
        return syllables > 0 ? Double(syllables) / 7.87 * 1.12 : 0
    }

    /// The server's estimate: engine time at 5.3 times the audio, plus overhead, times
    /// four, in half credits, never under half a credit. The real charge follows the job.
    static func voiceCredits(seconds: Double) -> Double {
        guard seconds > 0 else { return 1 }
        let cost = seconds * 5.3 * 0.000164 + 0.03
        return max(0.5, (cost * 4 / 0.155 * 2).rounded(.up) / 2)
    }

    /// What is left after this voiceover, to one decimal and never under zero.
    static func balanceAfter(balance: Double, credits: Double) -> Double {
        max(0, ((balance - credits) * 10).rounded() / 10)
    }
}

/// The free trial voices a limited script at a time. `trialMaxChars` is nil once the
/// account has paid, and then there is no limit here.
enum TrialRule {
    /// The English cap, in words (EN_TRIAL_MAX_WORDS on the server and the website).
    static let maxWordsEnglish = 260

    static func words(_ script: String) -> Int {
        script.split(whereSeparator: { $0.isWhitespace }).count
    }

    static func isOver(_ script: String, language: Lang, trialMaxChars: Int?) -> Bool {
        guard let limit = trialMaxChars else { return false }
        if language == .en { return words(script) > maxWordsEnglish }
        return TextKind.ethiopicLetterCount(script) > limit
    }

    /// The website's sentence for a script over the trial limit. Nil when it fits.
    static func problem(_ script: String, language: Lang, trialMaxChars: Int?) -> String? {
        guard let limit = trialMaxChars,
              isOver(script, language: language, trialMaxChars: trialMaxChars) else { return nil }
        if language == .en {
            return "Your free credits voice up to \(maxWordsEnglish) English words at a time, about two minutes. This script is \(words(script)). Split it into two, or pick a plan for full-length scripts."
        }
        return "Your free credits voice up to \(limit) Amharic characters at a time, about two minutes. This script is \(TextKind.ethiopicLetterCount(script)). Split it into two, or pick a plan for full-length scripts."
    }
}
