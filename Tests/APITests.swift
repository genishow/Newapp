import XCTest
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
}
