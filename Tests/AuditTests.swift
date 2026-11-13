import XCTest
@testable import Kinbir

/// Rules added after the audit: forcing a same-language rewrite, the website's price
/// maths, the free-trial length rule, and the fields they read.
final class AuditTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSON.decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: forcing a rewrite

    func testForceIsOnlySentWhenAsked() {
        XCTAssertNil(ScriptOptions(targetSec: 60).fields["force"])
        var options = ScriptOptions(targetSec: 60)
        options.force = true
        XCTAssertEqual(options.fields["force"] as? Bool, true)
        XCTAssertEqual(options.fields["target_sec"] as? Int, 60)
    }

    func testForceIsNotSentWithAChangeRequest() {
        var options = ScriptOptions(refineInstruction: "make it warmer")
        options.force = true
        XCTAssertNil(options.fields["force"], "refine is never skipped, so it needs no force")
    }

    func testSameLanguageFollowsTheOutputLanguage() {
        XCTAssertTrue(ScriptOptions.sameLanguage("ሰላም ለሁላችሁ።", as: .am))
        XCTAssertFalse(ScriptOptions.sameLanguage("Coffee was first found in Ethiopia.", as: .am))
        XCTAssertTrue(ScriptOptions.sameLanguage("Coffee was first found in Ethiopia.", as: .en))
        XCTAssertFalse(ScriptOptions.sameLanguage("ሰላም ለሁላችሁ።", as: .en))
        XCTAssertFalse(ScriptOptions.sameLanguage("https://example.com/story", as: .en))
    }

    func testSkippedAnswerDecodes() throws {
        let r = try decode(RewriteResult.self,
                           #"{"skipped":true,"reason":"input is already English","amharic":"Hello there.","mode":"video","warnings":[]}"#)
        XCTAssertEqual(r.skipped, true)
        XCTAssertEqual(r.amharic, "Hello there.")
        XCTAssertNil(r.creditsCharged)
    }

    func testMockSkipsSameLanguageUnlessForced() async throws {
        let api = MockAPI()
        let plain = try await api.rewrite(text: "ሰላም ለሁላችሁ።", options: ScriptOptions()) { _ in }
        XCTAssertEqual(plain.skipped, true)
        XCTAssertEqual(plain.amharic, "ሰላም ለሁላችሁ።")

        var options = ScriptOptions()
        options.force = true
        let forced = try await api.rewrite(text: "ሰላም ለሁላችሁ።", options: options) { _ in }
        XCTAssertEqual(forced.skipped, false)
        XCTAssertEqual(forced.creditsCharged, 1)
    }

    // MARK: price maths, as on the website

    func testAmharicSecondsUseTheWebsiteFormula() {
        // 787 letters / 7.87 * 1.12 = 112 seconds.
        let script = String(repeating: "ሰ", count: 787)
        XCTAssertEqual(ScriptMath.seconds(script, language: .am), 112, accuracy: 0.001)
        XCTAssertEqual(ScriptMath.seconds("", language: .am), 0)
        XCTAssertEqual(ScriptMath.seconds("hello there", language: .am), 0, "no Ethiopic letters")
    }

    func testEnglishSecondsAreWordsOverTwoPointTwo() {
        let script = Array(repeating: "word", count: 22).joined(separator: " ")
        XCTAssertEqual(ScriptMath.seconds(script, language: .en), 10, accuracy: 0.001)
        XCTAssertEqual(ScriptMath.seconds("   ", language: .en), 0)
    }

    func testVoiceCreditsFollowTheServerFormula() {
        // ceil((sec * 5.3 * 0.000164 + 0.03) * 4 / 0.155 * 2) / 2
        XCTAssertEqual(ScriptMath.voiceCredits(seconds: 1), 1)
        XCTAssertEqual(ScriptMath.voiceCredits(seconds: 60), 2.5)
        XCTAssertEqual(ScriptMath.voiceCredits(seconds: 112), 3.5)
        XCTAssertEqual(ScriptMath.voiceCredits(seconds: 600), 14.5)
        XCTAssertEqual(ScriptMath.voiceCredits(seconds: 0), 1, "the website shows 1 with nothing to time")
    }

    func testBalanceAfterNeverGoesUnderZero() {
        XCTAssertEqual(ScriptMath.balanceAfter(balance: 20, credits: 2.5), 17.5)
        XCTAssertEqual(ScriptMath.balanceAfter(balance: 1, credits: 2.5), 0)
        XCTAssertEqual(ScriptMath.balanceAfter(balance: 17.56, credits: 1), 16.6, accuracy: 0.0001)
    }

    // MARK: the free trial

    func testTrialLimitCountsEthiopicLetters() {
        let fits = String(repeating: "ሰ", count: 900) + " . , 123 abc"
        let over = String(repeating: "ሰ", count: 901)
        XCTAssertFalse(TrialRule.isOver(fits, language: .am, trialMaxChars: 900))
        XCTAssertNil(TrialRule.problem(fits, language: .am, trialMaxChars: 900))
        XCTAssertTrue(TrialRule.isOver(over, language: .am, trialMaxChars: 900))
        let line = TrialRule.problem(over, language: .am, trialMaxChars: 900) ?? ""
        XCTAssertTrue(line.contains("900 Amharic characters"))
        XCTAssertTrue(line.contains("This script is 901."))
    }

    func testTrialLimitCountsEnglishWords() {
        let fits = Array(repeating: "word", count: 260).joined(separator: " ")
        let over = Array(repeating: "word", count: 261).joined(separator: " ")
        XCTAssertFalse(TrialRule.isOver(fits, language: .en, trialMaxChars: 900))
        XCTAssertTrue(TrialRule.isOver(over, language: .en, trialMaxChars: 900))
        let line = TrialRule.problem(over, language: .en, trialMaxChars: 900) ?? ""
        XCTAssertTrue(line.contains("260 English words"))
        XCTAssertTrue(line.contains("This script is 261."))
    }

    func testAPaidAccountHasNoTrialLimit() {
        let long = String(repeating: "ሰ", count: 5000)
        XCTAssertFalse(TrialRule.isOver(long, language: .am, trialMaxChars: nil))
        XCTAssertNil(TrialRule.problem(long, language: .am, trialMaxChars: nil))
    }

    // MARK: a second voice

    func testEnrollSaysWhetherTheNewVoiceIsInUse() throws {
        let second = try decode(EnrollResult.self,
                                #"{"status":"approved","voice_id":"v2","active":false,"credits_granted":0,"message":"voice added - activate it with POST /voices/activate"}"#)
        XCTAssertEqual(second.active, false)
        let first = try decode(EnrollResult.self, #"{"status":"approved","voice_id":"v1","active":true}"#)
        XCTAssertEqual(first.active, true)
        let old = try decode(EnrollResult.self, #"{"status":"approved","voice_id":"v1"}"#)
        XCTAssertNil(old.active)
    }

    func testMockSecondVoiceIsNotSwitchedTo() async throws {
        let api = MockAPI()
        let added = try await api.enroll(videoURL: URL(fileURLWithPath: "/tmp/x.mov"))
        XCTAssertEqual(added.active, false, "the account already had a voice in use")
        let fresh = MockAPI(scenario: .init(noVoice: true))
        let first = try await fresh.enroll(videoURL: URL(fileURLWithPath: "/tmp/x.mov"))
        XCTAssertEqual(first.active, true)
    }
}
