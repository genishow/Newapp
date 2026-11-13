import XCTest
@testable import Kinbir

final class TextKindTests: XCTestCase {
    func testEmpty() {
        XCTAssertEqual(TextKind.detect(""), .empty)
        XCTAssertEqual(TextKind.detect("  \n "), .empty)
    }

    func testAmharic() {
        XCTAssertEqual(TextKind.detect("ሰላም ለሁላችሁ።"), .amharic)
    }

    func testEnglish() {
        XCTAssertEqual(TextKind.detect("Coffee was first found in Ethiopia."), .english)
    }

    func testMostlyAmharicWithAnEnglishNameStaysAmharic() {
        XCTAssertEqual(TextKind.detect("ዛሬ ስለ ቡና እና ስለ ኢትዮጵያ ታሪክ እንነጋገራለን AI"), .amharic)
    }

    func testMostlyEnglishWithOneAmharicWordIsEnglish() {
        XCTAssertEqual(TextKind.detect("The word ቡና means coffee in Amharic and it is loved."), .english)
    }

    func testLink() {
        XCTAssertEqual(TextKind.detect("https://example.com/news/story"), .link)
        XCTAssertEqual(TextKind.detect("  http://example.org  "), .link)
    }

    func testTextThatContainsALinkIsNotALink() {
        XCTAssertEqual(TextKind.detect("Read https://example.com today"), .english)
    }

    func testNotALinkWithoutSchemeOrDot() {
        XCTAssertFalse(TextKind.isLink("example.com"))
        XCTAssertFalse(TextKind.isLink("https://localhost"))
    }

    func testDigitsOnlyGoStraightToVoice() {
        XCTAssertEqual(TextKind.detect("2026"), .amharic)
    }

    func testEthiopicLetterCountIgnoresPunctuationAndSpaces() {
        XCTAssertEqual(TextKind.ethiopicLetterCount("ሰላም፣ ሰላም።"), 6)
        XCTAssertEqual(TextKind.ethiopicLetterCount("hello"), 0)
    }
}

final class RulesTests: XCTestCase {
    func testEnrollDuration() {
        XCTAssertNotNil(EnrollRules.problem(seconds: 5, bytes: 1_000))
        XCTAssertNil(EnrollRules.problem(seconds: 10, bytes: 1_000))
        XCTAssertNil(EnrollRules.problem(seconds: 40, bytes: 1_000))
        XCTAssertNotNil(EnrollRules.problem(seconds: 41, bytes: 1_000))
    }

    func testEnrollSize() {
        XCTAssertNil(EnrollRules.problem(seconds: 20, bytes: 60 * 1024 * 1024))
        XCTAssertNotNil(EnrollRules.problem(seconds: 20, bytes: 60 * 1024 * 1024 + 1))
    }

    func testEmail() {
        XCTAssertTrue(EmailRules.looksValid("geni@example.com"))
        XCTAssertTrue(EmailRules.looksValid("  a.b@mail.co.uk "))
        XCTAssertFalse(EmailRules.looksValid("geni"))
        XCTAssertFalse(EmailRules.looksValid("geni@"))
        XCTAssertFalse(EmailRules.looksValid("@example.com"))
        XCTAssertFalse(EmailRules.looksValid("geni@example"))
        XCTAssertFalse(EmailRules.looksValid("geni@example."))
        XCTAssertFalse(EmailRules.looksValid("ge ni@example.com"))
    }
}

final class FormatterTests: XCTestCase {
    func testCredits() {
        XCTAssertEqual(Fmt.credits(12), "12")
        XCTAssertEqual(Fmt.credits(2.5), "2.5")
        XCTAssertEqual(Fmt.credits(17.56), "17.6")
        XCTAssertEqual(Fmt.credits(0), "0")
        XCTAssertEqual(Fmt.credits(19.96), "20")
    }

    func testClock() {
        XCTAssertEqual(Fmt.clock(0), "0:00")
        XCTAssertEqual(Fmt.clock(75), "1:15")
        XCTAssertEqual(Fmt.clock(9.4), "0:09")
        XCTAssertEqual(Fmt.clock(.nan), "0:00")
    }

