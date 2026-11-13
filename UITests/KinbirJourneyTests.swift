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
        return element
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
        waitFor("planButton").tap()
    }

    // MARK: tests

    /// A new user goes from the welcome screen to a finished voiceover and signs out.
    func testNewUserJourney() {
        launch(["-mockNoVoice"])

        // Welcome and the demo.
        waitFor("welcomeHeading")
        waitFor("demoPlayButton").tap()
        waitFor("demoReady")

        // Sign in.
        signIn()

        // No voice yet, so the app asks for one.
        waitFor("cloneVoiceButton").tap()
        waitFor("enrollHeading")
        waitFor("enrollScript")
        waitFor("sampleVideoButton").tap()
        waitFor("enrollDoneHeading")
        waitFor("enrollContinueButton").tap()

        // Back on Create with a voice and the free credits.
        waitForLabel("creditsPill", contains: "20")
        waitFor("voiceLine")

        // English in, Amharic script out.
        writeAmharicScript()
        waitFor("scriptCounter", timeout: 20)
        waitForLabel("creditsPill", contains: "19")

        // Make the voiceover.
        waitForLabel("voiceButton", contains: "Make voiceover")
        el("voiceButton").tap()
        waitFor("resultHeading", timeout: 30)
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

        app.tabBars.buttons["Library"].tap()
        waitFor("libraryEmpty")

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
        waitFor("clip-1").tap()
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
        waitFor("fixLink").tap()
        waitFor("fixScreenHeading")
        waitFor("word-0-0").tap()
        // The first reading plays by itself; choosing one only adds it to the list.
        waitFor("fixHeading")
        waitFor("fixUse-0").tap()
        waitFor("generateChangesButton").tap()
        waitFor("fixDoneNote", timeout: 20)
        waitFor("fixBackButton").tap()
        waitFor("playButton")
    }

    /// An English project reads English as it is, with speed and emphasis.
    func testEnglishVoiceover() {
        launch()
        signIn()
        waitFor("moreOptionsButton").tap()
        waitFor("languagePicker")
        app.buttons["English"].tap()
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
        writeAmharicScript()
        waitForLabel("problemCard", contains: "credits")
        waitForLabel("problemCard", contains: "coming soon")
    }
}
