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

    /// Amharic letters per second of reading, and English words per second: the
    /// website's AM_CHARS_PER_SEC and its 2.2 (web/lib/create.ts), so both say the same.
    static let amharicLettersPerSecond = 7.17 * 0.97
    static let englishWordsPerSecond = 2.2

    /// The longest script, in seconds, that free credits can voice. Nil once paid.
    static func maxSeconds(trialMaxChars: Int?, language: Lang) -> Double? {
        guard let limit = trialMaxChars else { return nil }
        return language == .en ? Double(maxWordsEnglish) / englishWordsPerSecond
                               : Double(limit) / amharicLettersPerSecond
    }

    /// The same limit as it is said to the customer: a round length, at least 30 seconds.
    static func aboutSeconds(trialMaxChars: Int?, language: Lang) -> Int? {
        guard let max = maxSeconds(trialMaxChars: trialMaxChars, language: language) else { return nil }
        return Swift.max(30, Int((max / 30).rounded()) * 30)
    }

    /// The lengths the writer offers. On free credits only those it can voice, so a
    /// customer never pays to write a script the trial then refuses (as on the website).
    static func lengths(_ all: [Int], trialMaxChars: Int?, language: Lang) -> [Int] {
        guard let about = aboutSeconds(trialMaxChars: trialMaxChars, language: language) else { return all }
        let fit = all.filter { $0 <= about }
        return fit.isEmpty ? [all.first ?? 30] : fit
    }

    /// The length the writer is asked for. On free credits a little under the limit
    /// (93%), because a writer asked for exactly 260 words hands back 270 as often as 250.
    static func writerTarget(_ targetSec: Int?, trialMaxChars: Int?, language: Lang) -> Int? {
        guard let target = targetSec,
              let max = maxSeconds(trialMaxChars: trialMaxChars, language: language) else { return targetSec }
        return Swift.min(target, Int((max * 0.93).rounded(.down)))
    }

    /// The limit in the server's own unit: "260 English words", "900 Amharic characters".
    static func limitWords(trialMaxChars: Int?, language: Lang) -> String {
        language == .en ? "\(maxWordsEnglish) English words" : "\(trialMaxChars ?? 0) Amharic characters"
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

/// Close variations of a spelling the user typed, so typing gives a few readings to
/// compare, like "Say it myself" does. Holding a sound is written by doubling it
/// ("gebboch"), and the server reads ch, sh, zh, kh, ts, ny, gn, dj and t', k', p'
/// as one sound. Each variation holds or lets go of one sound (never the first),
/// spread across the word. Pairs are used when a word has too few sounds.
enum SpellingVariants {
    private static let digraphs = ["ch'", "ts'", "ch", "sh", "zh", "kh", "ts", "ny", "gn", "dj", "t'", "k'", "p'"]
    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u"]

    /// One sound and how many times it is written in a row.
    private struct Unit { var sound: String; var count: Int; var consonant: Bool }

    private static func units(_ text: String) -> [Unit] {
        var out: [Unit] = []
        var rest = Substring(text.lowercased())
        while let first = rest.first {
            let sound: String
            if let d = digraphs.first(where: { rest.hasPrefix($0) }) {
                sound = d
            } else {
                sound = String(first)
            }
            rest = rest.dropFirst(sound.count)
            let consonant = first.isLetter && !vowels.contains(first)
            if let last = out.last, last.sound == sound, consonant {
                out[out.count - 1].count += 1
            } else {
                out.append(Unit(sound: sound, count: 1, consonant: consonant))
            }
        }
        return out
    }

    private static func render(_ units: [Unit]) -> String {
        units.map { String(repeating: $0.sound, count: $0.count) }.joined()
    }

    static func make(_ typed: String, count: Int = 3) -> [String] {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, !text.contains(" "),
              text.unicodeScalars.allSatisfy({ $0.isASCII }) else { return [] }
        let parts = units(text)
        let spots = parts.indices.filter { $0 > 0 && parts[$0].consonant }
        func toggled(_ at: [Int]) -> String {
            var copy = parts
            for i in at { copy[i].count = copy[i].count > 1 ? 1 : 2 }
            return render(copy)
        }
        let original = render(parts)
        var singles: [String] = []
        for s in spots {
            let v = toggled([s])
            if v != original && !singles.contains(v) { singles.append(v) }
        }
        var picked: [String] = []
        if singles.count <= count {
            picked = singles
        } else {
            // Spread out: first, middle and last sound rather than three at the start.
            for k in 0..<count {
                let i = Int((Double(k) * Double(singles.count - 1) / Double(max(count - 1, 1))).rounded())
                if !picked.contains(singles[i]) { picked.append(singles[i]) }
            }
        }
        if picked.count < count {
            outer: for a in spots.indices {
                for b in spots.indices where b > a {
                    let v = toggled([spots[a], spots[b]])
                    if v != original && !picked.contains(v) { picked.append(v) }
                    if picked.count >= count { break outer }
                }
            }
        }
        return Array(picked.prefix(count))
    }
}

/// Is a reading a spoken word, or did the voice come out as just breathing? (Geni: "some
/// come out now audio just breathing".) Voiced sound repeats regularly, so it crosses zero
/// rarely; breath and hiss are noise and cross zero all the time. A reading counts as speech
/// when it has enough loud, voiced 20 ms windows. Kept generous, so a real word is never
/// hidden: only clearly empty or noise-only readings fail.
enum SpeechCheck {
    static func isSpeech(_ samples: [Float], sampleRate: Double,
                         minVoicedSeconds: Double = 0.12) -> Bool {
        let window = max(1, Int(sampleRate * 0.02))
        guard samples.count >= window * 3 else { return false }
        var rms: [Float] = []
        var zcr: [Float] = []
        var start = 0
        while start + window <= samples.count {
            var sum: Float = 0
            var crossings = 0
            for i in start..<(start + window) {
                let v = samples[i]
                sum += v * v
                if i > start && (samples[i - 1] < 0) != (v < 0) { crossings += 1 }
            }
            rms.append((sum / Float(window)).squareRoot())
            zcr.append(Float(crossings) / Float(window))
            start += window
        }
        let peak = rms.max() ?? 0
        guard peak >= 0.01 else { return false }                  // silence
        var voiced = 0
        for (r, z) in zip(rms, zcr) where r >= peak * 0.3 && z < 0.2 { voiced += 1 }
        return Double(voiced) * 0.02 >= minVoicedSeconds
    }
}
