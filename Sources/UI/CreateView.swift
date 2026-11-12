import SwiftUI

/// The home of the app: a script box and one button.
struct CreateView: View {
    @EnvironmentObject private var state: AppState
    @Binding var text: String
    @Binding var path: [Route]

    private enum Work: Equatable {
        case idle, fetching, writing, starting
    }

    @State private var work: Work = .idle
    @State private var problem: String?
    @State private var estimate: Double?
    /// The English or link text from before Kinbir wrote the script, for Undo.
    @State private var beforeRewrite: String?
    /// Ties the voiceover to the script Kinbir wrote, while the text is unchanged.
    @State private var draftId: String?
    @State private var draftText: String?
    @FocusState private var editing: Bool

    private var kind: TextKind { TextKind.detect(text) }
    private var busy: Bool { work != .idle }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                header

                if state.me != nil && state.me?.hasVoice == false {
                    cloneCard
                }

                scriptCard

                if let problem {
                    ProblemCard(message: problem)
                }

                Button {
                    editing = false
                    Task { await mainAction() }
                } label: {
                    BusyLabel(title: buttonTitle, busy: busy)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || kind == .empty)
                .accessibilityIdentifier("mainActionButton")

                belowButton
            }
            .page()
        }
        .background(Theme.white)
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editing = false }
                    .accessibilityIdentifier("keyboardDone")
            }
        }
        .onChange(of: text) { _, new in
            state.saveDraft(new)
            if new != draftText { draftId = nil }
        }
        .task(id: estimateKey) { await loadEstimate() }
        .task { await state.refresh() }
    }

    // MARK: pieces

    private var header: some View {
        HStack {
            LogoMark(size: 36)
            Text("Kinbir").font(Theme.heading).foregroundStyle(Theme.black)
            Spacer()
            Pill(text: Fmt.credits(state.balance) + " credits")
                .accessibilityIdentifier("creditsPill")
        }
    }

    private var cloneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clone your voice first").font(Theme.heading).foregroundStyle(Theme.black)
            Text("Read a short script on camera once. After that, every voiceover is in your voice.")
                .font(Theme.body).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: Route.enroll) {
                Text("Clone my voice")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("cloneVoiceButton")
        }
        .card(fill: Theme.lime)
    }

    private var scriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Write Amharic, or paste English or a link.")
                        .font(Theme.body).foregroundStyle(Theme.muted)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(Theme.body)
                    .lineSpacing(Theme.amharicLineSpacing)
                    .foregroundStyle(Theme.black)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 200)
                    .focused($editing)
                    .disabled(work == .writing)
                    .accessibilityIdentifier("scriptEditor")
            }

            HStack(spacing: 12) {
                Text(kindLabel).font(Theme.small.weight(.medium)).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("kindLabel")
                Spacer()
                if beforeRewrite != nil && !busy {
                    Button("Undo") {
                        if let old = beforeRewrite { text = old }
                        beforeRewrite = nil
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("undoButton")
                }
                if !text.isEmpty && !busy {
                    Button("Clear") {
                        text = ""
                        beforeRewrite = nil
                        problem = nil
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("clearButton")
                }
                if text.isEmpty {
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first {
                            DispatchQueue.main.async { text = first }
                        }
                    }
                    .labelStyle(.titleOnly)
                    .tint(Theme.black)
                    .buttonBorderShape(.capsule)
                }
            }
        }
        .card(fill: Theme.grey, padding: 14)
    }

    @ViewBuilder private var belowButton: some View {
        if kind == .english, let estimate, !busy {
            NoteText(text: "Writing the Amharic script costs about \(Fmt.credits(estimate)) credits.")
                .accessibilityIdentifier("estimateNote")
        }
        if work == .writing {
            NoteText(text: "Writing your Amharic script. You can edit it when it is done.")
        }
        if let limit = state.me?.trialMaxChars, kind == .amharic {
            let used = TextKind.ethiopicLetterCount(text)
            NoteText(text: "Free credits voice up to \(limit) Amharic characters at a time. This script has \(used).")
        }
        if let voice = state.activeVoice {
            HStack(spacing: 8) {
                Text("Voice: " + (voice.name ?? "My voice"))
                    .font(Theme.small).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("voiceLine")
                NavigationLink(value: Route.voices) { Text("Change") }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("changeVoiceButton")
            }
        }
    }

    private var kindLabel: String {
        switch kind {
        case .empty: return "Nothing yet"
        case .link: return "Link"
        case .english: return "English text"
        case .amharic: return "Amharic script"
        }
    }

    private var buttonTitle: String {
        switch work {
        case .fetching: return "Getting the article"
        case .writing: return "Writing"
        case .starting: return "Starting"
        case .idle:
            switch kind {
            case .link: return "Get the article"
            case .english: return "Write Amharic script"
            case .empty, .amharic: return "Make voiceover"
            }
        }
    }

    /// Changes only when an estimate is worth asking for again.
    private var estimateKey: String {
        kind == .english && work == .idle ? text : ""
    }

    // MARK: actions

    private func loadEstimate() async {
        estimate = nil
        let snapshot = text
        guard TextKind.detect(snapshot) == .english else { return }
        // Wait for typing to pause before asking the server.
        try? await Task.sleep(nanoseconds: 800_000_000)
        if Task.isCancelled { return }
        estimate = try? await state.api.rewriteEstimate(text: snapshot)
    }

    private func mainAction() async {
        problem = nil
        switch kind {
        case .empty:
            return
        case .link:
            await fetchArticle()
        case .english:
            await writeScript()
        case .amharic:
            await makeVoiceover()
        }
    }

    private func fetchArticle() async {
        work = .fetching
        defer { work = .idle }
        do {
            let link = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let article = try await state.api.extract(url: link)
            beforeRewrite = link
            text = article.text
        } catch {
            problem = state.report(error)
        }
    }

    private func writeScript() async {
        work = .writing
        defer { work = .idle }
        let source = text
        do {
            // The editor fills with the Amharic script as it arrives.
            text = ""
            let result = try await state.api.rewrite(text: source) { piece in
                text += piece
            }
            let final = (result.amharic ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
            beforeRewrite = source
            draftText = final
            text = final
            draftId = result.draftId
            await state.refresh()
        } catch {
            text = source
            problem = state.report(error)
        }
    }

    private func makeVoiceover() async {
        guard state.me?.hasVoice != false else {
            problem = "Clone your voice first. Your account has no voice yet."
            return
        }
        work = .starting
        defer { work = .idle }
        do {
            let script = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let submit = try await state.api.generate(text: script, draftId: draftId)
            await state.refresh()
            path.append(.job(submit.jobId))
        } catch {
            problem = state.report(error)
        }
    }
}
