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

    func testOwnClipShowsItsPictureAndStillsAreImages() throws {
        // What GET /broll/plan returns for an own clip and for an old newspaper picture.
        let json = #"{"beats":[{"beat":1,"candidates":[{"clip_id":5,"poster":null,"link":"/models/uploads/c/up-1.mov","preview_link":"/models/uploads/c/up-1.mov","own_upload":true,"kind":"video","poster_url":"/uploads/up-1.poster.jpg/file?e=1&t=x","stream_url":"/uploads/up-1.mov/file?e=1&t=y&v=preview"}]},{"beat":2,"candidates":[{"clip_id":6,"poster":"https://example.org/p.jpg","preview_link":"https://example.org/p.jpg","kind":"still"}]}]}"#
        let plan = try JSON.decoder.decode(StoredPlan.self, from: Data(json.utf8))
        let own = try XCTUnwrap(plan.beats?.first?.chosen)
        XCTAssertEqual(own.posterURL?.absoluteString, "https://api.kinbir.com/uploads/up-1.poster.jpg/file?e=1&t=x")
        XCTAssertEqual(own.previewURL?.absoluteString, "https://api.kinbir.com/uploads/up-1.mov/file?e=1&t=y&v=preview")
        XCTAssertFalse(own.isStill)
        let still = try XCTUnwrap(plan.beats?.last?.chosen)
        XCTAssertTrue(still.isStill)
        XCTAssertEqual(still.previewURL?.absoluteString, "https://example.org/p.jpg")
        let unmarked = Candidate(clipId: 1, previewLink: "https://x.org/a.PNG?w=3")
        XCTAssertTrue(unmarked.isStill, "a picture link with no kind is still a picture")
    }

    func testClipGuideAndLengthLimit() throws {
        XCTAssertEqual(ClipRules.suggestedClips(shots: 14).low, 5)
        XCTAssertEqual(ClipRules.suggestedClips(shots: 14).high, 15)
        XCTAssertEqual(ClipRules.suggestedClips(shots: 0).low, 1)
        XCTAssertTrue(ClipRules.isTooLong(seconds: 601))
        XCTAssertFalse(ClipRules.isTooLong(seconds: 600))
        let stretch = try JSON.decoder.decode(StretchResult.self, from: Data(#"{"plan_id":"p","beats":[],"dur_sec":4.5,"changed":[1,2],"note":"This shot is now 4.5 seconds."}"#.utf8))
        XCTAssertEqual(stretch.durSec, 4.5)
    }
}


final class SpellingVariantsTests: XCTestCase {
    func testHoldsOrLetsGoOfOneSound() {
        // gebboch: b is held, ch is one sound. The first sound never changes.
        let v = SpellingVariants.make("gebboch")
        XCTAssertEqual(v, ["geboch", "gebbochch", "gebochch"])
    }

    func testSpreadsAcrossALongWord() {
        let v = SpellingVariants.make("ennddiderregg")
        XCTAssertEqual(v.count, 3)
        XCTAssertEqual(Set(v).count, 3)
        XCTAssertFalse(v.contains("ennddiderregg"))
        XCTAssertEqual(v.first, "enddiderregg")
        XCTAssertEqual(v.last, "ennddiderreg")
    }

    func testNothingForAmharicLettersOrSentences() {
        XCTAssertEqual(SpellingVariants.make("ገቦች"), [])
        XCTAssertEqual(SpellingVariants.make("two words"), [])
        XCTAssertEqual(SpellingVariants.make("a"), [])
    }
}

final class SpeechCheckTests: XCTestCase {
    private let rate = 16_000.0

    private func tone(_ seconds: Double, amp: Float = 0.2) -> [Float] {
        (0..<Int(rate * seconds)).map { amp * Float(sin(2 * Double.pi * 180 * Double($0) / rate)) }
    }

    func testAVoicedWordIsSpeech() {
        XCTAssertTrue(SpeechCheck.isSpeech(tone(0.6), sampleRate: rate))
    }

    func testSilenceIsNotSpeech() {
        XCTAssertFalse(SpeechCheck.isSpeech([Float](repeating: 0, count: 16_000), sampleRate: rate))
    }

    func testBreathingNoiseIsNotSpeech() {
        var seed: UInt64 = 42
        let noise: [Float] = (0..<16_000).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (Float(seed >> 40) / 16_777_216 - 0.5) * 0.4
        }
        XCTAssertFalse(SpeechCheck.isSpeech(noise, sampleRate: rate))
    }

    func testAWordAfterABreathStillCounts() {
        var seed: UInt64 = 7
        let breath: [Float] = (0..<8_000).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (Float(seed >> 40) / 16_777_216 - 0.5) * 0.12
        }
        XCTAssertTrue(SpeechCheck.isSpeech(breath + tone(0.4), sampleRate: rate))
    }

    func testLibraryShowsOnlyTheLast48Hours() throws {
        let now = Fmt.date(fromServer: "2026-11-15T12:00:00Z")!
        let jobs = try JSON.decoder.decode([JobSummary].self, from: Data(#"""
        [{"job_id":"new","status":"done","created_at":"2026-11-15T10:00:00Z","finished_at":"2026-11-15T10:01:00Z"},
         {"job_id":"old","status":"done","created_at":"2026-11-13T10:00:00Z","finished_at":"2026-11-13T11:00:00Z"},
         {"job_id":"making","status":"running"}]
        """#.utf8))
        let videos = try JSON.decoder.decode([VideoSummary].self, from: Data(#"""
        [{"video_job_id":"vid-new","finished_at":"2026-11-14T13:00:00Z"},
         {"video_job_id":"vid-old","finished_at":"2026-11-12T10:00:00Z"}]
        """#.utf8))
        let fresh = LibraryCache(jobs: jobs, videos: videos).fresh(now: now)
        XCTAssertEqual(fresh.jobs.map(\.jobId), ["new", "making"])
        XCTAssertEqual(fresh.videos.map(\.videoJobId), ["vid-new"])
    }

    func testSavedFilesAreNamedAfterTheScript() {
        XCTAssertEqual(SaveName.base(script: "ቅንብር የሚለየውም የቪዲዮአችሁን ድምፅ በራሳችሁ ድምፅ ያደርጋል።"),
                       "Kinbir - ቅንብር የሚለየውም የቪዲዮአችሁን ድምፅ በራሳችሁ")
        XCTAssertEqual(SaveName.base(script: "Hello, world."), "Kinbir - Hello, world")
        XCTAssertEqual(SaveName.base(script: "a/b: c?…"), "Kinbir - a b c")
        XCTAssertEqual(SaveName.base(script: nil), "Kinbir")
        XCTAssertEqual(SaveName.base(script: "   "), "Kinbir")
    }
}

/// The writer on free credits offers only lengths the trial can voice, the same
/// numbers the website works out (web/lib/create.ts).
final class TrialLengthTests: XCTestCase {
    private let all = [15, 30, 45, 60, 90, 120, 180, 240, 300, 420, 600]

    func testPaidAccountKeepsEveryLength() {
        XCTAssertEqual(TrialRule.lengths(all, trialMaxChars: nil, language: .am), all)
        XCTAssertNil(TrialRule.aboutSeconds(trialMaxChars: nil, language: .en))
        XCTAssertEqual(TrialRule.writerTarget(600, trialMaxChars: nil, language: .am), 600)
        XCTAssertNil(TrialRule.writerTarget(nil, trialMaxChars: nil, language: .am))
    }

    func testAmharicTrialStopsAtAboutTwoMinutes() {
        XCTAssertEqual(TrialRule.aboutSeconds(trialMaxChars: 900, language: .am), 120)
        XCTAssertEqual(TrialRule.lengths(all, trialMaxChars: 900, language: .am), [15, 30, 45, 60, 90, 120])
        // 900 / (7.17 * 0.97) = 129.4 s, asked for 93% of it
        XCTAssertEqual(TrialRule.writerTarget(120, trialMaxChars: 900, language: .am), 120)
        XCTAssertEqual(TrialRule.writerTarget(600, trialMaxChars: 900, language: .am), 120)
    }

    func testEnglishTrialUsesWords() {
        // 260 words / 2.2 = 118.2 s
        XCTAssertEqual(TrialRule.aboutSeconds(trialMaxChars: 900, language: .en), 120)
        XCTAssertEqual(TrialRule.writerTarget(120, trialMaxChars: 900, language: .en), 109)
        XCTAssertEqual(TrialRule.limitWords(trialMaxChars: 900, language: .en), "260 English words")
        XCTAssertEqual(TrialRule.limitWords(trialMaxChars: 900, language: .am), "900 Amharic characters")
    }
}

/// The video style choices are the website's (2026-11-21).
final class StyleChoiceTests: XCTestCase {
    func testSameChoicesAsTheWebsite() {
        XCTAssertEqual(RenderOptions.colors.count, 12)
        XCTAssertEqual(RenderOptions.colors.map(\.id).prefix(6),
                       ["gold", "blue", "red", "green", "purple", "white"])
        XCTAssertEqual(RenderOptions.musicLevels.map(\.id),
                       ["subtle", "balanced", "prominent", "strong", "front"])
        XCTAssertEqual(RenderOptions.fonts(english: false).map(\.id), ["standard", "serif"])
        XCTAssertEqual(RenderOptions.fonts(english: true).map(\.id),
                       ["standard", "serif", "display", "typewriter"])
    }
}

/// The AI shot prompt is word for word the website's (veoPrompt in BrollBeat.tsx).
final class AiShotPromptTests: XCTestCase {
    private let tail = " Ultra high quality, photorealistic, shot on a high-end cinema camera. Neutral true-to-life color, no color grading, no filters, no tint, not oversaturated. Everything in crisp sharp focus, no blur, no soft focus, no shallow depth of field. Realistic textures and true-to-life motion, smooth stabilized slow camera movement. No glitching, no warping or morphing, no flickering, no distorted faces or hands, no on-screen text, no subtitles, no watermarks, no logos, nobody speaking to camera."

    func testWideShot() {
        let beat = Beat(beat: 1, dur: 4.6, mustShow: "coffee ceremony in a village.")
        XCTAssertEqual(AiShot.prompt(for: beat),
                       "coffee ceremony in a village. Extremely wide cinematic shot with generous space around the subject, so the frame survives cropping to any format, widescreen 16:9, about 5 seconds." + tail)
    }

    func testCloseUpAndLongShot() {
        let beat = Beat(beat: 2, dur: 12, query: "macro coffee beans")
        XCTAssertEqual(AiShot.prompt(for: beat),
                       "macro coffee beans. Detailed close-up shot, subject filling the frame, widescreen 16:9, about 8 seconds." + tail)
    }
}

/// The music for each part of the video, the website's orderedArcIds.
final class MusicArcTests: XCTestCase {
    func testOneTrackPerPartKeepingTheTrackBefore() {
        XCTAssertEqual(RenderOptions.musicArc(parts: 1, picks: ["a"]), [])
        XCTAssertEqual(RenderOptions.musicArc(parts: 3, picks: ["a", nil, "b"]), ["a", "a", "b"])
        XCTAssertEqual(RenderOptions.musicArc(parts: 3, picks: ["a", "b"]), ["a", "b", "b"])
        XCTAssertEqual(RenderOptions.musicArc(parts: 2, picks: [nil, nil]), [])
    }

    func testBreaksAndArcAreSent() {
        var options = RenderOptions()
        options.musicIds = ["a", "b"]
        options.sfxId = "whoosh"
        let body = options.payload(music: true, captions: false)
        XCTAssertEqual(body["music_ids"] as? [String], ["a", "b"])
        XCTAssertEqual(body["sfx_id"] as? String, "whoosh")
        options.includeBreaks = false
        XCTAssertNil(options.payload(music: true, captions: false)["sfx_id"])
        XCTAssertNil(options.payload(music: false, captions: false)["music_ids"])
        XCTAssertEqual(MusicBreaks(choice: "3").payload["count"] as? Int, 3)
    }
}
