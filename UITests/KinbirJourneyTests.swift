import XCTest

/// End-to-end tests. They launch the real app with its built-in mock server
/// (`-uiTestMock`) and drive the real screens, start to finish.
final class KinbirJourneyTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: helpers

    private func launch(_ extra: [String] = []) {
        app.launchArguments = ["-uiTestMock"] + extra
        app.launch()
    }

    /// Any element with this accessibility identifier, whatever its type.
    private func el(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func waitFor(_ id: String, timeout: TimeInterval = 15,
                         file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = el(id)
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "\(id) did not appear", file: file, line: line)
        // Every screen has a heading, so this keeps one picture of each screen in the results.
        if id.hasSuffix("Heading") { snap(id) }
        return element
    }

    /// Keeps a picture of the screen in the test results, so the screens can be looked at
    /// after a run without a phone.
    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForLabel(_ id: String, contains text: String, timeout: TimeInterval = 15,
                              file: StaticString = #filePath, line: UInt = #line) {
        let element = el(id)
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let outcome = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(outcome, .completed,
                       "\(id) never showed \"\(text)\". It shows \"\(element.exists ? element.label : "nothing")\"",
                       file: file, line: line)
    }

    /// Flips a switch. The switch itself sits at the right edge of its row.
    private func flip(_ id: String) {
        waitFor(id).coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    private func signIn(code: String = "123456") {
        waitFor("startButton").tap()
        let email = waitFor("emailField")
        email.tap()
        email.typeText("tester@example.com")
        waitFor("sendCodeButton").tap()
        waitForLabel("codeSentNotice", contains: "10 minutes")
        let field = waitFor("codeField")
        field.tap()
        field.typeText(code)
        waitFor("verifyButton").tap()
    }

    private func type(_ text: String, into id: String) {
        let editor = waitFor(id)
        editor.tap()
        editor.typeText(text)
        let done = el("keyboardDone")
        if done.waitForExistence(timeout: 3) { done.tap() }
    }

    /// English text in, Amharic script out: the "English text" tab of step 1.
    private func writeAmharicScript() {
        waitFor("writeForMeButton").tap()
        waitFor("writerHeading")
        waitFor("writerRulesRow")       // script rules sit above the choices
        waitFor("writeChoice-source").tap()
        let editor = waitFor("sourceEditor")
        editor.tap()
        editor.typeText("Coffee was first discovered in Ethiopia.")
        let done = el("sheetKeyboardDone")
        if done.waitForExistence(timeout: 3) { done.tap() }
        waitFor("writeButton").tap()
    }

    /// The step-by-step video path lives under More options on the setup screen.
    private func planShotsMyself() {
        waitFor("videoSetupHeading")
        waitFor("setupMoreOptions").tap()
        app.swipeUp()   // the button sits low, behind the pinned bar on smaller phones
        waitFor("planButton").tap()
    }

    // MARK: tests

    /// A new user goes from the welcome screen to a finished voiceover and signs out.
    func testNewUserJourney() {
        launch(["-mockNoVoice"])

        // Welcome and the demo.
        // The field starts empty, so the play button waits for words or a sample.
        waitFor("welcomeHeading")
        XCTAssertFalse(waitFor("demoPlayButton").isEnabled, "nothing to read yet")
        waitFor("demoSampleEn")
        waitFor("demoSampleAm").tap()
        waitFor("demoReady")

        // Sign in.
        signIn()

        // No voice yet, so the app asks for one.
        waitFor("cloneVoiceButton").tap()
        waitFor("enrollHeading")
        waitFor("enrollScript")
        waitFor("sampleVideoButton").tap()

        // The take is shown first. It can be checked, and is only sent after both ticks.
        waitFor("enrollReviewHeading")
        waitFor("redoButton")
        XCTAssertFalse(waitFor("sendVoiceButton").isEnabled, "sending waits for both consent ticks")
        waitFor("checkQualityButton").tap()
        waitFor("qualityBadge")
        waitFor("consentVoiceTick").tap()
        waitFor("consentPolicyTick").tap()
        waitFor("sendVoiceButton").tap()

        // Ready: give the voice a name.
        waitFor("enrollDoneHeading")
        let name = waitFor("voiceNameField")
        name.tap()
        name.typeText("Narration")
        waitFor("saveVoiceNameButton").tap()
        waitForLabel("voiceNameSaved", contains: "Narration")
        waitFor("enrollContinueButton").tap()

        // Back on Create with a voice and the free credits.
        waitForLabel("creditsPill", contains: "20")
        waitFor("voiceLine")

        // English in, Amharic script out.
        writeAmharicScript()
        waitFor("scriptCounter", timeout: 20)
        waitForLabel("creditsPill", contains: "19")
        // What the script cost, and what the voiceover will leave.
        waitForLabel("scriptNote", contains: "Charged 1 credit")
        waitForLabel("leavesLine", contains: "of 19 credits")

        // Make the voiceover.
        waitForLabel("voiceButton", contains: "Make voiceover")
        el("voiceButton").tap()
        // On a slow test machine the first tap can land while the button is still waking up.
        if !el("progressHeading").waitForExistence(timeout: 4), !el("resultHeading").exists,
           el("voiceButton").exists {
            el("voiceButton").tap()
        }
        waitFor("resultHeading", timeout: 40)
        waitFor("playButton")
        waitFor("shareButton")

        // Make another clears the script.
        waitFor("makeAnotherButton").tap()
        waitFor("voiceButton")
        XCTAssertFalse(el("scriptCounter").exists, "the script box must be empty again")

        // The Library lists it.
        app.tabBars.buttons["Library"].tap()
        waitFor("libraryHeading")
        waitFor("libraryRow")

        // Account shows the balance: 20 free, 1 for the script, 2.5 for the voiceover.
        app.tabBars.buttons["Account"].tap()
        waitFor("accountHeading")
        waitForLabel("accountBalance", contains: "16.5")
        waitForLabel("accountEmail", contains: "tester@example.com")

        // Voices list.
        waitFor("myVoicesRow").tap()
        waitFor("voicesHeading")
        waitFor("voiceRow-0")
        app.navigationBars.buttons.firstMatch.tap()

        // Sign out returns to Welcome.
        waitFor("signOutButton").tap()
        waitFor("welcomeHeading")
    }

    /// An account that already has a voice lands straight on a usable Create screen.
    func testReturningUserSeesCreateAndEmptyLibrary() {
        launch()
        signIn()
        waitFor("voiceButton")
        waitFor("voiceLine")
        XCTAssertFalse(el("cloneVoiceButton").exists, "an account with a voice must not be asked to clone")
        snap("create")

        el("creditsPill").tap()
        waitFor("creditsSheetBalance")
        snap("credits")
        el("creditsDone").tap()

        app.tabBars.buttons["Library"].tap()
        waitFor("libraryEmpty")
        snap("libraryEmpty")

        app.tabBars.buttons["Account"].tap()
        waitFor("deleteAccountLink").tap()
        waitFor("deleteHeading")
        XCTAssertFalse(el("deleteConfirmButton").isEnabled,
                       "deleting must stay disabled until the email is typed")
    }

    /// From a script to a finished video with stock footage.
    private func makeVoiceover() {
        writeAmharicScript()
        waitFor("scriptCounter", timeout: 20)
        el("voiceButton").tap()
        waitFor("resultHeading", timeout: 30)
    }

    func testVideoWithStockFootage() {
        launch()
        signIn()
        makeVoiceover()

        waitFor("makeVideoLink").tap()
        planShotsMyself()

        // Planning, then the stock search fills both shots.
        waitFor("shotsHeading", timeout: 30)
        waitFor("shotRow-1")
        waitFor("shotRow-2")

        // Open a shot and pick the other clip.
        el("shotRow-1").tap()
        waitFor("shotSheetHeading")
        // Tapping a clip only shows it; "Use this clip" puts it in the video.
        waitFor("clip-1").tap()
        waitFor("useClipButton").tap()
        waitFor("shotsHeading")

        // The website's shot tools are there, and moving a shot comes back to the list.
        el("shotRow-1").tap()
        waitFor("shotSheetHeading")
        waitFor("findDifferentButton")
        app.swipeUp()
        waitFor("shotTools")
        app.buttons["↓ Move later"].tap()
        waitFor("shotsHeading")

        // Render.
        let make = waitFor("makeVideoButton")
        XCTAssertTrue(make.isEnabled, "with every shot filled the video can be made")
        make.tap()
        waitFor("videoReadyHeading", timeout: 30)
        waitFor("saveVideoButton")

        // The Library lists the video.
        app.tabBars.buttons["Library"].tap()
        waitFor("videoRow")
    }

    /// Tap a word on the result, pick another reading, and the sheet closes on success.
    func testFixAWord() {
        launch()
        signIn()
        makeVoiceover()
        // Fixing sits under the player, as on the website.
        waitFor("fixScreenHeading")
        waitFor("word-0-0").tap()
        // The first reading plays by itself; choosing one only adds it to the list.
        waitFor("fixHeading")
        // "Or say it yourself": record the word, and the closest readings are listed.
        waitFor("fixWaySay").tap()
        waitFor("fixRecordWord").tap()
        waitForLabel("fixRecordWord", contains: "Stop")
        el("fixRecordWord").tap()
        // Keep the closest reading: its Use button is the one in view after recording
        // (Option A's has scrolled up under the window's top bar by then).
        waitFor("fixUse-100", timeout: 20).tap()
        waitFor("generateChangesButton").tap()
        waitFor("fixDoneNote", timeout: 20)
        waitFor("playButton")
    }

    /// The speed can be changed after listening: a new speed asks first and shows its price,
    /// and going back to the speed it was made at is free and at once.
    func testChangeReadingSpeed() {
        launch()
        signIn()
        makeVoiceover()
        waitFor("speedControl")
        waitForLabel("speedNow", contains: "Normal")
        waitFor("speed-fast").tap()
        waitFor("speedConfirm").tap()
        waitForLabel("speedNow", contains: "Faster", timeout: 20)
        waitFor("speed-normal").tap()
        waitForLabel("speedNow", contains: "Normal", timeout: 20)
    }

    /// A spelling can be typed in Amharic letters, starting from the word itself. The word
    /// used exactly as written becomes a fresh take of its sentence, so Generate still works.
    func testAmharicSpellingStartsFromTheWord() {
        launch()
        signIn()
        makeVoiceover()
        waitFor("fixScreenHeading")
        waitFor("word-0-0").tap()
        waitFor("fixWayType").tap()
        waitFor("fixLettersAmharic").tap()
        waitFor("fixStartFromWord").tap()
        // The word exactly as written is not a fix: the app says so instead of quietly
        // reading the whole sentence again.
        waitFor("fixSameAsWord")
        XCTAssertFalse(waitFor("fixUseTyped").isEnabled)
        XCTAssertFalse(app.buttons["generateChangesButton"].exists)
    }

    /// A typed spelling stays listed under the word, so it can be heard and used again.
    func testTypedSpellingIsRemembered() {
        launch()
        signIn()
        makeVoiceover()
        waitFor("fixScreenHeading")
        waitFor("word-0-0").tap()
        waitFor("fixWayType").tap()
        let field = waitFor("fixCustomField")
        field.tap()
        field.typeText("gebboch")
        // Playing a typed spelling also offers three close readings of it.
        waitFor("fixListenTyped").tap()
        waitFor("fixUse-200")
        waitFor("fixUse-202")
        waitFor("fixUseTyped").tap()
        waitFor("generateChangesButton")
        waitFor("word-0-0").tap()
        waitFor("fixTriedList")
        waitFor("fixTryUse-0")
    }

    /// An English project reads English as it is, with speed and emphasis.
    func testEnglishVoiceover() {
        launch()
        signIn()
        // The language switch sits top right; English hides the Amharic tools.
        waitFor("lang-en").tap()
        XCTAssertFalse(app.buttons["ethToggle"].exists)
        XCTAssertFalse(app.buttons["speakButton"].exists)
        waitFor("moreOptionsButton").tap()
        waitFor("englishCard")
        waitFor("moreDone").tap()
        type("Coffee was first discovered in Ethiopia.", into: "scriptEditor")
        waitFor("scriptCounter")
        el("voiceButton").tap()
        waitFor("resultHeading", timeout: 30)
    }

    /// Speaking fills the script box, and script rules can be saved.
    func testSpeakAndScriptRules() {
        launch()
        signIn()
        waitFor("speakButton").tap()
        waitForLabel("speakButton", contains: "Stop")
        el("speakButton").tap()
        waitFor("scriptCounter")

        app.tabBars.buttons["Account"].tap()
        waitFor("scriptRulesRow").tap()
        waitFor("rulesHeading")
        waitFor("saveRulesButton").tap()
        waitForLabel("saveRulesButton", contains: "Saved")
    }

    /// One tap from a voiceover to a finished video, with captions and music by default.
    func testOneTapVideo() {
        launch()
        signIn()
        makeVoiceover()
        waitFor("makeVideoLink").tap()
        waitFor("videoSetupHeading")
        waitFor("shape-landscape").tap()
        waitFor("autoVideoButton").tap()
        waitFor("videoReadyHeading", timeout: 40)
        waitFor("editShotsButton").tap()
        waitFor("shotsHeading")
    }

    /// A video with the presenter, delivered as a separate clip.
    func testVideoWithPresenter() {
        launch()
        signIn()
        makeVoiceover()
        waitFor("makeVideoLink").tap()
        planShotsMyself()
        waitFor("shotsHeading", timeout: 30)

        // Upload a photo, then switch the presenter on.
        waitFor("presenterRowShots").tap()
        flip("avatarDeclare")
        waitFor("samplePhotoButton").tap()
        waitFor("avatarReady")
        flip("avatarToggle")
        waitFor("avatarQuote")
        app.buttons["Separate file"].tap()
        waitFor("presenterDone").tap()

        waitFor("makeVideoButton").tap()
        waitFor("videoReadyHeading", timeout: 30)
        waitFor("saveAvatarButton")
    }

    /// A photo or video can be put on one shot, and the shot says how long it must be.
    func testUploadOntoOneShot() {
        launch()
        signIn()
        makeVoiceover()
        waitFor("makeVideoLink").tap()
        planShotsMyself()
        waitFor("shotsHeading", timeout: 30)
        waitFor("shotRow-1").tap()
        waitFor("shotSheetHeading")
        waitFor("shotLengthNote")
        waitFor("shotUploadSample").tap()
        waitFor("shotSheetDone", timeout: 20).tap()
        waitFor("shotsHeading", timeout: 30)
    }

    /// When stock footage is unavailable the app says so and own clips fill the shots.
    func testStockLimitAsksForOwnFootage() {
        launch(["-mockStockLimit"])
        signIn()
        makeVoiceover()

        waitFor("makeVideoLink").tap()
        planShotsMyself()
        waitFor("stockLimitCard", timeout: 30)
        XCTAssertFalse(el("makeVideoButton").isEnabled, "empty shots must block the video")

        waitFor("addSampleClipButton").tap()
        let predicate = NSPredicate(format: "isEnabled == true")
        let ready = XCTNSPredicateExpectation(predicate: predicate, object: el("makeVideoButton"))
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 20), .completed,
                       "own clips must fill the empty shots")
        el("makeVideoButton").tap()
        waitFor("videoReadyHeading", timeout: 30)
    }

    /// A wrong sign-in code shows the server's own sentence.
    func testWrongCodeIsExplained() {
        launch()
        signIn(code: "000000")
        waitForLabel("problemCard", contains: "not right")
        waitFor("codeField")
    }

    /// With no credits the app says so plainly and offers nothing to buy in Build 1.
    func testOutOfCreditsIsExplained() {
        launch(["-mockNoCredits"])
        signIn()
        waitForLabel("creditsPill", contains: "0")
        // The Create screen says so before anything is tapped.
        waitForLabel("outOfCreditsCard", contains: "out of credits")
        waitForLabel("outOfCreditsCard", contains: "Account page")
        // A paid step is still refused with the server's own sentence.
        writeAmharicScript()
        waitForLabel("problemCard", contains: "credits")
        waitForLabel("problemCard", contains: "Account page")
    }

    /// Credits are bought on the Account page; the server adds them and the balance updates.
    func testBuyingCreditsAddsThem() {
        launch(["-mockNoCredits"])
        signIn()
        app.tabBars.buttons["Account"].tap()
        waitFor("buyCreditsButton").tap()
        waitFor("buyHeading")
        waitForLabel("buyBalance", contains: "0")
        // Top-ups are for plans only, as on the website.
        XCTAssertFalse(app.buttons["buy-topup10"].exists)
        waitFor("buy-starter").tap()
        waitForLabel("buyMessage", contains: "110 credits were added")
        waitForLabel("buyBalance", contains: "110")
        waitFor("restorePurchases")
    }

    /// A promo video is sent from the Account page and listed as waiting for review.
    func testPromoVideoIsSent() {
        launch()
        signIn()
        app.tabBars.buttons["Account"].tap()
        waitFor("earnCreditsButton").tap()
        waitFor("promoHeading")
        // nothing to send until a video is chosen and the rights box is ticked
        XCTAssertFalse(waitFor("promoSend").isEnabled)
        waitFor("promoChooseVideo").tap()
        waitForLabel("promoChosenNote", contains: "Video chosen")
        XCTAssertFalse(waitFor("promoSend").isEnabled)
        waitFor("promoRightsTick").tap()
        // the post link is required, and must be a social media post
        XCTAssertFalse(waitFor("promoSend").isEnabled)
        let field = waitFor("promoLink")
        field.tap()
        field.typeText("example.com/me")
        waitFor("promoLinkNote")
        XCTAssertFalse(waitFor("promoSend").isEnabled)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14))
        field.typeText("tiktok.com/@me/video/1")
        // a second platform, and the reward line counts them
        waitFor("promoAddLink").tap()
        let second = waitFor("promoLinkMore")
        second.tap()
        second.typeText("instagram.com/reel/abc")
        waitForLabel("promoPlatformCount", contains: "2 of 4")
        waitFor("promoSend").tap()
        waitFor("promoSentNote")
        waitFor("promoRow")
        // posted somewhere new later: add the link to the same video
        waitFor("promoAddMoreLinks").tap()
        let more = waitFor("promoAddLinkField")
        more.tap()
        more.typeText("youtube.com/shorts/xyz")
        waitFor("promoAddLinkSend").tap()
        waitForLabel("promoSentNote", contains: "Link added")
    }

    /// The first launch asks for a language and the welcome page follows it.
    func testFirstLaunchAsksForLanguage() {
        launch(["-mockAskLanguage"])
        waitFor("languageChoice")
        waitFor("pickAmharic").tap()
        waitForLabel("welcomeHeading", contains: "በራስዎ ድምፅ")
        waitFor("lang-en").tap()
        waitForLabel("welcomeHeading", contains: "your own voice")
        waitFor("startButton")
    }

    /// No clone needed: what was typed on the welcome page is waiting, and the Kinbir
    /// voice reads it at once, free. Cloning is offered, not required.
    func testKinbirVoiceWithoutCloning() {
        launch(["-mockNoVoice"])
        let field = waitFor("demoField")
        field.tap()
        field.typeText("ሰላም ለሁላችሁ")
        let done = el("demoKeyboardDone")
        if done.waitForExistence(timeout: 3) { done.tap() }
        signIn()
        waitFor("cloneVoiceButton")
        let editor = waitFor("scriptEditor")
        XCTAssertTrue((editor.value as? String ?? "").contains("ሰላም"), "the welcome text carries over")
        waitForLabel("voiceButton", contains: "Free")
        el("voiceButton").tap()
        waitFor("resultHeading", timeout: 40)
    }
}
