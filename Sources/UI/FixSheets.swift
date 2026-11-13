import SwiftUI

/// "How should this word sound?" Works the way the website does: the first reading plays
/// by itself, the others are prepared in the background, and choosing one only adds it to
/// the list of changes. Nothing is charged until the changes are generated together.
struct WordFixSheet: View {
    @EnvironmentObject private var state: AppState
    let target: FixTarget
    /// How many times this word appears, so the user knows one fix changes them all.
    let occurrences: Int
    let onUse: (FixEdit) -> Void
    let onClose: () -> Void

    @StateObject private var player = AudioPlayer()
    @State private var options: [FixOption] = []
    @State private var loaded = false
    @State private var custom = ""
    @State private var problem: String?
    /// Which reading is being prepared right now, for the spinner on its row.
    @State private var preparing: String?
    @State private var waited = 0
    @State private var firstEver = false
    /// Readings already downloaded. A second tap plays at once.
    @State private var clips: [String: URL] = [:]
    @State private var playingKey: String?

    private var typed: String { custom.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    Text(T("How should this word sound?")).font(Theme.heading).foregroundStyle(Theme.black)
                        .accessibilityIdentifier("fixHeading")
                    AmharicText(text: target.word, font: .system(size: 30, weight: .medium))
                    if occurrences > 1 {
                        NoteText(text: Tf("It appears %@ times. Fixing it here changes all of them.", "\(occurrences)"))
                    }

                    if let problem {
                        ProblemCard(message: problem)
                    }

                    if !loaded {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.black)
                            Text(T("Preparing options")).font(Theme.body).foregroundStyle(Theme.black)
                        }
                    } else if options.isEmpty {
                        NoteText(text: T("No other readings exist for this word yet. Type how it should sound below."))
                    } else {
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            row(key: "o:\(option.optionId)",
                                title: Tf("Option %@", optionLetter(index)),
                                index: index,
                                listen: { await hear(key: "o:\(option.optionId)", optionId: option.optionId, custom: nil) },
                                use: { onUse(.option(word: target.word, optionId: option.optionId)) })
                        }
                    }

                    if preparing != nil && (firstEver || waited > 3) {
                        NoteText(text: firstEver
                                 ? T("This word is being voiced for the very first time, so it can take a minute or two. Everyone after you gets it instantly.")
                                 : Tf("Preparing the audio. %@ seconds so far.", "\(waited)"))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(T("Not right? Type it your way")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                        TextField(T("Type how it should sound"), text: $custom)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .field()
                            .accessibilityIdentifier("fixCustomField")
                        HStack(spacing: 20) {
                            Button(preparing == "c:" + typed ? T("Preparing") : T("Listen")) {
                                Task { await hear(key: "c:" + typed, optionId: nil, custom: typed) }
                            }
                            .buttonStyle(QuietButtonStyle())
                            Button(T("Use what I typed")) {
                                onUse(.custom(word: target.word, spelling: typed))
                            }
                            .buttonStyle(QuietButtonStyle())
                        }
                        .disabled(typed.count < 3)
                    }
                    .card(fill: Theme.white, padding: 14)

                    NoteText(text: T("These clips are an example reading and may not be in your own voice. Listening is free when the reading has been made before. Your changes are recorded in your voice when you generate them: 1.5 credits for all of them together."))
                }
                .page()
            }
            .background(Theme.white)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Close")) { onClose() }.accessibilityIdentifier("fixClose")
                }
            }
        }
        .tint(Theme.black)
        .task { await open() }
        // A typed spelling is prepared after a short pause, so Listen is quick.
        .task(id: typed) {
            guard typed.count >= 3 else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            _ = try? await state.api.fixPreview(word: target.word, optionId: nil, custom: typed)
        }
        .onDisappear { player.stop() }
    }

    private func optionLetter(_ index: Int) -> String {
        String(UnicodeScalar(UInt8(65 + min(index, 25))))
    }

    private func row(key: String, title: String, index: Int,
                     listen: @escaping () async -> Void, use: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await listen() }
            } label: {
                ZStack {
                    Circle().fill(playingKey == key ? Theme.lime : Theme.black)
                    if preparing == key {
                        ProgressView().tint(Theme.white)
                    } else {
                        Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(playingKey == key ? Theme.black : Theme.white)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(T("Listen"))
            .accessibilityIdentifier("fixListen-\(index)")

            Text(title).font(Theme.bodyMedium).foregroundStyle(Theme.black)
            Spacer()
            Button(T("Use")) { use() }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("fixUse-\(index)")
        }
        .card(fill: Theme.white, padding: 10)
    }

    /// Loads the options, starts preparing every reading, and plays the first one.
    private func open() async {
        guard !loaded else { return }
        do {
            options = try await state.api.fixCandidates(word: target.word)
        } catch {
            // "No other readings yet" is an answer, not a failure.
            if APIError.wrap(error).status != 404 { problem = state.report(error) }
        }
        loaded = true
        guard let first = options.first else { return }
        let api = state.api
        let word = target.word
        for option in options.dropFirst() {
            let id = option.optionId
            Task { _ = try? await api.fixPreview(word: word, optionId: id, custom: nil) }
        }
        await hear(key: "o:\(first.optionId)", optionId: first.optionId, custom: nil)
    }

    private func hear(key: String, optionId: Int?, custom: String?) async {
        problem = nil
        if let ready = clips[key] {
            play(ready, key: key)
            return
        }
        guard preparing == nil else { return }
        preparing = key
        waited = 0
        firstEver = false
        defer { preparing = nil }
        do {
            var preview = try await state.api.fixPreview(word: target.word, optionId: optionId,
                                                         custom: custom)
            // A reading made before comes back ready at once. Only a new one is waited for.
            var tries = 0
            while !preview.isDone {
                if preview.isFailed || tries >= 90 {
                    problem = T("That reading could not be made. Try another.")
                    return
                }
                firstEver = preview.firstEver ?? firstEver
                tries += 1
                let pause = Launch.isMock ? 0.2 : 2.0
                try await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
                waited += Int(pause.rounded(.up))
                preview = try await state.api.fixPreviewStatus(id: preview.previewId)
            }
            let url = try await state.api.fixPreviewAudio(id: preview.previewId)
            clips[key] = url
            play(url, key: key)
        } catch {
            if !Task.isCancelled { problem = state.report(error) }
        }
    }

    private func play(_ url: URL, key: String) {
        if player.load(url: url) {
            playingKey = key
            player.toggle()
        }
    }
}

