import Foundation

/// The language of a project: what the script is written in and the voice reads.
enum Lang: String, CaseIterable, Identifiable {
    case am, en
    var id: String { rawValue }
    var title: String { self == .am ? "Amharic" : "English" }

    /// The voiceover language a new user starts with. Kinbir is Amharic first.
    static var matchingInterface: Lang { .am }
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
    /// Record one clause again, words unchanged. A clause ends at ፣ or ።.
    case rereadPart(segment: Int, part: Int)
    /// Record one clause again with new words.
    case editPart(segment: Int, part: Int, text: String)

    var payload: [String: Any] {
        switch self {
        case .option(let word, let optionId): return ["word": word, "option_id": optionId]
        case .custom(let word, let spelling): return ["word": word, "custom": spelling]
        case .rereadSentence(let segment): return ["segment": segment]
        case .editSentence(let segment, let text): return ["segment": segment, "text": text]
        case .rereadPart(let segment, let part):
            return ["segment": segment, "part": part, "rerecord": true]
        case .editPart(let segment, let part, let text):
            return ["segment": segment, "part": part, "text": text]
        }
    }

    /// One fix per word and one per sentence: a newer choice replaces the older one.
    var id: String {
        switch self {
        case .option(let word, _), .custom(let word, _): return "w:" + word
        case .rereadSentence(let segment), .editSentence(let segment, _): return "s:\(segment)"
        case .rereadPart(let segment, let part), .editPart(let segment, let part, _):
            return "p:\(segment):\(part)"
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

/// Splits a sentence into the pieces shown on the fix screen, the way the website does:
/// every run of Ethiopic letters is a word that can be tapped, and everything between
/// (punctuation, numbers, Latin text) is shown but cannot be.
enum Words {
    struct Token: Identifiable, Equatable {
        let id: Int
        let shown: String
        /// The word as the server wants it. Empty when this piece cannot be fixed.
        let word: String
        /// True when a space came before this piece in the script.
        var spaceBefore = false
    }

    static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x1200 && scalar.value <= 0x135A
    }

    static func tokens(in sentence: String, startingAt offset: Int = 0) -> [Token] {
        var out: [Token] = []
        var run = String.UnicodeScalarView()
        var runIsWord = false
        var space = false
        var runSpace = false
        func flush() {
            guard !run.isEmpty else { return }
            let text = String(run)
            out.append(Token(id: offset + out.count, shown: text, word: runIsWord ? text : "",
                             spaceBefore: runSpace))
            run = String.UnicodeScalarView()
        }
        for scalar in sentence.unicodeScalars {
            if scalar.properties.isWhitespace {
                flush()
                space = true
                continue
            }
            let letter = isLetter(scalar)
            if run.isEmpty || letter != runIsWord {
                flush()
                runIsWord = letter
                runSpace = space
                space = false
            }
            run.append(scalar)
        }
        flush()
        return out
    }
}

/// The script cut the way the server cuts it. A segment is a block of audio (many
/// sentences); a part is one clause ending at ፣ or ።; a sentence is the parts up to a ።.
enum Script {
    struct Sentence: Identifiable, Equatable {
        let segment: Int
        /// Which sentence of the segment this is.
        let index: Int
        /// The clause numbers inside the segment that make up this sentence.
        let parts: [Int]
        let text: String
        var id: String { "\(segment):\(index)" }
    }

    /// Clauses of a segment, each keeping its closing mark. Joined with "" they give the
    /// segment back, apart from blank pieces.
    static func clauses(_ segment: String) -> [String] {
        var out: [String] = []
        var current = ""
        for character in segment {
            current.append(character)
            if character == "።" || character == "፣" {
                out.append(current)
                current = ""
            }
        }
        out.append(current)
        return out.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func sentences(_ segments: [String]) -> [Sentence] {
        var out: [Sentence] = []
        for (si, segment) in segments.enumerated() {
            let pieces = clauses(segment)
            var parts: [Int] = []
            var index = 0
            func close() {
                guard !parts.isEmpty else { return }
                let text = parts.map { pieces[$0] }.joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(Sentence(segment: si, index: index, parts: parts, text: text))
                index += 1
                parts = []
            }
            for (pi, piece) in pieces.enumerated() {
                parts.append(pi)
                if piece.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("።") { close() }
            }
            close()
        }
        return out
    }
}

/// One change waiting on the fix screen, before it is sent.
enum PendingFix: Identifiable, Equatable {
    case word(FixEdit, label: String)
    case reread(Script.Sentence)
    case edit(Script.Sentence, text: String)

    /// One change per word and one per sentence: a newer choice replaces the older one.
    var id: String {
        switch self {
        case .word(let fix, _): return fix.id
        case .reread(let sentence), .edit(let sentence, _): return "s:" + sentence.id
        }
    }

    /// What is sent for a list of changes, following the website:
    /// - a word fix goes as it is;
    /// - an edited sentence goes clause by clause when it still has the same number of
    ///   clauses, otherwise the whole segment is sent once with every edit in it;
    /// - "read again" goes clause by clause, and is dropped for a segment that is being edited.
    static func wire(_ pending: [PendingFix], segments: [String]) -> [FixEdit] {
        var out: [FixEdit] = []
        var edits: [Int: [(Script.Sentence, String)]] = [:]
        for item in pending {
            switch item {
            case .word(let fix, _): out.append(fix)
            case .edit(let sentence, let text): edits[sentence.segment, default: []].append((sentence, text))
            case .reread: break
            }
        }
        for segment in edits.keys.sorted() {
            let list = edits[segment] ?? []
            var perPart: [FixEdit] = []
            var structural = false
            for (sentence, text) in list {
                let pieces = Script.clauses(text)
                if pieces.count == sentence.parts.count {
                    for (offset, part) in sentence.parts.enumerated() {
                        perPart.append(.editPart(segment: segment, part: part, text: pieces[offset]))
                    }
                } else {
                    structural = true
                }
            }
            if structural, segment < segments.count {
                out.append(.editSentence(segment: segment,
                                         text: segmentText(segments[segment], with: list)))
            } else {
                out.append(contentsOf: perPart)
            }
        }
        for item in pending {
            if case .reread(let sentence) = item, edits[sentence.segment] == nil {
                for part in sentence.parts {
                    out.append(.rereadPart(segment: sentence.segment, part: part))
                }
            }
        }
        return out
    }

    /// A fresh take of everything: every segment is read again, with any edits in it.
    static func wholeScript(_ pending: [PendingFix], segments: [String]) -> [FixEdit] {
        var out: [FixEdit] = []
        var edits: [Int: [(Script.Sentence, String)]] = [:]
        for item in pending {
            switch item {
            case .word(let fix, _): out.append(fix)
            case .edit(let sentence, let text): edits[sentence.segment, default: []].append((sentence, text))
            case .reread: break
            }
        }
        for (index, segment) in segments.enumerated() {
            if let list = edits[index] {
                out.append(.editSentence(segment: index, text: segmentText(segment, with: list)))
            } else {
                out.append(.rereadSentence(segment: index))
            }
        }
        return out
    }

    /// The segment with each edited sentence's clauses replaced by its new words.
    static func segmentText(_ segment: String, with edits: [(Script.Sentence, String)]) -> String {
        var pieces: [String?] = Script.clauses(segment)
        for (sentence, text) in edits {
            guard let first = sentence.parts.first, first < pieces.count else { continue }
            for part in sentence.parts where part < pieces.count { pieces[part] = nil }
            pieces[first] = text
        }
        return pieces.compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
    }
}
