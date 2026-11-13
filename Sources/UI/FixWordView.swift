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
                Text(T("Script rules")).screenTitle(amharic: A("Script rules"))
                    .accessibilityIdentifier("rulesHeading")
                Text(T("Kinbir follows these every time it writes or changes a script for you."))
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
                    BusyLabel(title: saved ? T("Saved") : T("Save rules"), busy: busy)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
                .accessibilityIdentifier("saveRulesButton")

                if let template = state.me?.scriptRulesDefault, !template.isEmpty {
                    Button(T("Reset to the Kinbir template")) { rules = template }
                        .buttonStyle(QuietButtonStyle())
                }
                NoteText(text: Tf("Leave it empty to use no rules. %@ of %@ characters.", "\(rules.count)", "\(limit)"))
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