    func testLength() {
        XCTAssertEqual(Fmt.length(nil), "")
        XCTAssertEqual(Fmt.length(20), "20 sec")
        XCTAssertEqual(Fmt.length(60), "1 min")
        XCTAssertEqual(Fmt.length(75), "1 min 15 sec")
    }

    func testServerDates() {
        XCTAssertNotNil(Fmt.date(fromServer: "2026-11-12T10:00:00Z"))
        XCTAssertNotNil(Fmt.date(fromServer: "2026-11-12T10:00:00.123456Z"))
        XCTAssertNotNil(Fmt.date(fromServer: "2026-11-12T10:00:00"))
        XCTAssertNil(Fmt.date(fromServer: "yesterday"))
        XCTAssertNil(Fmt.date(fromServer: nil))
    }

    func testAgo() {
        let now = Fmt.date(fromServer: "2026-11-12T12:00:00Z")!
        XCTAssertEqual(Fmt.ago("2026-11-12T11:59:40Z", now: now), "just now")
        XCTAssertEqual(Fmt.ago("2026-11-12T11:30:00Z", now: now), "30 min ago")
        XCTAssertEqual(Fmt.ago("2026-11-12T09:00:00Z", now: now), "3 h ago")
        XCTAssertEqual(Fmt.ago("2026-11-10T12:00:00Z", now: now), "2 d ago")
        XCTAssertEqual(Fmt.ago(nil, now: now), "")
    }

    func testOwnerTagIsStableAndDiffers() {
        XCTAssertEqual(Fmt.ownerTag("am-abc"), Fmt.ownerTag("am-abc"))
        XCTAssertNotEqual(Fmt.ownerTag("am-abc"), Fmt.ownerTag("am-abd"))
    }
}

final class InterfaceLanguageTests: XCTestCase {
    func testEveryAmharicLineKeepsItsValues() {
        // A line like "Shot %@" must keep the same number of slots in Amharic.
        for (english, amharic) in Amharic.table {
            XCTAssertFalse(amharic.trimmingCharacters(in: .whitespaces).isEmpty, "empty line for: \(english)")
            XCTAssertEqual(english.components(separatedBy: "%@").count,
                           amharic.components(separatedBy: "%@").count,
                           "value slots differ for: \(english)")
        }
    }

    func testAmharicLinesAreActuallyAmharic() {
        for (english, amharic) in Amharic.table where english != "Kinbir" {
            XCTAssertTrue(amharic.unicodeScalars.contains { TextKind.isEthiopic($0) },
                          "no Ethiopic letters in the line for: \(english)")
        }
    }

    func testEndingsMatch() {
        // Lines glued in front of other text end with a space in both languages.
        for (english, amharic) in Amharic.table {
            XCTAssertEqual(english.hasSuffix(" "), amharic.hasSuffix(" "), "trailing space differs for: \(english)")
        }
    }

    func testHoursLeft() {
        let now = Fmt.date(fromServer: "2026-11-12T12:00:00Z")!
        XCTAssertEqual(Fmt.hoursLeft("2026-11-12T11:00:00Z", now: now), 47)
        XCTAssertEqual(Fmt.hoursLeft("2026-11-10T13:00:00Z", now: now), 1)
        XCTAssertNil(Fmt.hoursLeft("2026-11-10T11:00:00Z", now: now), "past 48 hours it is gone")
        XCTAssertNil(Fmt.hoursLeft(nil, now: now))
    }

    func testWritingFromAnIdea() {
        var options = ScriptOptions(targetSec: 60)
        options.fromIdea = true
        XCTAssertEqual(options.fields["mode"] as? String, "brief")
        XCTAssertEqual(options.fields["target_sec"] as? Int, 60)
        options.refineInstruction = "shorter"
        XCTAssertEqual(options.fields["mode"] as? String, "refine", "a change request wins over an idea")
    }
}
