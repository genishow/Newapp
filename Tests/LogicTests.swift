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

final class EthiopicTypingTests: XCTestCase {
    func testTypingLatinGivesAmharicLikeTheWebsite() {
        XCTAssertEqual(Ethiopic.type("s"), "ስ")
        XCTAssertEqual(Ethiopic.type("se"), "ሰ")
        XCTAssertEqual(Ethiopic.type("selam"), "ሰላም")
        XCTAssertEqual(Ethiopic.type("see"), "ሴ")
        XCTAssertEqual(Ethiopic.type("sh"), "ሽ")
        XCTAssertEqual(Ethiopic.type("qua"), "ቋ")
        XCTAssertEqual(Ethiopic.type("Te"), "ጠ")
        XCTAssertEqual(Ethiopic.type("a"), "አ")
        XCTAssertEqual(Ethiopic.type("bunna"), "ቡንና")
        XCTAssertEqual(Ethiopic.type("::"), "።")
        XCTAssertEqual(Ethiopic.type(",,"), "፣")
        XCTAssertEqual(Ethiopic.type("ሰላም", typed: " "), "ሰላም ")
        XCTAssertEqual(Ethiopic.type("ሰላም", typed: "7"), "ሰላም7")
    }

    func testLetterPadHasEveryFamily() {
        XCTAssertEqual(Ethiopic.padLetters.count, 7 + 34 * 7)
        XCTAssertEqual(Ethiopic.padLetters[7], "ሀ")
        XCTAssertTrue(Ethiopic.padLetters.contains("ፐ"))
    }
}

final class FootageExtrasTests: XCTestCase {
    func testMusicBreaksLikeTheWebsite() {
        XCTAssertEqual(MusicBreaks().payload["mode"] as? String, "none")
        XCTAssertEqual(MusicBreaks(choice: "auto").payload["mode"] as? String, "auto")
        let three = MusicBreaks(choice: "3").payload
        XCTAssertEqual(three["mode"] as? String, "count")
        XCTAssertEqual(three["count"] as? Int, 3)
        XCTAssertEqual(MusicBreaks.choices.count, 10)
    }

    func testLogoAndBreaksInTheRenderRequest() {
        var options = RenderOptions()
        XCTAssertNil(options.payload(music: false, captions: false)["logo"])
        XCTAssertNil(options.payload(music: false, captions: false)["gaps_enabled"])
        options.logo.enabled = true
        options.logo.corner = "bl"
        options.logo.scale = 99
        options.includeBreaks = false
        let body = options.payload(music: false, captions: false)
        let logo = body["logo"] as? [String: Any]
        XCTAssertEqual(logo?["corner"] as? String, "bl")
        XCTAssertEqual(logo?["scale"] as? Int, 30, "the size is kept between 5 and 30")
        XCTAssertEqual(body["gaps_enabled"] as? Bool, false)
    }

    func testPaidCheckQuote() {
        XCTAssertEqual(VerifyResult.credits(shots: 1), 2)
        XCTAssertEqual(VerifyResult.credits(shots: 60), 2)
        XCTAssertEqual(VerifyResult.credits(shots: 61), 3)
        XCTAssertEqual(VerifyResult.credits(shots: 300), 10)
    }

    func testFreeCheckAnswerIsAtTheTopLevel() throws {
        // What GET /jobs/{id} really returns for a footage rescan.
        let job = try JSON.decoder.decode(FootageCheckJob.self, from: Data(#"{"job_id":"j","status":"done","scanned":4,"mismatched":[{"beat":3,"score":0.2,"line":"x"}],"note":"1 shot may not match"}"#.utf8))
        XCTAssertEqual(job.wrongShots.map(\.beat), [3])
        let clean = try JSON.decoder.decode(FootageCheckJob.self, from: Data(#"{"status":"done","scanned":4,"mismatched":[]}"#.utf8))
        XCTAssertTrue(clean.wrongShots.isEmpty)
    }

    func testAutofillWithNothingToSearch() throws {
        let none = try JSON.decoder.decode(AutofillSubmit.self, from: Data(#"{"job_id":null,"status":"skipped","empty":2,"note":"this plan uses only your own clips"}"#.utf8))
        XCTAssertNil(none.jobId)
        XCTAssertEqual(none.note, "this plan uses only your own clips")
        let some = try JSON.decoder.decode(AutofillSubmit.self, from: Data(#"{"job_id":"f1","status":"queued","empty":2,"note":""}"#.utf8))
        XCTAssertEqual(some.jobId, "f1")
    }

    func testChecksDecode() throws {
        let job = try JSON.decoder.decode(FootageCheckJob.self, from: Data(#"{"status":"done","result":{"scanned":4,"mismatched":[{"beat":2,"score":0.1,"line":"x"}],"note":""}}"#.utf8))
        XCTAssertEqual(job.result?.mismatched?.first?.beat, 2)
        let verify = try JSON.decoder.decode(VerifyResult.self, from: Data(#"{"plan_id":"p","checks":[{"beat":1,"verdict":"no","why":"shows a beach"}],"auto_replaced":[3],"flagged":1,"beats":[],"credits_charged":2}"#.utf8))
        XCTAssertEqual(verify.checks?.first?.verdict, "no")
        XCTAssertEqual(verify.autoReplaced, [3])
    }
}

