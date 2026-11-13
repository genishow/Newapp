import Foundation

/// Type-to-Amharic, the same rules as the Kinbir website: ordinary Latin typing becomes
/// Ethiopic as you type. se → ሰ, selam → ሰላም, a bare s → ስ, :: → ።, ,, → ፣.
/// Capitals are the ejectives: T → ጠ, C → ጨ, P → ጰ, S → ጸ.
enum Ethiopic {
    /// Row starts (the first-order letter). Order k is start + k; the bare form is start + 5.
    static let row: [Character: UInt32] = [
        "h": 0x1200, "l": 0x1208, "H": 0x1210, "m": 0x1218, "r": 0x1228, "s": 0x1230,
        "x": 0x1238, "q": 0x1240, "b": 0x1260, "v": 0x1268, "t": 0x1270, "c": 0x1278,
        "n": 0x1290, "N": 0x1298, "k": 0x12a8, "K": 0x12b8, "w": 0x12c8, "z": 0x12d8,
        "Z": 0x12e0, "y": 0x12e8, "d": 0x12f0, "j": 0x1300, "g": 0x1308, "T": 0x1320,
        "C": 0x1328, "P": 0x1330, "S": 0x1338, "f": 0x1348, "p": 0x1350,
    ]
    static let vowelOrder: [Character: UInt32] = ["e": 0, "u": 1, "i": 2, "a": 3, "E": 4, "o": 6]
    static let loneVowel: [Character: String] = [
        "a": "አ", "u": "ኡ", "i": "ኢ", "e": "እ", "E": "ኤ", "o": "ኦ", "A": "ዐ",
    ]
    static let labio: [Character: String] = ["ቁ": "ቋ", "ኩ": "ኳ", "ጉ": "ጓ", "ሁ": "ኋ"]

    private static func letter(_ value: UInt32) -> String {
        Unicode.Scalar(value).map { String(Character($0)) } ?? ""
    }

    private static let sixthToRow: [Character: UInt32] = {
        var out: [Character: UInt32] = [:]
        for start in row.values { if let c = letter(start + 5).first { out[c] = start } }
        return out
    }()

    private static let firstToRow: [Character: UInt32] = {
        var out: [Character: UInt32] = [:]
        for start in row.values { if let c = letter(start).first { out[c] = start } }
        return out
    }()

    /// One keystroke. `replacesPrevious` is true when the letter before the caret turns
    /// into `text`; false when `text` is simply added. Nil lets the key through unchanged.
    static func key(previous: Character?, typed: Character) -> (replacesPrevious: Bool, text: String)? {
        if typed == ":" {
            return previous == "፡" ? (true, "።") : (false, "፡")
        }
        if typed == "," {
            return previous == "," ? (true, "፣") : nil
        }
        guard typed.isASCII, typed.isLetter else { return nil }
        if let previous {
            if previous == "ስ" && typed == "h" { return (true, "ሽ") }
            if previous == "ዝ" && typed == "h" { return (true, "ዥ") }
            if previous == "ን" && typed == "y" { return (true, "ኝ") }
            if let start = sixthToRow[previous], let order = vowelOrder[typed] {
                return (true, letter(start + order))
            }
            if let start = firstToRow[previous], typed == "e" {
                return (true, letter(start + 4))
            }
            if typed == "a", let both = labio[previous] { return (true, both) }
        }
        if let start = row[typed] { return (false, letter(start + 5)) }
        if let vowel = loneVowel[typed] { return (false, vowel) }
        return nil
    }

    /// The text after typing `typed` at its end.
    static func type(_ value: String, typed: Character) -> String {
        guard let edit = key(previous: value.last, typed: typed) else { return value + String(typed) }
        return (edit.replacesPrevious ? String(value.dropLast()) : value) + edit.text
    }

    /// Types a whole Latin word, for tests and examples: "selam" → "ሰላም".
    static func type(_ latin: String) -> String {
        latin.reduce("") { type($0, typed: $1) }
    }

    /// The letter pad: one row per family, seven forms each, and the punctuation row.
    static let rowStarts: [UInt32] = [
        0x1200, 0x1208, 0x1210, 0x1218, 0x1220, 0x1228, 0x1230, 0x1238, 0x1240, 0x1260,
        0x1268, 0x1270, 0x1278, 0x1280, 0x1290, 0x1298, 0x12a0, 0x12a8, 0x12b8, 0x12c8,
        0x12d0, 0x12d8, 0x12e0, 0x12e8, 0x12f0, 0x1300, 0x1308, 0x1320, 0x1328, 0x1330,
        0x1338, 0x1340, 0x1348, 0x1350,
    ]
    static let punctuation = ["።", "፣", "፤", "፥", "፦", "፧", "፡"]
    static var padLetters: [String] {
        punctuation + rowStarts.flatMap { start in (0..<7).map { letter(start + UInt32($0)) } }
    }
}
