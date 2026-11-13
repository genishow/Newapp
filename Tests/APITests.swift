import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Kinbir

final class RequestBuilderTests: XCTestCase {
    private let builder = RequestBuilder(accessCode: { "am-secret" })

    private func body(_ request: URLRequest) -> [String: Any] {
        guard let data = request.httpBody,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func testGetCarriesTheCodeInAHeaderNotTheURL() {
        let req = builder.get("/whoami")
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.url?.absoluteString, "https://api.kinbir.com/whoami")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Access-Code"), "am-secret")
        XCTAssertFalse(req.url!.absoluteString.contains("am-secret"))
    }

    func testDelete() {
        let req = builder.get("/voices/v123", method: "DELETE")
        XCTAssertEqual(req.httpMethod, "DELETE")
        XCTAssertEqual(req.url?.path, "/voices/v123")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Access-Code"), "am-secret")
    }

    func testPostCarriesTheCodeInTheBody() {
        let req = builder.post("/generate", body: ["text": "ሰላም"])
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let sent = body(req)
        XCTAssertEqual(sent["access_code"] as? String, "am-secret")
        XCTAssertEqual(sent["text"] as? String, "ሰላም")
    }

    func testSignInPostsCarryNoCode() {
        let req = builder.post("/auth/verify", body: ["email": "a@b.co", "code": "123456"],
                               authenticated: false)
        XCTAssertNil(body(req)["access_code"])
    }

    func testGenerateNeverAsksForEnglish() {
        // Rule 1 of the spec: Amharic output only.
        let req = builder.post("/generate", body: ["text": "ሰላም"])
        XCTAssertNil(body(req)["language"])
    }

    func testSignedOutGetSendsAnEmptyHeader() {
        let anonymous = RequestBuilder(accessCode: { nil })
        XCTAssertEqual(anonymous.get("/enroll/script").value(forHTTPHeaderField: "X-Access-Code"), "")
    }
}

final class MultipartTests: XCTestCase {
    func testBodyLayout() {
        var form = Multipart(boundary: "BOUND")
        form.addField(name: "language", value: "am")
        form.addFile(name: "video", filename: "enroll.mov", mimeType: "video/quicktime",
                     data: Data("VIDEO".utf8))
        let text = String(data: form.finished(), encoding: .utf8)!
        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=BOUND")
        XCTAssertTrue(text.hasPrefix("--BOUND\r\n"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"language\"\r\n\r\nam\r\n"))
        XCTAssertTrue(text.contains("name=\"video\"; filename=\"enroll.mov\"\r\nContent-Type: video/quicktime\r\n\r\nVIDEO\r\n"))
        XCTAssertTrue(text.hasSuffix("--BOUND--\r\n"))
    }

    func testMimeTypes() {
        XCTAssertEqual(Multipart.mimeType(forExtension: "MOV"), "video/quicktime")
        XCTAssertEqual(Multipart.mimeType(forExtension: "mp4"), "video/mp4")
        XCTAssertEqual(Multipart.mimeType(forExtension: "xyz"), "application/octet-stream")
    }
}

