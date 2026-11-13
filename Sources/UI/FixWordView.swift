import SwiftUI

/// Lays views out left to right and wraps to the next line, like words in a paragraph.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        let spots = arrange(width: bounds.width, subviews: subviews).spots
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + spots[index].x, y: bounds.minY + spots[index].y),
                          proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, spots: [CGPoint]) {
        var spots: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            spots.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), spots)
    }
}

/// The script as tappable words. Tapping one opens the fix sheet.
struct TappableScript: View {
    let segments: [String]
    let fixedWords: [String]
    let onTap: (FixTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, sentence in
                FlowLayout(spacing: 6) {
                    ForEach(Words.tokens(in: sentence)) { token in
                        Button {
                            onTap(FixTarget(word: token.word, shown: token.shown, segment: index))
                        } label: {
                            Text(token.shown)
                                .font(Theme.body)
                                .foregroundStyle(Theme.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(fixedWords.contains(token.word) ? Theme.lime : Theme.grey))
                        }
                        .buttonStyle(.plain)
                        .disabled(token.word.isEmpty)
                        .accessibilityIdentifier("word-\(index)-\(token.id)")
                    }
                }
            }
        }
    }
}

struct FixTarget: Identifiable, Equatable {
    let word: String
    let shown: String
    let segment: Int
    var id: String { "\(segment)-\(word)" }
}

/// Fix how one word is said: listen to other readings, type your own, or read the sentence again.
struct FixWordSheet: View {
    @EnvironmentObject private var state: AppState
    let jobId: String
    let target: FixTarget
    /// Called when a fix was applied and the audio has changed.
    let onFixed: () -> Void
    let onClose: () -> Void

    @StateObject private var player = AudioPlayer()
    @State private var options: [FixOption] = []
    @State private var loaded = false
    @State private var custom = ""
    @State private var busy: String?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    Text("Fix this word").font(Theme.title).foregroundStyle(Theme.black)
                        .accessibilityIdentifier("fixHeading")
                    AmharicText(text: target.word, font: .system(size: 28, weight: .medium))

