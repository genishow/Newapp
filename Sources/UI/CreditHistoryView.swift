import SwiftUI

/// The free credits the account received, and where each came from (Geni: "how
/// many credits they received from the app for free, not every credit tracking").
struct CreditHistoryView: View {
    @EnvironmentObject private var state: AppState

    @State private var history: CreditHistory?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text(T("Free credits")).screenTitle(amharic: A("Free credits"))
                    .accessibilityIdentifier("creditHistoryHeading")

                if let history {
                    total(T("Free credits you received"), history.gifts, id: "historyGifts")

                    if history.freeItems.isEmpty {
                        NoteText(text: T("Nothing yet. Free credits you receive will show here."))
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(history.freeItems) { item in
                                row(item)
                                if item.id != history.freeItems.last?.id {
                                    Rectangle().fill(Theme.grey).frame(height: 1).padding(.horizontal, 14)
                                }
                            }
                        }
                        .card(fill: Theme.white, padding: 4)
                        NoteText(text: T("Only credits you got for free are shown here."))
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
