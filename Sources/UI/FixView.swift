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
    @State private var pending: [PendingFix] = []
    @State private var loadFailed = false
    @State private var applying = false
    @State private var batchId: String?
    @State private var problem: String?
    @State private var done = false

    private var segments: [String] { job?.segments ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(T("Fix the voiceover")).screenTitle(amharic: A("Fix the voiceover"))
                    .accessibilityIdentifier("fixScreenHeading")

                HStack(spacing: 10) {
                    modeTile(.words, icon: "character.bubble", title: T("Fix pronunciation"))
                    modeTile(.sentences, icon: "pencil", title: T("Change the words"))
                }
                .disabled(applying)

                if job == nil {
                    if loadFailed {
                        ProblemCard(message: T("The script could not be loaded."))
                        Button(T("Try again")) { Task { await load() } }
                            .buttonStyle(SecondaryButtonStyle())
                    } else {
                        ProgressView().tint(Theme.black)
                    }
                } else if mode == .words {
                    TappableScript(segments: segments, fixedWords: pendingWords) { fixingWord = $0 }
                        .disabled(applying)
                        .card(fill: Theme.grey, padding: 14)
                } else {
                    ForEach(sentences) { sentence in
                        Button {
                            fixingSentence = SentenceTarget(sentence: sentence,
                                                            pendingText: pendingText(for: sentence),
                                                            queued: isQueued(sentence))
                        } label: {
                            AmharicText(text: pendingText(for: sentence) ?? sentence.text)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card(fill: isQueued(sentence) ? Theme.lime : Theme.grey, padding: 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(applying)
                        .accessibilityIdentifier("sentence-" + sentence.id)
                    }
                }

                if !pending.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(T("Your changes")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                        FlowLayout(spacing: 8) {
                            ForEach(pending) { fix in
                                Button {
                                    pending.removeAll { $0.id == fix.id }
                                    problem = nil
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
                        Text(T("Done. Press play to hear the new take.")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
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
            await load()
            await state.api.warmEngine()
        }
        .onDisappear { player.stop() }
        .sheet(item: $fixingWord) { target in
            WordFixSheet(target: target, jobId: jobId, occurrences: occurrences(of: target.word),
                         marked: pending.contains { $0.id == "w:" + target.word },
                         onUnmark: {
                             pending.removeAll { $0.id == "w:" + target.word }
                             fixingWord = nil
                         },
                         onUse: { fix, label in
                             queue(.word(fix, label: label))
                             fixingWord = nil
                         },
                         onClose: { fixingWord = nil })
                .environmentObject(state)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $fixingSentence) { target in
            SentenceSheet(target: target,
                          onSave: { text in
                              queue(.edit(target.sentence, text: text))
                              fixingSentence = nil
                          },
                          onReread: {
                              queue(.reread(target.sentence))
                              fixingSentence = nil
                          },
                          onUndo: {
                              pending.removeAll { $0.id == "s:" + target.sentence.id }
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
            Button(Tf("Generate my %@ changes · 1.5 credits", "\(pending.count)")) {
                Task { await applyFixes(whole: false) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("generateChangesButton")
        } else if done {
            Button(T("Back to my voiceover")) { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("fixBackButton")
        } else if job != nil {
            Button(T("Generate the whole script again · 1.5 credits")) {
                Task { await applyFixes(whole: true) }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("generateWholeButton")
        }
    }

    // MARK: helpers

    private var sentences: [Script.Sentence] { Script.sentences(segments) }

    private func load() async {
        loadFailed = false
        do {
            job = try await state.api.job(id: jobId)
        } catch {
            loadFailed = true
        }
    }

    private var pendingWords: [String] {
        pending.compactMap { item in
            guard case .word(let fix, _) = item else { return nil }
            switch fix {
            case .option(let word, _), .custom(let word, _), .heard(let word, _, _): return word
            default: return nil
            }
        }
    }

    private func pendingText(for sentence: Script.Sentence) -> String? {
        for item in pending {
            if case .edit(let s, let text) = item, s.id == sentence.id { return text }
        }
        return nil
    }

    private func isQueued(_ sentence: Script.Sentence) -> Bool {
        pending.contains { $0.id == "s:" + sentence.id }
    }

    private func occurrences(of word: String) -> Int {
        segments.reduce(0) { count, sentence in
            count + Words.tokens(in: sentence).filter { $0.word == word }.count
        }
    }

    private func label(for item: PendingFix) -> String {
        switch item {
        case .word(_, let label): return label
        case .reread(let sentence): return "↻ " + String(sentence.text.prefix(18))
        case .edit(_, let text): return "✎ " + String(text.prefix(18))
        }
    }

    /// A newer choice for the same word or sentence replaces the older one.
    private func queue(_ fix: PendingFix) {
        pending.removeAll { $0.id == fix.id }
        guard pending.count < FixEdit.maxPerBatch else {
            problem = T("That is the most changes for one go. Generate these first.")
            return
        }
        pending.append(fix)
        done = false
        problem = nil
        Haptics.tap()
    }

    private func applyFixes(whole: Bool) async {
        guard !applying else { return }
        applying = true
        problem = nil
        done = false
        defer { applying = false }
        let sent = pending
        let fixes = whole ? PendingFix.wholeScript(sent, segments: segments)
                          : PendingFix.wire(sent, segments: segments)
        guard fixes.count <= FixEdit.maxPerBatch else {
            problem = T("That is the most changes for one go. Generate these first.")
            return
        }
        do {
            var batch = try await state.api.fixApply(jobId: jobId, fixes: fixes)
            guard let id = batch.batchId else {
                problem = T("The changes could not be started. Try again.")
                return
            }
            batchId = id
            // The list is kept until the new take is really done, as on the website. The
            // buttons are off while this runs, so it cannot be paid for twice.
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
                pending.removeAll { item in sent.contains { $0.id == item.id } }
                done = true
                Haptics.success()
                job = (try? await state.api.job(id: jobId)) ?? job
                if let url = try? await state.api.playbackAudio(jobId: jobId) { _ = player.load(url: url) }
            case "cancelled":
                problem = T("Stopped. Your credits were returned.")
            case "failed":
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
