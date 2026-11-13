import SwiftUI

/// Fix the voiceover: how a word sounds, or the words of a sentence. Choices wait in a
/// list and are recorded together with one button, the way the website does it.
struct FixView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let jobId: String

    private enum Mode { case words, sentences }

    @StateObject private var player = AudioPlayer()
    @State private var job: JobStatus?
    @State private var mode: Mode = .words
    @State private var fixingWord: FixTarget?
    @State private var fixingSentence: SentenceTarget?
    @State private var pending: [FixEdit] = []
    @State private var applying = false
    @State private var batchId: String?
    @State private var problem: String?
    @State private var done = false

    private var segments: [String] { job?.segments ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(T("Fix the voiceover")).screenTitle()
                    .accessibilityIdentifier("fixScreenHeading")

                HStack(spacing: 10) {
                    modeTile(.words, icon: "character.bubble", title: T("A word sounds wrong"))
                    modeTile(.sentences, icon: "pencil", title: T("Change the words"))
                }
                .disabled(applying)

                if job == nil {
                    ProgressView().tint(Theme.black)
                } else if mode == .words {
                    NoteText(text: T("Tap the word that sounds wrong."))
                    TappableScript(segments: segments,
                                   fixedWords: (job?.fixedWords ?? []) + pendingWords) { fixingWord = $0 }
                        .disabled(applying)
                        .card(fill: Theme.grey, padding: 14)
                } else {
                    NoteText(text: T("Tap the part you want to change or hear again."))
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, sentence in
                        Button {
                            fixingSentence = SentenceTarget(segment: index,
                                                            text: pendingText(for: index) ?? sentence)
                        } label: {
                            AmharicText(text: pendingText(for: index) ?? sentence)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card(fill: pending.contains { $0.id == "s:\(index)" } ? Theme.lime : Theme.grey,
                                      padding: 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(applying)
                        .accessibilityIdentifier("sentence-\(index)")
                    }
                }

                if !pending.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(T("Your changes")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                        FlowLayout(spacing: 8) {
                            ForEach(pending) { fix in
                                Button {
                                    pending.removeAll { $0.id == fix.id }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(label(for: fix)).font(Theme.small).lineLimit(1)
                                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundStyle(Theme.black)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 36)
                                    .background(Capsule().fill(Theme.white))
                                    .overlay(Capsule().strokeBorder(Theme.black, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(applying)
                            }
                        }
                    }
                }

                if done {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(T("Done. Listen to the new take.")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                            .accessibilityIdentifier("fixDoneNote")
                        Button {
                            player.toggle()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                Text(player.isPlaying ? T("Pause") : T("Play"))
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!player.isReady)
                    }
                    .card(fill: Theme.lime)
                }
            }
            .page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomBar(problem: problem) { bottom }
        }
        .task {
            job = try? await state.api.job(id: jobId)
            await state.api.warmEngine()
        }
        .onDisappear { player.stop() }
        .sheet(item: $fixingWord) { target in
            WordFixSheet(target: target, occurrences: occurrences(of: target.word),
                         onUse: { fix in
                             queue(fix)
                             fixingWord = nil
                         },
                         onClose: { fixingWord = nil })
                .environmentObject(state)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $fixingSentence) { target in
            SentenceSheet(segment: target.segment, original: target.text,
                          onUse: { fix in
                              queue(fix)
                              fixingSentence = nil
                          },
                          onClose: { fixingSentence = nil })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func modeTile(_ value: Mode, icon: String, title: String) -> some View {
        Button {
            Haptics.tap()
            mode = value
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 20, weight: .medium))
                Text(title).font(Theme.smallMedium).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.black)
            .frame(maxWidth: .infinity, minHeight: 84)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(mode == value ? Theme.lime : Theme.white))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Theme.black, lineWidth: mode == value ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(value == .words ? "modeWords" : "modeSentences")
    }

    @ViewBuilder private var bottom: some View {
        if applying {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.black)
                Text(T("Recording your changes")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                Spacer()
                Button(T("Stop")) { Task { await stopFixes() } }
                    .buttonStyle(QuietButtonStyle())
            }
            .frame(minHeight: 52)
        } else if !pending.isEmpty {
            Button(Tf("Apply %@ changes · 1.5 credits", "\(pending.count)")) {
                Task { await applyFixes() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("generateChangesButton")
        } else if done {
            Button(T("Back to my voiceover")) { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("fixBackButton")
        } else {
            Text(T("Pick as many changes as you like. They cost 1.5 credits together."))
                .font(Theme.small).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
    }

    // MARK: helpers

    private var pendingWords: [String] {
        pending.compactMap { fix in
            switch fix {
            case .option(let word, _), .custom(let word, _): return word
            default: return nil
            }
        }
    }

    private func pendingText(for segment: Int) -> String? {
        for fix in pending {
            if case .editSentence(let s, let text) = fix, s == segment { return text }
        }
        return nil
    }

    private func occurrences(of word: String) -> Int {
        segments.reduce(0) { count, sentence in
            count + Words.tokens(in: sentence).filter { $0.word == word }.count
        }
    }

    private func label(for fix: FixEdit) -> String {
        switch fix {
        case .option(let word, _), .custom(let word, _): return word
        case .rereadSentence(let segment): return Tf("Part %@ again", "\(segment + 1)")
        case .editSentence(let segment, _): return Tf("Part %@ edited", "\(segment + 1)")
        }
    }

    /// A newer choice for the same word or sentence replaces the older one.
    private func queue(_ fix: FixEdit) {
        pending.removeAll { $0.id == fix.id }
        guard pending.count < FixEdit.maxPerBatch else {
            problem = T("That is the most changes for one go. Apply these first.")
            return
        }
        pending.append(fix)
        done = false
        problem = nil
        Haptics.tap()
    }

    private func applyFixes() async {
        applying = true
        problem = nil
        defer { applying = false }
        let sent = pending
        do {
            var batch = try await state.api.fixApply(jobId: jobId, fixes: sent)
            guard let id = batch.batchId else {
                problem = T("The changes could not be started. Try again.")
                return
            }
            batchId = id
            // Paid for from here on: the list is cleared so a second tap cannot pay twice.
            pending = []
            await state.refresh()
            var misses = 0
            var tries = 0
            while !batch.isOver && tries < 180 {
                tries += 1
                try? await Task.sleep(nanoseconds: UInt64((Launch.isMock ? 0.2 : 2) * 1_000_000_000))
                do {
                    batch = try await state.api.fixStatus(jobId: jobId, batchId: id)
                    misses = 0
                } catch {
                    misses += 1
                    if misses >= 8 { throw error }
                }
            }
            switch batch.status {
            case "done":
                done = true
                Haptics.success()
                job = (try? await state.api.job(id: jobId)) ?? job
                if let url = try? await state.api.playbackAudio(jobId: jobId), player.load(url: url) {
                    player.toggle()
                }
            case "cancelled":
                pending = sent
                problem = T("Stopped. Your credits were returned.")
            case "failed":
                pending = sent
                Haptics.failure()
                problem = batch.error.map(APIError.sentenceCase)
                    ?? T("The changes did not finish. Your credits were returned.")
            default:
                problem = T("This is taking longer than usual. Check your voiceover again in a few minutes.")
            }
            await state.refresh()
        } catch {
            problem = state.report(error)
        }
    }

    private func stopFixes() async {
        guard let batchId else { return }
        do {
            try await state.api.fixCancel(jobId: jobId, batchId: batchId)
        } catch {
            problem = state.report(error)
        }
    }
}