final class ErrorTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testExpiredSession() {
        let e = APIError.from(status: 401, data: data(#"{"detail":"unknown access code"}"#), path: "/whoami")
        XCTAssertEqual(e.kind, .sessionExpired)
        XCTAssertTrue(e.message.contains("Sign in again"))
    }

    func testWrongSignInCodeKeepsTheServerSentence() {
        let e = APIError.from(status: 401,
                              data: data(#"{"detail":"that code is not right - 4 tries left"}"#),
                              path: "/auth/verify")
        XCTAssertEqual(e.kind, .other)
        XCTAssertEqual(e.message, "That code is not right - 4 tries left")
    }

    func testOutOfCredits() {
        let e = APIError.from(status: 402,
                              data: data(#"{"detail":"insufficient credits (need ~2.5, have 0.0)"}"#),
                              path: "/generate")
        XCTAssertEqual(e.kind, .needsCredits)
        XCTAssertTrue(e.message.contains("insufficient credits"))
        XCTAssertTrue(e.message.contains(APIError.buyingNote))
    }

    func testServerErrorWithNoUsefulSentence() {
        let e = APIError.from(status: 500, data: data(#"{"detail":"Internal Server Error"}"#), path: "/jobs")
        XCTAssertEqual(e.kind, .server)
        XCTAssertTrue(e.message.contains("our side"))
    }

    func testServerErrorWithAUsefulSentence() {
        let e = APIError.from(status: 503, data: data(#"{"detail":"generation is paused by the admin"}"#),
                              path: "/generate")
        XCTAssertEqual(e.message, "generation is paused by the admin")
    }

    func testStructuredDetail() {
        let e = APIError.from(status: 400, data: data(#"{"detail":{"message":"too long","shots":[1,2]}}"#),
                              path: "/generate")
        XCTAssertEqual(e.message, "Too long")
    }

    func testNotJSON() {
        let e = APIError.from(status: 404, data: data("<html>"), path: "/jobs/x")
        XCTAssertEqual(e.kind, .other)
        XCTAssertFalse(e.message.isEmpty)
    }

    func testWrapNetworkError() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(APIError.wrap(offline).kind, .network)
    }

    func testWrapKeepsAnAPIError() {
        let original = APIError(kind: .needsCredits, status: 402, message: "x")
        XCTAssertEqual(APIError.wrap(original), original)
    }
}

final class SSETests: XCTestCase {
    func testDelta() {
        XCTAssertEqual(SSEParser.parse(line: #"data: {"type":"delta","text":"ሰላም "}"#), .delta("ሰላም "))
    }

    func testDone() {
        let line = #"data: {"type":"done","skipped":false,"amharic":"ሰላም።","draft_id":"d1","credits_charged":1.5,"credits_balance":18.5,"warnings":[]}"#
        guard case .done(let result)? = SSEParser.parse(line: line) else {
            return XCTFail("expected a done event")
        }
        XCTAssertEqual(result.amharic, "ሰላም።")
        XCTAssertEqual(result.draftId, "d1")
        XCTAssertEqual(result.creditsBalance, 18.5)
    }

    func testError() {
        XCTAssertEqual(SSEParser.parse(line: #"data: {"type":"error","error":"model busy"}"#),
                       .error("model busy"))
    }

    func testIgnoresOtherLines() {
        XCTAssertNil(SSEParser.parse(line: ""))
        XCTAssertNil(SSEParser.parse(line: ": keep-alive"))
        XCTAssertNil(SSEParser.parse(line: "event: message"))
        XCTAssertNil(SSEParser.parse(line: "data: not json"))
        XCTAssertNil(SSEParser.parse(line: #"data: {"type":"ping"}"#))
    }
}

/// Real answer shapes copied from the Kinbir server code, so a mismatch shows here
/// and not on a customer's phone.
final class DecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSON.decoder.decode(T.self, from: Data(json.utf8))
    }

    func testWhoAmI() throws {
        let me = try decode(WhoAmI.self, """
        {"email":"geni@example.com",
         "voices":[{"voice_id":"v1","name":"Calm","active":true,"created_at":"2026-08-01T00:00:00Z",
                    "badge":"green","re_enrollment":false},
                   {"voice_id":"v2","name":null,"active":false,"created_at":null,"badge":null,
                    "re_enrollment":true,"ref_language":"en"}],
         "active_voice_id":"v1","daily_cap":300,"used_today":0,"credits_balance":17.5,
         "tier":null,"monthly_allowance":0,"internal":false,"has_paid":false,
         "trial_max_chars":900,"has_subscription":false,"has_billing_history":false,
         "enroll_attempts_30d":1,"en_pace":"natural","en_emphasis":"some",
         "script_rules":"","script_rules_default":"x","script_rules_enabled":true}
        """)
        XCTAssertEqual(me.email, "geni@example.com")
        XCTAssertEqual(me.balance, 17.5)
        XCTAssertEqual(me.trialMaxChars, 900)
        XCTAssertEqual(me.voices?.count, 2)
        XCTAssertEqual(me.amharicVoices.map(\.voiceId), ["v1"], "English voices are hidden")
        XCTAssertTrue(me.hasVoice)
    }

    func testWhoAmIForABrandNewAccount() throws {
        let me = try decode(WhoAmI.self, """
        {"email":"new@example.com","voices":[],"active_voice_id":null,"credits_balance":0.0,
         "tier":null,"has_paid":false,"trial_max_chars":900}
        """)
        XCTAssertFalse(me.hasVoice)
        XCTAssertEqual(me.balance, 0)
        XCTAssertNil(me.activeVoiceId)
    }

    func testPaidAccountHasNoTrialLimit() throws {
        let me = try decode(WhoAmI.self, #"{"email":"p@example.com","voices":[],"credits_balance":110,"tier":"starter","has_paid":true,"trial_max_chars":null}"#)
        XCTAssertNil(me.trialMaxChars)
        XCTAssertEqual(me.tier, "starter")
    }

    func testAuthVerify() throws {
        let a = try decode(AuthResult.self, #"{"access_code":"am-XyZ","email":"a@b.co","is_new":true,"has_voice":false,"credits_balance":0.0}"#)
        XCTAssertEqual(a.accessCode, "am-XyZ")
        XCTAssertEqual(a.isNew, true)
    }

    func testEnrollScript() throws {
        let s = try decode(EnrollScript.self, #"{"enroll_text":"ሀ","personal":"ለ","personal_en":"x"}"#)
        XCTAssertEqual(s.text, "ለ")
        let old = try decode(EnrollScript.self, #"{"enroll_text":"ሀ"}"#)
        XCTAssertEqual(old.text, "ሀ")
    }

    func testEnrollApproved() throws {
        let r = try decode(EnrollResult.self, """
        {"status":"approved","voice_id":"v9","badge":"amber","quality":{"snr_db":18.2,"badge":"amber"},
         "advice":["too quiet - move closer to the mic"],"needs_review":false,"active":true,
         "credits_granted":20,"credits_balance":20.0,"message":"your voice is ready"}
        """)
        XCTAssertTrue(r.isApproved)
        XCTAssertEqual(r.creditsGranted, 20)
        XCTAssertEqual(r.advice?.count, 1)
    }

    func testEnrollPending() throws {
        let r = try decode(EnrollResult.self, #"{"status":"pending","pending_id":"p1","message":"Thanks"}"#)
        XCTAssertFalse(r.isApproved)
    }

    func testGenerateSubmit() throws {
        let g = try decode(GenerateSubmit.self, """
        {"job_id":"job-abc","status":"queued","segments_total":3,"warnings":[],"pair_logged":false,
         "credits_reserved":2.5,"credits_balance":15.0,"status_url":"/jobs/job-abc"}
        """)
        XCTAssertEqual(g.jobId, "job-abc")
        XCTAssertEqual(g.segmentsTotal, 3)
    }

    func testJobStatusRunningAndDone() throws {
        let running = try decode(JobStatus.self, #"{"job_id":"job-1","status":"running","segments_done":1,"segments_total":3}"#)
        XCTAssertTrue(running.isRunning)
        XCTAssertFalse(running.isDone)

        let done = try decode(JobStatus.self, """
        {"job_id":"job-1","type":"generate","status":"done","language":"am","segments_done":3,
         "segments_total":3,"audio_sec":61.2,"parts":3,"segments":["ሰላም።","እንዴት ናችሁ።"],
         "segment_offsets":[0,5],"fixed_words":[],"pace":"natural","credits_charged":2.5,
         "credits_balance":15.0,"audio_url":"/jobs/job-1/audio"}
        """)
        XCTAssertTrue(done.isDone)
        XCTAssertEqual(done.audioSec, 61.2)
        XCTAssertEqual(done.scriptText, "ሰላም። እንዴት ናችሁ።")
    }

    func testJobFailed() throws {
        let j = try decode(JobStatus.self, #"{"job_id":"job-2","status":"failed","error":"engine timeout"}"#)
        XCTAssertTrue(j.isFailed)
        XCTAssertEqual(j.error, "engine timeout")
    }

    func testJobsList() throws {
        let list = try decode(JobsList.self, """
        {"jobs":[{"job_id":"job-1","status":"done","created_at":"2026-11-12T10:00:00Z",
                  "finished_at":"2026-11-12T10:02:00Z","audio_sec":30.5,"chars":400,
                  "orientation":"vertical","voice_id":"v1","preview":"ሰላም","can_make_video":true}],
         "total":1,"kept_hours":48}
        """)
        XCTAssertEqual(list.jobs.count, 1)
        XCTAssertEqual(list.keptHours, 48)
        XCTAssertEqual(list.jobs[0].preview, "ሰላም")
    }

    func testRewriteSkippedBecauseAlreadyAmharic() throws {
        let r = try decode(RewriteResult.self, """
        {"skipped":true,"reason":"input is already Amharic","amharic":"ሰላም።","mode":"video",
         "chunks":[{"i":0,"syllables":3}],"digits_found":false,"warnings":[]}
        """)
        XCTAssertEqual(r.skipped, true)
        XCTAssertEqual(r.amharic, "ሰላም።")
    }

    func testExtractAndEstimateAndDemo() throws {
        let x = try decode(ExtractResult.self, #"{"title":null,"text":"Body","chars":4,"note":""}"#)
        XCTAssertEqual(x.text, "Body")
        let e = try decode(RewriteEstimate.self, #"{"credits_estimated":3}"#)
        XCTAssertEqual(e.creditsEstimated, 3)
        let d = try decode(DemoRef.self, #"{"demo_id":"demo-1","status":"done","cached":true,"audio_url":"/demo/demo-1/audio"}"#)
        XCTAssertTrue(d.isDone)
    }
}

/// Collects streamed text from a closure.
private final class TextBox {
    var text = ""
}

final class MockServerTests: XCTestCase {
    func testToneFileIsAValidWav() {
        let wav = ToneFile.data(seconds: 0.5, sampleRate: 8_000)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertEqual(wav.count, 44 + 4_000 * 2)
    }

    func testWholeJourneyOnTheMockServer() async throws {
        let api = MockAPI(scenario: .init(noVoice: true))

        let auth = try await api.verify(email: MockAPI.email, code: MockAPI.goodCode)
        XCTAssertEqual(auth.hasVoice, false)

        do {
            _ = try await api.generate(text: "ሰላም", draftId: nil)
            XCTFail("generating with no voice must be refused")
        } catch {}

        let enrolled = try await api.enroll(videoURL: URL(fileURLWithPath: "/tmp/x.mov"))
        XCTAssertTrue(enrolled.isApproved)
        XCTAssertEqual(enrolled.creditsGranted, 20)

        let streamed = TextBox()
        let script = try await api.rewrite(text: "Hello") { piece in streamed.text += piece }
        XCTAssertFalse(streamed.text.isEmpty)
        XCTAssertEqual(script.amharic, MockAPI.amharicScript)

        let submit = try await api.generate(text: script.amharic ?? "", draftId: script.draftId)
        var job = try await api.job(id: submit.jobId)
        XCTAssertTrue(job.isRunning)
        job = try await api.job(id: submit.jobId)
        XCTAssertTrue(job.isDone)

        let audio = try await api.playbackAudio(jobId: submit.jobId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))

        let list = try await api.jobs()
        XCTAssertEqual(list.first?.jobId, submit.jobId)

        let me = try await api.whoami()
        XCTAssertEqual(me.balance, 20 - 1 - 2.5)
    }

    func testWrongCodeAndNoCredits() async {
        let api = MockAPI(scenario: .init(noCredits: true))
        do {
            _ = try await api.verify(email: MockAPI.email, code: "000000")
            XCTFail("a wrong code must be refused")
        } catch {
            XCTAssertEqual(APIError.wrap(error).status, 401)
        }
        do {
            _ = try await api.generate(text: "ሰላም", draftId: nil)
            XCTFail("generating with no credits must be refused")
        } catch {
            XCTAssertEqual(APIError.wrap(error).kind, .needsCredits)
        }
    }

    #if canImport(SwiftUI)
    @MainActor
    func testAppStateSignInAndForcedSignOut() async {
        let store = MemoryCodeStore()
        let state = AppState(api: MockAPI(), store: store)
        await state.start()
        XCTAssertEqual(state.phase, .signedOut)

        await state.signIn(with: AuthResult(accessCode: "am-mock-code", email: MockAPI.email,
                                            isNew: false, hasVoice: true, creditsBalance: 20))
        XCTAssertEqual(state.phase, .signedIn)
        XCTAssertEqual(store.load(), "am-mock-code")
        XCTAssertEqual(state.activeVoice?.voiceId, "v-mock-1")

        state.saveDraft("ሰላም")
        XCTAssertEqual(state.loadDraft(), "ሰላም")

        let expired = APIError.from(status: 401, data: Data(), path: "/whoami")
        _ = state.report(expired)
        XCTAssertEqual(state.phase, .signedOut)
        XCTAssertNil(store.load())
        XCTAssertNotNil(state.notice)
    }
    #endif
}

/// Footage, music and video: real answer shapes from the server code.
final class VideoDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSON.decoder.decode(T.self, from: Data(json.utf8))
    }

    func testPlanJobDone() throws {
        let job = try decode(PlanJob.self, """
        {"job_id":"job-p1","type":"broll_plan","status":"done",
         "result":{"plan_id":"bp-1","timing":"measured","chunks":2,"audio_sec":6.2,
           "beats":[{"beat":1,"chunk":0,"start":0,"end":3.1,"dur":3.1,"says":"ሰላም።",
                     "must_show":"people waving","query":"people waving","fallback":"crowd"},
                    {"beat":2,"chunk":1,"start":3.1,"end":6.2,"dur":3.1,"type":"gap",
                     "must_show":"","query":"","fallback":""}],
           "warnings":[],"cost_usd":0.11,"credits_estimated":3,"credits_charged":2.5,
           "credits_adjustment":-0.5,"credits_balance":14.5}}
        """)
        XCTAssertEqual(job.status, "done")
        XCTAssertEqual(job.result?.planId, "bp-1")
        let beats = job.result?.beats ?? []
        XCTAssertEqual(beats.count, 2)
        XCTAssertTrue(beats[0].isEmpty, "a talk shot with no clip needs footage")
        XCTAssertFalse(beats[1].needsFootage, "a music break needs none")
        XCTAssertFalse(beats[1].isEmpty)
    }

    func testSearchResultWithClips() throws {
        let r = try decode(SearchResult.self, """
        {"plan_id":"bp-1","orientation":"portrait","searched":1,"gaps":[],"remaining":0,"note":"",
         "beats":[{"beat":1,"start":0,"end":3,"dur":3,"status":"ok","must_show":"x","query":"x",
           "candidates":[{"clip_id":123,"url":"https://www.pexels.com/video/123","duration":7,
             "width":1080,"height":1920,"link":"https://cdn/x.mp4","preview_link":"https://cdn/p.mp4",
             "poster":"https://images.pexels.com/1.jpg?w=420","matched":["wave"],"score":0.4,
             "desc":"People waving","author":"A","author_url":"u","licence":"pexels","source":"pexels",
             "via_query":"people waving"},
            {"clip_id":9,"link":"/models/uploads/up-abc.mov","preview_link":"/models/uploads/up-abc.mov",
             "poster":null,"own_upload":true,"clip_start":1.5,"kind":"video"}]}]}
        """)
        XCTAssertFalse(r.stockLimited)
        let beat = try XCTUnwrap(r.beats?.first)
        XCTAssertEqual(beat.chosen?.clipId, 123, "the clip in use is the first candidate")
        XCTAssertNotNil(beat.chosen?.posterURL)
        XCTAssertFalse(beat.isEmpty)
        XCTAssertTrue(beat.candidates?[1].isOwn == true)
        XCTAssertNil(beat.candidates?[1].posterURL)
    }

    func testStockLimitIsDetected() throws {
        // The server still answers 200 when the stock library says "not now".
        let limited = try decode(SearchResult.self, #"{"plan_id":"bp-1","searched":0,"gaps":[],"remaining":12,"beats":[],"retry_after":30}"#)
        XCTAssertTrue(limited.stockLimited)
        let stalled = try decode(SearchResult.self, #"{"plan_id":"bp-1","searched":0,"gaps":[],"remaining":5,"beats":[]}"#)
        XCTAssertTrue(stalled.stockLimited)
        let finished = try decode(SearchResult.self, #"{"plan_id":"bp-1","searched":0,"gaps":[2],"remaining":0,"beats":[]}"#)
        XCTAssertFalse(finished.stockLimited)
    }

    func testAssembleStatusDone() throws {
        let s = try decode(AssembleStatus.self, """
        {"job_id":"vid-1","status":"done","files_done":8,"files_total":8,"bytes":1234,"duration_sec":61.0,
         "quality":"1080p","download_url":"/assemble/vid-1/video.mp4",
         "stream_url":"/assemble/vid-1/video.mp4?e=1&t=abc","preview_url":"/assemble/vid-1/preview.mp4?e=1&t=abc"}
        """)
        XCTAssertTrue(s.isDone)
        XCTAssertTrue(s.isOver)
        XCTAssertEqual(s.playPath, "/assemble/vid-1/preview.mp4?e=1&t=abc")
        let running = try decode(AssembleStatus.self, #"{"status":"running","files_done":2,"files_total":8}"#)
        XCTAssertFalse(running.isOver)
    }

    func testUploadsMusicAndVideos() throws {
        let u = try decode(UploadList.self, #"{"uploads":[{"upload_id":"up-1.mov","name":"IMG_1.MOV","kind":"video","duration":12.5,"width":1080,"height":1920,"bytes":999,"owned":true,"job_id":"job-1","label_status":"pending"}]}"#)
        XCTAssertEqual(u.uploads.first?.uploadId, "up-1.mov")
        let m = try decode(MusicList.self, #"{"tracks":[{"track_id":"calm.mp3","kind":"kinbir","title":"Calm","bytes":10}],"note":""}"#)
        XCTAssertEqual(m.tracks.first?.title, "Calm")
        let v = try decode(VideoList.self, #"{"videos":[{"video_job_id":"vid-1","plan_id":"bp-1","job_id":"job-1","orientation":"portrait","duration_sec":61,"finished_at":"2026-11-12T10:00:00Z","avatar_file":false,"preview":"ሰላም"}],"total":1,"kept_hours":48}"#)
        XCTAssertEqual(v.videos.first?.videoJobId, "vid-1")
    }

    func testAbsoluteURLs() {
        let b = RequestBuilder(accessCode: { nil })
        XCTAssertEqual(b.absolute("/assemble/v/preview.mp4?e=1&t=a")?.absoluteString,
                       "https://api.kinbir.com/assemble/v/preview.mp4?e=1&t=a")
        XCTAssertEqual(b.absolute("https://cdn.example.com/x.mp4")?.host, "cdn.example.com")
        XCTAssertNil(b.absolute(nil))
        XCTAssertNil(b.absolute(""))
    }

    func testClipRules() {
        XCTAssertTrue(ClipRules.isAllowed(URL(fileURLWithPath: "/tmp/a.MOV")))
        XCTAssertFalse(ClipRules.isAllowed(URL(fileURLWithPath: "/tmp/a.pdf")))
        XCTAssertEqual(ClipRules.partCount(bytes: 1), 1)
        XCTAssertEqual(ClipRules.partCount(bytes: ClipRules.chunkBytes), 1)
        XCTAssertEqual(ClipRules.partCount(bytes: ClipRules.chunkBytes + 1), 2)
    }

    func testVideoJourneyOnTheMockServer() async throws {
        let api = MockAPI()
        _ = try await api.planFootage(jobId: "job-1", shape: .portrait, source: .stock)
        var plan = try await api.planJob(id: "job-mock-plan")
        XCTAssertEqual(plan.status, "running")
        plan = try await api.planJob(id: "job-mock-plan")
        let planId = try XCTUnwrap(plan.result?.planId)

        do {
            _ = try await api.assemble(planId: planId, shape: .portrait, musicId: nil, captions: false, avatar: nil)
            XCTFail("a video with empty shots must be refused")
        } catch {}

        let search = try await api.searchFootage(planId: planId, shape: .portrait, beat: nil, query: nil)
        XCTAssertEqual(search.remaining, 0)
        var beats = try await api.plan(id: planId).beats ?? []
        XCTAssertTrue(beats.allSatisfy { !$0.isEmpty })

        let second = try XCTUnwrap(beats[0].candidates?[1])
        try await api.chooseClip(planId: planId, beat: 1, clipId: second.clipId)
        beats = try await api.plan(id: planId).beats ?? []
        XCTAssertEqual(beats[0].chosen?.clipId, second.clipId)

        let submit = try await api.assemble(planId: planId, shape: .portrait, musicId: "calm.mp3", captions: true, avatar: nil)
        var status = try await api.assembleStatus(id: submit.jobId)
        XCTAssertFalse(status.isOver)
        status = try await api.assembleStatus(id: submit.jobId)
        XCTAssertTrue(status.isDone)
        let list = try await api.videos()
        XCTAssertEqual(list.first?.videoJobId, submit.jobId)
    }
}

final class AvatarTests: XCTestCase {
    func testCreditsMatchTheServerFormula() {
        // api/avatar.py: 14 s is 5.5 credits as a side panel and 22 full frame.
        XCTAssertEqual(AvatarChoice.credits(seconds: 14, fullFrame: false), 5.5)
        XCTAssertEqual(AvatarChoice.credits(seconds: 14, fullFrame: true), 22)
        XCTAssertEqual(AvatarChoice.credits(seconds: 1, fullFrame: false), 0.5)
        XCTAssertEqual(AvatarChoice.credits(seconds: 0, fullFrame: true), 0)
    }

    func testTotalSeconds() {
        var a = AvatarChoice()
        XCTAssertEqual(a.totalSeconds(audioSec: 60), 0, "off means nothing")
        a.enabled = true
        XCTAssertEqual(a.totalSeconds(audioSec: 60), 14)
        a.atEnd = true
        XCTAssertEqual(a.totalSeconds(audioSec: 60), 28)
        XCTAssertEqual(a.totalSeconds(audioSec: 40), 14, "start and end too close: only one fits")
        a.wholeVideo = true
        XCTAssertEqual(a.totalSeconds(audioSec: 60), 60)
        a.wholeVideo = false
        a.atEnd = false
        XCTAssertEqual(a.totalSeconds(audioSec: 6), 6, "never longer than the voiceover")
    }

    func testPayload() {
        var a = AvatarChoice()
        a.enabled = true
        a.seconds = 8
        a.mode = .separate
        let p = a.payload
        XCTAssertEqual(p["seconds"] as? Int, 8)
        XCTAssertEqual(p["mode"] as? String, "separate")
        XCTAssertEqual((p["placements"] as? [String: Any])?["start"] as? Bool, true)
    }

    func testDecoding() throws {
        let none = try JSON.decoder.decode(AvatarInfo.self, from: Data(#"{"has_photo":false,"verified":false}"#.utf8))
        XCTAssertFalse(none.isReady)
        let ok = try JSON.decoder.decode(AvatarInfo.self, from: Data(#"{"has_photo":true,"verified":true,"face_checked":false,"needs_review":false,"checked_at":"2026-11-12T10:00:00Z"}"#.utf8))
        XCTAssertTrue(ok.isReady)
        let s = try JSON.decoder.decode(AssembleStatus.self, from: Data(#"{"status":"done","avatar_seconds":14,"avatar_skipped":"the end appearance did not fit","avatar_mode":"separate","avatar_file":true,"avatar_files":[[0,14]]}"#.utf8))
        XCTAssertEqual(s.avatarFile, true)
        XCTAssertEqual(s.avatarSkipped, "the end appearance did not fit")
    }
}

final class ExtrasTests: XCTestCase {
    func testAmharicScriptOptionsSendNothingExtra() {
        XCTAssertTrue(ScriptOptions().fields.isEmpty)
    }

    func testLengthIsKeptInsideWhatTheServerAccepts() {
        XCTAssertEqual(ScriptOptions(targetSec: 60).fields["target_sec"] as? Int, 60)
        XCTAssertEqual(ScriptOptions(targetSec: 1200).fields["target_sec"] as? Int, 600)
        XCTAssertEqual(ScriptOptions(targetSec: 5).fields["target_sec"] as? Int, 15)
        XCTAssertTrue(ScriptOptions.lengths.allSatisfy { $0 >= 15 && $0 <= 600 })
    }

    func testRefineChangesTheScriptAndDoesNotAskForALength() {
        let f = ScriptOptions(language: .en, targetSec: 60, refineInstruction: "make it shorter").fields
        XCTAssertEqual(f["mode"] as? String, "refine")
        XCTAssertEqual(f["instruction"] as? String, "make it shorter")
        XCTAssertEqual(f["effort"] as? String, "medium")
        XCTAssertEqual(f["language"] as? String, "en")
        XCTAssertNil(f["target_sec"], "a length would make the server rebuild the script")
    }

    func testVoiceOptions() {
        XCTAssertTrue(VoiceOptions().fields.isEmpty, "Amharic sends no language, pace or emphasis")
        let en = VoiceOptions(language: .en, pace: "fast", emphasis: "punchy").fields
        XCTAssertEqual(en["language"] as? String, "en")
        XCTAssertEqual(en["pace"] as? String, "fast")
        XCTAssertEqual(en["emphasis"] as? String, "punchy")
    }

    func testFixPayloads() {
        XCTAssertEqual(FixEdit.option(word: "ቡና", optionId: 2).payload["option_id"] as? Int, 2)
        XCTAssertEqual(FixEdit.custom(word: "ቡና", spelling: "bunna").payload["custom"] as? String, "bunna")
        let reread = FixEdit.rereadSentence(segment: 3).payload
        XCTAssertEqual(reread["segment"] as? Int, 3)
        XCTAssertNil(reread["word"])
        XCTAssertNil(reread["text"], "the same words are read again")
        let edit = FixEdit.editSentence(segment: 1, text: "ሰላም።").payload
        XCTAssertEqual(edit["segment"] as? Int, 1)
        XCTAssertEqual(edit["text"] as? String, "ሰላም።")
        // One change per word and per sentence: a newer choice replaces the older one.
        XCTAssertEqual(FixEdit.option(word: "ቡና", optionId: 1).id, FixEdit.custom(word: "ቡና", spelling: "x").id)
        XCTAssertEqual(FixEdit.rereadSentence(segment: 2).id, FixEdit.editSentence(segment: 2, text: "y").id)
        XCTAssertNotEqual(FixEdit.rereadSentence(segment: 2).id, FixEdit.rereadSentence(segment: 3).id)
    }

    func testWordsAreRunsOfEthiopicLettersLikeTheWebsite() {
        let tokens = Words.tokens(in: "ሰላም፣ ለሁላችሁ። AI 2026")
        XCTAssertEqual(tokens.map(\.shown), ["ሰላም", "፣", "ለሁላችሁ", "።", "AI", "2026"])
        XCTAssertEqual(tokens.map(\.word), ["ሰላም", "", "ለሁላችሁ", "", "", ""], "only Ethiopic words can be fixed")
        XCTAssertEqual(tokens.map(\.spaceBefore), [false, false, true, false, true, true])
        // No space between two words: the website still sees two words, not one merged word.
        XCTAssertEqual(Words.tokens(in: "ነው።ስለዚህ ስነ-ልቦና").map(\.word), ["ነው", "", "ስለዚህ", "ስነ", "", "ልቦና"])
    }

    func testSentencesAndClausesLikeTheWebsite() {
        let segments = ["ሰላም፣ እንዴት ናችሁ። ዛሬ ስለ ቡና እናወራለን።", "ቡና ከኢትዮጵያ ነው"]
        XCTAssertEqual(Script.clauses(segments[0]).count, 3)
        let sentences = Script.sentences(segments)
        XCTAssertEqual(sentences.map(\.text), ["ሰላም፣ እንዴት ናችሁ።", "ዛሬ ስለ ቡና እናወራለን።", "ቡና ከኢትዮጵያ ነው"])
        XCTAssertEqual(sentences.map(\.parts), [[0, 1], [2], [0]])
        XCTAssertEqual(sentences.map(\.segment), [0, 0, 1])
    }

    func testWhatIsSentForSentenceChanges() {
        let segments = ["ሰላም፣ እንዴት ናችሁ። ዛሬ ስለ ቡና እናወራለን።", "ቡና ከኢትዮጵያ ነው።"]
        let s = Script.sentences(segments)
        // Read again: one entry per clause, with rerecord.
        let reread = PendingFix.wire([.reread(s[0])], segments: segments)
        XCTAssertEqual(reread, [.rereadPart(segment: 0, part: 0), .rereadPart(segment: 0, part: 1)])
        XCTAssertEqual(reread[0].payload["rerecord"] as? Bool, true)
        XCTAssertEqual(reread[1].payload["part"] as? Int, 1)
        // Same number of clauses: clause by clause.
        let same = PendingFix.wire([.edit(s[0], text: "ጤና ይስጥልኝ፣ እንዴት ናችሁ።")], segments: segments)
        XCTAssertEqual(same.count, 2)
        XCTAssertEqual(same[0].payload["text"] as? String, "ጤና ይስጥልኝ፣")
        XCTAssertEqual(same[0].payload["part"] as? Int, 0)
        // A comma removed: the whole segment once, and a re-read in that segment is dropped.
        let changed = PendingFix.wire([.edit(s[0], text: "ሰላም እንዴት ናችሁ።"), .reread(s[1]), .reread(s[2])],
                                      segments: segments)
        XCTAssertEqual(changed.first, .editSentence(segment: 0, text: "ሰላም እንዴት ናችሁ። ዛሬ ስለ ቡና እናወራለን።"))
        XCTAssertEqual(Array(changed.dropFirst()), [.rereadPart(segment: 1, part: 0)])
        // The whole script: every segment.
        let all = PendingFix.wholeScript([.word(.option(word: "ቡና", optionId: 1), label: "ቡና")], segments: segments)
        XCTAssertEqual(all, [.option(word: "ቡና", optionId: 1), .rereadSentence(segment: 0), .rereadSentence(segment: 1)])
        XCTAssertEqual(PendingFix.reread(s[1]).id, PendingFix.edit(s[1], text: "x").id)
    }

    func testDecoding() throws {
        let c = try JSON.decoder.decode(FixCandidates.self, from: Data(#"{"word":"ቡና","options":[{"option_id":0,"label":"Option A"},{"option_id":1,"label":"Option B"}],"allow_custom":true,"note":""}"#.utf8))
        XCTAssertEqual(c.options?.count, 2)
        let p = try JSON.decoder.decode(FixPreview.self, from: Data(#"{"preview_id":"pv1","status":"queued","preview_url":null,"first_ever":true}"#.utf8))
        XCTAssertFalse(p.isDone)
        let b = try JSON.decoder.decode(FixBatch.self, from: Data(#"{"batch_id":"fx1","status":"queued","words":["ቡና"],"charged":1.5,"credits_balance":10}"#.utf8))
        XCTAssertEqual(b.batchId, "fx1")
        XCTAssertFalse(b.isOver)
        let me = try JSON.decoder.decode(WhoAmI.self, from: Data(#"{"email":"a@b.co","voices":[{"voice_id":"v2","ref_language":"en"}],"en_pace":"fast","en_emphasis":"strong","script_rules":"Short sentences.","script_rules_default":"T"}"#.utf8))
        XCTAssertEqual(me.enPace, "fast")
        XCTAssertEqual(me.scriptRules, "Short sentences.")
        XCTAssertTrue(me.hasVoice, "an English voice is a voice")
        let job = try JSON.decoder.decode(JobStatus.self, from: Data(#"{"job_id":"j","status":"done","language":"en","emphasis":"punchy","fixed_words":[]}"#.utf8))
        XCTAssertTrue(job.isEnglish)
    }

    func testEnglishJourneyOnTheMockServer() async throws {
        let api = MockAPI()
        let submit = try await api.generate(text: "Hello there.", draftId: nil,
                                            voice: VoiceOptions(language: .en, pace: "slow", emphasis: "none"))
        _ = try await api.job(id: submit.jobId)
        let job = try await api.job(id: submit.jobId)
        XCTAssertTrue(job.isEnglish)
        XCTAssertEqual(api.video.lastVoiceOptions?.pace, "slow")

        let batch = try await api.fixApply(jobId: submit.jobId, fixes: [
            .rereadSentence(segment: 0), .option(word: "ሰላም", optionId: 1),
        ])
        XCTAssertEqual(api.video.appliedFixes.count, 2, "all changes go in one request")
        var status = try await api.fixStatus(jobId: submit.jobId, batchId: batch.batchId ?? "")
        XCTAssertFalse(status.isOver)
        status = try await api.fixStatus(jobId: submit.jobId, batchId: batch.batchId ?? "")
        XCTAssertEqual(status.status, "done")
        let saved = try await api.saveScriptRules("Be brief.")
        XCTAssertEqual(saved, "Be brief.")
        let me = try await api.whoami()
        XCTAssertEqual(me.scriptRules, "Be brief.")
    }
}

final class LibraryFilterTests: XCTestCase {
    private func row(_ id: String, _ status: String, audio: Double? = nil, preview: String? = nil,
                     voice: String? = nil) -> JobSummary {
        JobSummary(jobId: id, status: status, createdAt: nil, finishedAt: nil, audioSec: audio,
                   preview: preview, voiceId: voice)
    }

    func testOnlyRealVoiceoversAreListed() {
        // The server's list also holds script writing, footage plans and renders.
        XCTAssertTrue(row("job-1", "done", audio: 30, preview: "ሰላም", voice: "v1").belongsInLibrary)
        XCTAssertTrue(row("job-2", "running", voice: "v1").belongsInLibrary, "a voiceover being made")
        XCTAssertFalse(row("job-3", "done", preview: "plan").belongsInLibrary, "a footage plan has no audio")
        XCTAssertFalse(row("job-4", "running").belongsInLibrary, "a running plan carries no voice")
        XCTAssertFalse(row("vid-5", "done", audio: 30, preview: "x").belongsInLibrary, "videos have their own list")
        XCTAssertFalse(row("job-6", "failed", voice: "v1").belongsInLibrary)
    }

    func testFaithfulMode() {
        var o = ScriptOptions()
        o.faithful = true
        XCTAssertEqual(o.fields["mode"] as? String, "faithful")
        o.fromIdea = true
        XCTAssertEqual(o.fields["mode"] as? String, "brief", "an idea is written from scratch")
    }
}
