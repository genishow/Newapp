import SwiftUI

/// What the account was given, bought and used (Geni: "show the history, how many
/// credits they got so far"). One line per thing; newest first.
struct CreditHistoryView: View {
    @EnvironmentObject private var state: AppState

    @State private var history: CreditHistory?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text(T("Credit history")).screenTitle(amharic: A("Credit history"))
                    .accessibilityIdentifier("creditHistoryHeading")

                if let history {
                    HStack(alignment: .top, spacing: 10) {
                        total(T("Free credits"), history.gifts, id: "historyGifts")
                        total(T("Bought"), history.bought, id: "historyBought")
                        total(T("Used"), history.used, id: "historyUsed")
                    }

                    if history.items.isEmpty {
                        NoteText(text: T("Nothing here yet. Credits you get and use will show here."))
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(history.items) { item in
                                row(item)
                                if item.id != history.items.last?.id {
                                    Rectangle().fill(Theme.grey).frame(height: 1).padding(.horizontal, 14)
                                }
                            }
                        }
                        .card(fill: Theme.white, padding: 4)
                        NoteText(text: T("Shows your latest 60."))
                    }
                } else if let problem {
                    ProblemCard(message: problem)
                    Button(T("Try again")) { Task { await load() } }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func total(_ title: String, _ value: Double, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Fmt.credits(value))
                .font(.system(size: 26, weight: .medium)).foregroundStyle(Theme.black)
                .accessibilityIdentifier(id)
            Text(title).font(Theme.small).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(fill: Theme.lime, padding: 12)
        .accessibilityElement(children: .combine)
    }

    private func row(_ item: CreditHistory.Item) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(T(item.label)).font(Theme.body).foregroundStyle(Theme.black)
                Text(T(Fmt.ago(item.at))).font(Theme.small).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(CreditHistory.signed(item.credits))
                .font(Theme.bodyMedium)
                .foregroundStyle(Theme.black)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        problem = nil
        do {
            history = try await state.api.creditHistory()
        } catch {
            if history == nil { problem = state.report(error) }
        }
    }
}
