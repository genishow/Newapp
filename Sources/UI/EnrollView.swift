import SwiftUI

/// Clone my voice: read a short script on camera, upload it, done.
struct EnrollView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var script = ""
    @State private var scriptProblem: String?
    @State private var showRecorder = false
    @State private var showLibrary = false
    @State private var uploading = false
    @State private var problem: String?
    @State private var advice: [String] = []
    @State private var result: EnrollResult?
    @State private var language: Lang = .am

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                if let result {
                    done(result)
                } else {
                    form
                }
            }
            .page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: language) { await loadScript() }
        .fullScreenCover(isPresented: $showRecorder) {
            VideoRecorder(script: script) { url in
                showRecorder = false
                if let url { Task { await submit(url) } }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            VideoLibraryPicker { url in
                showLibrary = false
                if let url { Task { await submit(url) } }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(T("Clone your voice")).screenTitle()
                .accessibilityIdentifier("enrollHeading")

            Text(T("I am recording my own voice and face. I give permission for an AI voice of me to be created and used only by me."))
                .font(Theme.small).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
                .card(fill: Theme.grey, padding: 14)

            Picker(T("Reading language"), selection: $language) {
                ForEach(Lang.allCases) { Text(T($0.title)).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(uploading)
            .accessibilityIdentifier("enrollLanguagePicker")
            if language == .en {
                NoteText(text: T("Read in English to get a voice with a native English sound."))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(T("Read this aloud")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                if script.isEmpty && scriptProblem == nil {
                    ProgressView().tint(Theme.black)
                } else if let scriptProblem {
                    NoteText(text: scriptProblem)
                    Button(T("Try again")) { Task { await loadScript() } }
                        .buttonStyle(QuietButtonStyle())
                } else {
                    AmharicText(text: script, font: .system(size: 19))
                        .accessibilityIdentifier("enrollScript")
                }
            }
            .card(fill: Theme.lime)

            VStack(alignment: .leading, spacing: 6) {
                tip(T("A quiet room, no music or TV."))
                tip(T("Hold the phone close, about an arm's length."))
                tip(T("Read naturally, the way you normally speak."))
                tip(T("10 to 40 seconds."))
                tip(T("The words stay on screen while you record."))
            }

            if let problem {
                ProblemCard(message: problem)
            }
            ForEach(advice, id: \.self) { line in
                NoteText(text: T("Tip: ") + APIError.sentenceCase(line))
            }

            if uploading {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.black)
                    Text(T("Creating your voice. This can take a minute."))
                        .font(Theme.body).foregroundStyle(Theme.black)
                }
                .card(fill: Theme.grey, padding: 14)
            } else {
                if Launch.isMock {
                    // The simulator has no camera, so the UI tests take this path.
                    Button(T("Use sample video")) { Task { await submitSample() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("sampleVideoButton")
                } else if VideoRecorder.isAvailable {
                    Button(T("Record now")) { showRecorder = true }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(script.isEmpty)
                        .accessibilityIdentifier("recordButton")
                }
                Button(T("Choose a video")) { showLibrary = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(script.isEmpty)
                    .accessibilityIdentifier("chooseVideoButton")
            }
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.black).frame(width: 6, height: 6).padding(.top, 7)
            Text(text).font(Theme.small).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func done(_ result: EnrollResult) -> some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            if result.isApproved {
                Text(T("Your voice is ready")).screenTitle()
                    .accessibilityIdentifier("enrollDoneHeading")
                if let granted = result.creditsGranted, granted > 0 {
                    Text(Tf("%@ free credits are on your account.", Fmt.credits(granted)))
                        .font(Theme.body).foregroundStyle(Theme.black)
                        .card(fill: Theme.lime, padding: 14)
                }
                if result.needsReview == true {
                    NoteText(text: T("The recording was a little rough. If the voice does not sound right, record again in a quieter place."))
                }
            } else {
                Text(T("Thanks")).screenTitle()
                Text(T("Your video was received. You will get an email when it is approved."))
                    .font(Theme.body).foregroundStyle(Theme.muted)
            }
            ForEach(result.advice ?? [], id: \.self) { line in
                NoteText(text: T("Tip: ") + APIError.sentenceCase(line))
            }
            Button(T("Continue")) { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("enrollContinueButton")
        }
    }

    private func loadScript() async {
        scriptProblem = nil
        do {
            script = ""
            script = try await state.api.enrollScript(language: language)
            if script.isEmpty { scriptProblem = T("The script could not be loaded.") }
        } catch {
            scriptProblem = APIError.wrap(error).message
        }
    }

    private func submit(_ url: URL) async {
        problem = nil
        advice = []
        let seconds = await VideoFiles.seconds(of: url)
        if let issue = EnrollRules.problem(seconds: seconds, bytes: VideoFiles.bytes(of: url)) {
            problem = issue
            return
        }
        await upload(url)
    }

    private func submitSample() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sample.mov")
        try? Data("sample".utf8).write(to: url)
        await upload(url)
    }

    private func upload(_ url: URL) async {
        uploading = true
        defer { uploading = false }
        do {
            let answer = try await state.api.enroll(videoURL: url, language: language)
            await state.refresh()
            result = answer
        } catch {
            problem = state.report(error)
        }
    }
}
