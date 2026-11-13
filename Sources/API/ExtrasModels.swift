import Foundation

/// The language of a project: what the script is written in and the voice reads.
enum Lang: String, CaseIterable, Identifiable {
    case am, en
    var id: String { rawValue }
    var title: String { self == .am ? "Amharic" : "English" }
}

/// How Kinbir should write or change a script.
struct ScriptOptions: Equatable {
    var language: Lang = .am
    /// Wanted length in seconds. The server accepts 15 to 600.
    var targetSec: Int?
    /// When set, the current script is changed as asked and not rebuilt.
    var refineInstruction: String?
    /// The text is an idea, not source material: Kinbir writes the whole script from it.
    var fromIdea = false
    /// Keep the source's own order and wording, as the website's "Faithful mode" does.
    var faithful = false

    static let lengths: [Int] = [15, 30, 45, 60, 90, 120, 180, 240, 300, 420, 600]

    /// The request fields beyond `text`.
    var fields: [String: Any] {
        var f: [String: Any] = [:]
        if language == .en { f["language"] = "en" }
        if let instruction = refineInstruction, !instruction.isEmpty {
            f["mode"] = "refine"
            f["instruction"] = instruction
            f["effort"] = "medium"
        } else {
            if fromIdea {
                f["mode"] = "brief"
                f["effort"] = "medium"
            } else if faithful {
                f["mode"] = "faithful"
            }
            if let targetSec { f["target_sec"] = min(600, max(15, targetSec)) }
        }
        return f
    }
}

/// English reading settings. Amharic has none.
struct VoiceOptions: Equatable {
    static let paces = ["slow", "normal", "fast"]
    static let emphases = ["none", "punchy", "strong"]

    var language: Lang = .am
    var pace = "normal"
    var emphasis = "none"

    var fields: [String: Any] {
        guard language == .en else { return [:] }
        return ["language": "en", "pace": pace, "emphasis": emphasis]
    }
}

struct FixOption: Codable, Identifiable, Equatable {
    let optionId: Int
    var label: String?
    var id: Int { optionId }
}

struct FixCandidates: Codable, Equatable {
    var options: [FixOption]?
}

struct FixPreview: Codable, Equatable {
    let previewId: String
    var status: String
    /// True when nobody has ever heard this spelling, so it is being made from scratch.
    var firstEver: Bool?
    var isDone: Bool { status == "done" }
    var isFailed: Bool { status == "failed" }
}

/// One correction. Either a word with a chosen or typed reading, or a sentence to read again.
enum FixEdit: Equatable, Identifiable {
    case option(word: String, optionId: Int)
    case custom(word: String, spelling: String)
    /// Record this part of the script again, words unchanged.
    case rereadSentence(segment: Int)
    /// Record this part of the script again with new words.
    case editSentence(segment: Int, text: String)

    var payload: [String: Any] {
        switch self {
        case .option(let word, let optionId): return ["word": word, "option_id": optionId]
        case .custom(let word, let spelling): return ["word": word, "custom": spelling]
        case .rereadSentence(let segment): return ["segment": segment]
        case .editSentence(let segment, let text): return ["segment": segment, "text": text]
        }
    }

    /// One fix per word and one per sentence: a newer choice replaces the older one.
    var id: String {
        switch self {
        case .option(let word, _), .custom(let word, _): return "w:" + word
        case .rereadSentence(let segment), .editSentence(let segment, _): return "s:\(segment)"
        }
    }

    /// The website allows this many changes in one go.
    static let maxPerBatch = 25
}

struct SavedScript: Codable, Identifiable, Equatable {
    let jobId: String
    var createdAt: String?
    var text: String?
    var preview: String?

    var id: String { jobId }
    var body: String { text ?? preview ?? "" }
}

struct SavedScripts: Codable, Equatable {
    var scripts: [SavedScript]
}

struct FixBatch: Codable, Equatable {
    var batchId: String?
    var status: String
    var error: String?
    var isOver: Bool { status == "done" || status == "failed" || status == "cancelled" }
}

struct TranscribeResult: Codable, Equatable {
    var text: String?
}

struct ScriptRulesResult: Codable, Equatable {
    var scriptRules: String?
}

/// Splits a sentence into the words a user can tap, keeping punctuation attached for display.
enum Words {
    struct Token: Identifiable, Equatable {
        let id: Int
        let shown: String
        /// The word without punctuation, as the server wants it. Empty when not fixable.
        let word: String
    }

    static func tokens(in sentence: String, startingAt offset: Int = 0) -> [Token] {
        sentence.split(whereSeparator: { $0.isWhitespace }).enumerated().map { index, piece in
            let shown = String(piece)
            let scalars = shown.unicodeScalars.filter { $0.value >= 0x1200 && $0.value <= 0x135A }
            return Token(id: offset + index, shown: shown, word: String(String.UnicodeScalarView(scalars)))
        }
    }
}