                    if let problem {
                        ProblemCard(message: problem)
                    }
                    if let busy {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.black)
                            Text(busy).font(Theme.body).foregroundStyle(Theme.black)
                        }
                        .card(fill: Theme.grey, padding: 14)
                    }

                    if !loaded {
                        ProgressView().tint(Theme.black)
                    } else if options.isEmpty {
                        NoteText(text: "No other readings exist for this word yet. Type how it should sound below.")
                    } else {
                        Text("Listen, then use the one that sounds right")
                            .font(Theme.small.weight(.medium)).foregroundStyle(Theme.black)
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            HStack(spacing: 12) {
                                Text(option.label ?? "Option \(index + 1)")
                                    .font(Theme.body).foregroundStyle(Theme.black)
                                Spacer()
                                Button("Listen") {
                                    Task { await listen(optionId: option.optionId, custom: nil) }
                                }
                                .buttonStyle(QuietButtonStyle())
                                .accessibilityIdentifier("fixListen-\(index)")
                                Button("Use") {
                                    Task { await apply(.option(word: target.word, optionId: option.optionId)) }
                                }
                                .buttonStyle(QuietButtonStyle())
                                .accessibilityIdentifier("fixUse-\(index)")
                            }
                            .disabled(busy != nil)
                            .card(fill: Theme.white, padding: 12)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Or type how it should sound").font(Theme.small.weight(.medium))
                            .foregroundStyle(Theme.black)
                        TextField("Your spelling", text: $custom)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .field()
                            .accessibilityIdentifier("fixCustomField")
                        HStack(spacing: 20) {
                            Button("Listen") { Task { await listen(optionId: nil, custom: typed) } }
                                .buttonStyle(QuietButtonStyle())
                            Button("Use") {
                                Task { await apply(.custom(word: target.word, spelling: typed)) }
                            }
                            .buttonStyle(QuietButtonStyle())
                        }
                        .disabled(busy != nil || typed.count < 2)
                    }

                    Button("Read the whole sentence again") {
                        Task { await apply(.rereadSentence(segment: target.segment)) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(busy != nil)
                    .accessibilityIdentifier("rereadButton")

                    NoteText(text: "Listening to a reading is free when it has been made before; a brand new one costs under 1 credit. Using a fix costs 1.5 credits and records that sentence again.")
                }
                .page()
            }
            .background(Theme.white)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onClose() }.accessibilityIdentifier("fixClose")
                }
            }
        }
        .tint(Theme.black)
        .task { await load() }
        .onDisappear { player.stop() }
    }

    private var typed: String { custom.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func load() async {
        guard !loaded else { return }
        do {
            options = try await state.api.fixCandidates(word: target.word)
        } catch {
            let e = APIError.wrap(error)
            // "No other readings yet" is an answer, not a failure.
            if e.status != 404 { problem = state.report(error) }
        }
        loaded = true
    }

    private func listen(optionId: Int?, custom: String?) async {
        busy = "Preparing this reading."
        problem = nil
        defer { busy = nil }
        do {
            var preview = try await state.api.fixPreview(word: target.word, optionId: optionId,
                                                         custom: custom)
            var tries = 0
            while !preview.isDone {
                if preview.isFailed || tries > 90 {
                    problem = "That reading could not be made. Try another."
                    return
                }
                tries += 1
                try await Task.sleep(nanoseconds: UInt64((Launch.isMock ? 0.2 : 2) * 1_000_000_000))
                preview = try await state.api.fixPreviewStatus(id: preview.previewId)
            }
            let url = try await state.api.fixPreviewAudio(id: preview.previewId)
            if player.load(url: url) { player.toggle() }
            await state.refresh()
        } catch {
            problem = state.report(error)
        }
    }

    private func apply(_ fix: FixEdit) async {
        busy = "Recording the sentence again."
        problem = nil
        player.stop()
        defer { busy = nil }
        do {
            var batch = try await state.api.fixApply(jobId: jobId, fix: fix)
            guard let batchId = batch.batchId else {
                problem = "The fix could not be started. Try again."
                return
            }
            var tries = 0
            while !batch.isOver && tries < 180 {
                tries += 1
                try await Task.sleep(nanoseconds: UInt64((Launch.isMock ? 0.2 : 2) * 1_000_000_000))
                batch = try await state.api.fixStatus(jobId: jobId, batchId: batchId)
            }
            if batch.status == "done" {
                await state.refresh()
                onFixed()
            } else {
                problem = batch.error.map(APIError.sentenceCase)
                    ?? "The fix did not finish. Your credits were returned."
            }
        } catch {
            problem = state.report(error)
        }
    }
}

/// Standing instructions for every script Kinbir writes.
struct ScriptRulesView: View {
    @EnvironmentObject private var state: AppState
    @State private var rules = ""
    @State private var loaded = false
    @State private var busy = false
    @State private var saved = false
    @State private var problem: String?

    private let limit = 4000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text("Script rules").font(Theme.title).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("rulesHeading")
                Text("Kinbir follows these every time it writes or changes a script for you.")
                    .font(Theme.body).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $rules)
                    .font(Theme.body)
                    .foregroundStyle(Theme.black)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .card(fill: Theme.grey, padding: 12)
                    .accessibilityIdentifier("rulesEditor")
                    .onChange(of: rules) { _, new in
                        saved = false
                        if new.count > limit { rules = String(new.prefix(limit)) }
                    }

                if let problem {
                    ProblemCard(message: problem)
                }

                Button {
                    Task { await save() }
                } label: {
                    BusyLabel(title: saved ? "Saved" : "Save rules", busy: busy)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
                .accessibilityIdentifier("saveRulesButton")

                if let template = state.me?.scriptRulesDefault, !template.isEmpty {
                    Button("Reset to the Kinbir template") { rules = template }
                        .buttonStyle(QuietButtonStyle())
                }
                NoteText(text: "Leave it empty to use no rules. \(rules.count) of \(limit) characters.")
            }
            .page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task {
            guard !loaded else { return }
            await state.refresh()
            rules = state.me?.scriptRules ?? ""
            loaded = true
            saved = false
        }
    }

    private func save() async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            rules = try await state.api.saveScriptRules(rules)
            await state.refresh()
            saved = true
        } catch {
            problem = state.report(error)
        }
    }
}