/// Change the words of one part of the script, or record it again as it is.
struct SentenceSheet: View {
    let segment: Int
    let original: String
    let onUse: (FixEdit) -> Void
    let onClose: () -> Void

    @State private var text: String
    @FocusState private var editing: Bool

    init(segment: Int, original: String, onUse: @escaping (FixEdit) -> Void,
         onClose: @escaping () -> Void) {
        self.segment = segment
        self.original = original
        self.onUse = onUse
        self.onClose = onClose
        _text = State(initialValue: original)
    }

    private var cleaned: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var changed: Bool { cleaned != original.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    Text(T("Edit this sentence")).font(Theme.heading).foregroundStyle(Theme.black)
                        .accessibilityIdentifier("sentenceHeading")

                    TextEditor(text: $text)
                        .font(Theme.body)
                        .lineSpacing(Theme.amharicLineSpacing)
                        .foregroundStyle(Theme.black)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                        .focused($editing)
                        .card(fill: Theme.grey, padding: 12)
                        .accessibilityIdentifier("sentenceEditor")

                    if changed {
                        Button(T("Save this edit")) { onUse(.editSentence(segment: segment, text: cleaned)) }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(cleaned.isEmpty)
                            .accessibilityIdentifier("saveSentenceButton")
                        Button(T("Put the old words back")) { text = original }
                            .buttonStyle(QuietButtonStyle())
                    } else {
                        Button(T("Record this sentence again")) { onUse(.rereadSentence(segment: segment)) }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("rereadButton")
                        NoteText(text: T("Use this when the words are right but the reading came out too slow, too fast or flat."))
                    }
                    NoteText(text: T("Nothing is recorded yet. Your changes wait in a list, and you generate them all together for 1.5 credits."))
                }
                .page()
            }
            .background(Theme.white)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Close")) { onClose() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(T("Done")) { editing = false }
                }
            }
        }
        .tint(Theme.black)
    }
}

/// A sentence the user tapped, for `.sheet(item:)`.
struct SentenceTarget: Identifiable, Equatable {
    let segment: Int
    let text: String
    var id: Int { segment }
}
