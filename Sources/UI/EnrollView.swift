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
            VideoRecorder { url in
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
            Text("Clone your voice").font(Theme.title).foregroundStyle(Theme.black)
                .accessibilityIdentifier("enrollHeading")

            Text("I am recording my own voice and face. I give permission for an AI voice of me to be created and used only by me.")
                .font(Theme.small).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
                .card(fill: Theme.grey, padding: 14)

            Picker("Reading language", selection: $language) {
                ForEach(Lang.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(uploading)
            .accessibilityIdentifier("enrollLanguagePicker")
            if language == .en {
                NoteText(text: "Read in English to get a voice with a native English sound.")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Read this aloud").font(Theme.small.weight(.medium)).foregroundStyle(Theme.black)
                if script.isEmpty && scriptProblem == nil {
                    ProgressView().tint(Theme.black)
                } else if let scriptProblem {
                    NoteText(text: scriptProblem)
                    Button("Try again") { Task { await loadScript() } }
                        .buttonStyle(QuietButtonStyle())
                } else {
                    AmharicText(text: script, font: .system(size: 19))
                        .accessibilityIdentifier("enrollScript")
                }
            }
            .card(fill: Theme.lime)

            VStack(alignment: .leading, spacing: 6) {
                tip("A quiet room, no music or TV.")
                tip("Hold the phone close, about an arm's length.")
                tip("Read naturally, the way you normally speak.")
                tip("10 to 40 seconds.")
            }

            if let problem {
                ProblemCard(message: problem)
            }
            ForEach(advice, id: \.self) { line in
                NoteText(text: "Tip: " + APIError.sentenceCase(line))
            }

            if uploading {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.black)
                    Text("Creating your voice. This can take a minute.")
                        .font(Theme.body).foregroundStyle(Theme.black)
                }
                .card(fill: Theme.grey, padding: 14)
            } else {
                if Launch.isMock {
                    // The simulator has no camera, so the UI tests take this path.
                    Button("Use sample video") { Task { await submitSample() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("sampleVideoButton")
                } else if VideoRecorder.isAvailable {
                    Button("Record now") { showRecorder = true }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(script.isEmpty)
                        .accessibilityIdentifier("recordButton")
                }
                Button("Choose a video") { showLibrary = true }
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
                Text("Your voice is ready").font(Theme.title).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("enrollDoneHeading")
                if let granted = result.creditsGranted, granted > 0 {
                    Text("\(Fmt.credits(granted)) free credits are on your account.")
                        .font(Theme.body).foregroundStyle(Theme.black)
                        .card(fill: Theme.lime, padding: 14)
                }
                if result.needsReview == true {
                    NoteText(text: "The recording was a little rough. If the voice does not sound right, record again in a quieter place.")
                }
            } else {
                Text("Thanks").font(Theme.title).foregroundStyle(Theme.black)
                Text("Your video was received. You will get an email when it is approved.")
                    .font(Theme.body).foregroundStyle(Theme.muted)
            }
            ForEach(result.advice ?? [], id: \.self) { line in
                NoteText(text: "Tip: " + APIError.sentenceCase(line))
            }
            Button("Continue") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("enrollContinueButton")
        }
    }

    private func loadScript() async {
        scriptProblem = nil
        do {
            script = ""
            script = try await state.api.enrollScript(language: language)
            if script.isEmpty { scriptProblem = "The script could not be loaded." }
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
