import SwiftUI

/// Fix the voiceover: how a word sounds, or the words of a sentence. Choices wait in a
/// list and are recorded together with one button, the way the website does it.
struct FixView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let jobId: String
    /// Called when a new take is ready, so the player above can load it.
    var onRegenerated: () -> Void = {}

    private enum Mode { case words, sentences }

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

    /// A panel that sits under the player on the voiceover screen, as on the website.
    var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text(T("Want to change something?")).font(Theme.heading).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("fixScreenHeading")
                Text(mode == .words ? T("Tap any word to fix how it sounds.")
                                    : T("Tap any sentence to change its words or record it again."))
                    .font(Theme.body).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)

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
                            AmharicText(text: (pendingText(for: sentence) ?? "").isEmpty
                                        ? sentence.text : (pendingText(for: sentence) ?? sentence.text))
                                .strikethrough(pendingText(for: sentence) == "")
                                .opacity(pendingText(for: sentence) == "" ? 0.5 : 1)
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

                if let problem {
                    ProblemCard(message: problem)
                }

                bottom

                if done {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                        Text(T("Done. Your new take is in the player above, press play to hear it."))
                            .font(Theme.small)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.black)
                    .card(fill: Theme.lime, padding: 12)
                    .accessibilityIdentifier("fixDoneNote")
                }
            }
        .task {
            await load()
            // The voice engine goes to sleep 2 minutes after its last use, and waking it
            // takes over a minute. That is why one word could take so long. It is woken
            // here, and kept awake for the first minutes on this screen, so the first
            // word is quick. This stops when the screen is left.
            for _ in 0..<5 {
                await state.api.warmEngine()
                try? await Task.sleep(nanoseconds: 95 * 1_000_000_000)
                if Task.isCancelled { break }
            }
        }
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
                Text(T("Recording your changes. This takes a minute or two.")).font(Theme.small)
                    .foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(T("Stop")) { Task { await stopFixes() } }
                    .buttonStyle(QuietButtonStyle())
            }
            .frame(minHeight: 52)
        } else if job != nil {
            if !pending.isEmpty {
                Button(Tf("Generate my %@ changes · 1.5 credits", "\(pending.count)")) {
                    Task { await applyFixes(whole: false) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("generateChangesButton")
            }
            Button(Tf("Generate the whole script (%@ sentences) · 1.5 credits", "\(sentences.count)")) {
                Task { await applyFixes(whole: true) }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(wholeTooLong)
            .accessibilityIdentifier("generateWholeButton")
            if wholeTooLong {
                NoteText(text: FixView.tooLongNote).accessibilityIdentifier("wholeTooLongNote")
            }
        }
    }

    // MARK: helpers

    private var sentences: [Script.Sentence] { Script.sentences(segments) }

    /// The server takes at most this many changes in one go, and a whole-script take is
    /// one change for every part of the audio.
    private var wholeTooLong: Bool { segments.count > FixEdit.maxPerBatch }

    private static var tooLongNote: String {
        T("This script is too long to read again in one go. Re-record the sentences you want instead.")
    }

    private func load() async {
        loadFailed = false
        do {
            job = try await state.api.job(id: jobId)
        } catch {
            loadFailed = true
            return
        }
        await resumeBatch(loud: false)
    }

    // MARK: the running batch

    /// Where the id of a batch that is still recording is kept, so leaving this screen
    /// does not lose it and the same changes cannot be paid for twice.
    private var batchKey: String { "kinbir.fixBatch." + jobId }

    private var storedBatch: String? {
        // UI tests share one simulator, so nothing is carried from one test to the next.
        guard !Launch.isMock else { return nil }
        let id = UserDefaults.standard.string(forKey: batchKey) ?? ""
        return id.isEmpty ? nil : id
    }

    private func rememberBatch(_ id: String) {
        guard !Launch.isMock else { return }
        UserDefaults.standard.set(id, forKey: batchKey)
    }

    private func forgetBatch() {
        UserDefaults.standard.removeObject(forKey: batchKey)
    }

    /// Picks up a batch that was started earlier and may still be recording.
    private func resumeBatch(loud: Bool) async {
        guard !applying, let id = storedBatch else { return }
        applying = true
        batchId = id
        defer { applying = false }
        do {
            let batch = try await state.api.fixStatus(jobId: jobId, batchId: id)
            await follow(batch, id: id, sent: [])
        } catch {
            if Task.isCancelled { return }
            let wrapped = APIError.wrap(error)
            if wrapped.status == 404 {
                // The server no longer knows it, so it is over.
                forgetBatch()
                if loud { problem = T("Your earlier changes are finished. Tap again to send these.") }
            } else if loud || wrapped.kind == .sessionExpired {
                problem = state.report(error)
            }
        }
    }

    /// Watches a batch until it is over, for as long as this screen is open. The buttons
    /// stay off meanwhile, so it cannot be paid for twice.
    private func follow(_ first: FixBatch, id: String, sent: [PendingFix]) async {
        var batch = first
        var misses = 0
        while !batch.isOver {
            try? await Task.sleep(nanoseconds: UInt64((Launch.isMock ? 0.2 : 2) * 1_000_000_000))
            if Task.isCancelled { return }
            do {
                batch = try await state.api.fixStatus(jobId: jobId, batchId: id)
                misses = 0
            } catch {
                if Task.isCancelled { return }
                misses += 1
                let wrapped = APIError.wrap(error)
                if wrapped.status == 404 {
                    forgetBatch()
                    problem = state.report(error)
                    return
                }
                if misses >= 8 || wrapped.kind == .sessionExpired {
                    // The id stays stored: it is checked again before anything new is sent.
                    problem = state.report(error)
                    return
                }
            }
        }
        forgetBatch()
        switch batch.status {
        case "done":
            pending.removeAll { item in sent.contains { $0.id == item.id } }
            done = true
            Haptics.success()
            job = (try? await state.api.job(id: jobId)) ?? job
            onRegenerated()
        case "cancelled":
            problem = T("Stopped. Your credits were returned.")
        default:
            Haptics.failure()
            problem = batch.error.map(APIError.sentenceCase)
                ?? T("The changes did not finish. Your credits were returned.")
        }
        await state.refresh()
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

    /// Every edit waiting in one segment, with this sentence counted as removed.
    private func pendingEdits(in segment: Int, adding removed: Script.Sentence) -> [(Script.Sentence, String)] {
        var out: [(Script.Sentence, String)] = [(removed, "")]
        for item in pending {
            if case .edit(let s, let text) = item, s.segment == segment, s.id != removed.id {
                out.append((s, text))
            }
        }
        return out
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
        case .edit(let sentence, let text):
            return text.isEmpty ? "✕ " + String(sentence.text.prefix(18)) : "✎ " + String(text.prefix(18))
        }
    }

    /// A newer choice for the same word or sentence replaces the older one.
    private func queue(_ fix: PendingFix) {
        // A sentence can be taken out only when others stay in its part of the audio.
        if case .edit(let sentence, let text) = fix, text.isEmpty {
            let left = PendingFix.segmentText(segments.indices.contains(sentence.segment)
                                              ? segments[sentence.segment] : "",
                                              with: pendingEdits(in: sentence.segment, adding: sentence))
            if left.isEmpty {
                problem = T("This sentence cannot be removed because it is the only one in its part of the audio. Change its words instead.")
                return
            }
        }
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
        // A batch from earlier may still be recording. It is finished first, so the same
        // changes are never paid for twice.
        if storedBatch != nil {
            problem = nil
            await resumeBatch(loud: true)
            return
        }
        applying = true
        problem = nil
        done = false
        defer { applying = false }
        let sent = pending
        let fixes = whole ? PendingFix.wholeScript(sent, segments: segments)
                          : PendingFix.wire(sent, segments: segments)
        guard fixes.count <= FixEdit.maxPerBatch else {
            problem = whole ? FixView.tooLongNote
                            : T("That is the most changes for one go. Generate these first.")
            return
        }
        do {
            let batch = try await state.api.fixApply(jobId: jobId, fixes: fixes)
            guard let id = batch.batchId else {
                problem = T("The changes could not be started. Try again.")
                return
            }
            batchId = id
            rememberBatch(id)
            // The list is kept until the new take is really done, as on the website. The
            // buttons are off while this runs, so it cannot be paid for twice.
            await state.refresh()
            await follow(batch, id: id, sent: sent)
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
