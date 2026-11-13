import SwiftUI

/// The voices on this account. Tap one to use it.
struct VoicesView: View {
    @EnvironmentObject private var state: AppState
    @State private var problem: String?
    @State private var busyId: String?
    @State private var renaming: VoiceSummary?
    @State private var newName = ""
    @State private var deleting: VoiceSummary?
    @StateObject private var player = AudioPlayer()
    @State private var listeningId: String?
    /// Samples already downloaded, so a second tap plays at once.
    @State private var samples: [String: URL] = [:]
    /// The voice whose sample is loaded in the player.
    @State private var loadedId: String?

    private let maxVoices = 5

    private var voices: [VoiceSummary] { state.me?.allVoices ?? [] }
    private var activeId: String? { state.activeVoice?.voiceId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text(T("My voices")).screenTitle(amharic: A("My voices"))
                    .accessibilityIdentifier("voicesHeading")

                if let problem {
                    ProblemCard(message: problem)
                }
                if listeningId != nil {
                    NoteText(text: T("Preparing the sample. The first listen wakes the voice engine and can take up to a minute."))
                        .accessibilityIdentifier("voiceSampleNote")
                }

                if voices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("No voice yet")).font(Theme.heading).foregroundStyle(Theme.black)
                        Text(T("Clone your voice to start making voiceovers."))
                            .font(Theme.body).foregroundStyle(Theme.muted)
                    }
                    .card(fill: Theme.grey)
                }

                ForEach(Array(voices.enumerated()), id: \.element.id) { index, voice in
                    row(voice, index: index)
                }

                if voices.count < maxVoices {
                    NavigationLink(value: Route.enroll) {
                        Text(voices.isEmpty ? T("Clone my voice") : T("Add a voice"))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("addVoiceButton")
                } else {
                    NoteText(text: T("You have 5 voices, which is the most an account can keep. Delete one to add another."))
                }
            }
            .page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
        .task { await state.refresh() }
        .onDisappear { player.stop() }
        .alert(T("Rename voice"), isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } })
        ) {
            TextField(T("Name"), text: $newName)
                .accessibilityIdentifier("renameField")
            Button(T("Save")) {
                if let voice = renaming { Task { await rename(voice) } }
            }
            Button(T("Cancel"), role: .cancel) { renaming = nil }
        }
        .confirmationDialog(T("Delete this voice?"), isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button(T("Delete voice"), role: .destructive) {
                if let voice = deleting { Task { await delete(voice) } }
            }
            Button(T("Cancel"), role: .cancel) { deleting = nil }
        } message: {
            Text(T("This cannot be undone. Voiceovers you already made are not affected."))
        }
    }

    private func title(_ voice: VoiceSummary, index: Int) -> String {
        let name = (voice.name ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? Tf("Voice %@", "\(index + 1)") : name
    }

    private func row(_ voice: VoiceSummary, index: Int) -> some View {
        let isActive = voice.voiceId == activeId
        return HStack(spacing: 12) {
            Button {
                Task { await activate(voice) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.black)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(voice, index: index))
                            .font(Theme.bodyMedium).foregroundStyle(Theme.black)
                        Text((isActive ? T("In use") : T("Tap to use")) + (voice.isAmharic ? T(" · Amharic") : T(" · English")))
                            .font(Theme.small).foregroundStyle(isActive ? Theme.black : Theme.muted)
                    }
                    Spacer()
                    if busyId == voice.voiceId { ProgressView().tint(Theme.black) }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busyId != nil)
            .accessibilityIdentifier("voiceRow-\(index)")

            Button {
                Task { await listen(voice) }
            } label: {
                ZStack {
                    Circle().fill(Theme.white)
                    Circle().strokeBorder(Theme.black, lineWidth: 1)
                    if listeningId == voice.voiceId {
                        ProgressView().controlSize(.small).tint(Theme.black)
                    } else {
                        Image(systemName: isSounding(voice) ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.black)
                    }
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(listeningId != nil)
            .accessibilityLabel(isSounding(voice) ? T("Pause the sample") : T("Listen to a sample"))
            .accessibilityIdentifier("voiceSample-\(index)")

            Menu {
                Button(sampleTitle(voice)) {
                    Task { await listen(voice) }
                }
                Button(T("Rename")) {
                    newName = voice.name ?? ""
                    renaming = voice
                }
                // The only voice cannot be deleted, as on the website.
                if voices.count > 1 {
                    Button(T("Delete"), role: .destructive) { deleting = voice }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.black)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(T("More"))
            .accessibilityIdentifier("voiceMenu-\(index)")
        }
        .card(fill: isActive ? Theme.lime : Theme.white, padding: 14)
    }

    private func isSounding(_ voice: VoiceSummary) -> Bool {
        loadedId == voice.voiceId && player.isPlaying
    }

    private func sampleTitle(_ voice: VoiceSummary) -> String {
        if listeningId == voice.voiceId { return T("Preparing the sample") }
        return isSounding(voice) ? T("Pause the sample") : T("Listen to a sample")
    }

    /// Plays or pauses a voice's sample. A sample heard before plays at once; the saved one
    /// on the server is free, and only a missing one is made.
    private func listen(_ voice: VoiceSummary) async {
        guard listeningId == nil else { return }
        problem = nil
        let id = voice.voiceId
        if loadedId == id, player.isReady {
            player.toggle()
            return
        }
        if let saved = samples[id], player.load(url: saved) {
            loadedId = id
            player.toggle()
            return
        }
        listeningId = id
        defer { listeningId = nil }
        do {
            let url = try await state.api.voicePreview(voiceId: id)
            samples[id] = url
            if player.load(url: url) {
                loadedId = id
                player.toggle()
            } else {
                loadedId = nil
                problem = T("The audio could not be played. Try again.")
            }
        } catch {
            problem = state.report(error)
        }
    }

    private func activate(_ voice: VoiceSummary) async {
        guard voice.voiceId != activeId else { return }
        busyId = voice.voiceId
        problem = nil
        defer { busyId = nil }
        do {
            try await state.api.activateVoice(id: voice.voiceId)
            await state.refresh()
        } catch {
            problem = state.report(error)
        }
    }

    private func rename(_ voice: VoiceSummary) async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !name.isEmpty else { return }
        problem = nil
        do {
            try await state.api.renameVoice(id: voice.voiceId, name: name)
            await state.refresh()
        } catch {
            problem = state.report(error)
        }
    }

    private func delete(_ voice: VoiceSummary) async {
        deleting = nil
        problem = nil
        do {
            try await state.api.deleteVoice(id: voice.voiceId)
            await state.refresh()
        } catch {
            problem = state.report(error)
        }
    }
}
