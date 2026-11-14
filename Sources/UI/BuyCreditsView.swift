import StoreKit
import SwiftUI

/// Plans and top-ups through the App Store (D-449). A plan bought on kinbir.com is
/// managed there, so this screen never sells a second plan on top of it.
struct BuyCreditsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: Store
    @Environment(\.openURL) private var openURL

    private var planVia: String? { state.me?.planVia }
    private var hasPlan: Bool { !(state.me?.tier ?? "").isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text(T("Buy credits")).screenTitle(amharic: A("Buy credits"))
                    .accessibilityIdentifier("buyHeading")

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.credits(state.balance))
                        .font(.system(size: 34, weight: .medium)).foregroundStyle(Theme.black)
                        .accessibilityIdentifier("buyBalance")
                    Text(T("credits now")).font(Theme.body).foregroundStyle(Theme.black)
                }
                NoteText(text: T("A one-minute voiceover is about 2.5 credits. A one-minute video with footage is about 12."))

                if let message = store.message {
                    Text(message).font(Theme.body).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                        .card(fill: Theme.lime, padding: 14)
                        .accessibilityIdentifier("buyMessage")
                }

                if planVia == "web" {
                    Text(T("Your plan is paid on the Kinbir website, so it is changed or cancelled there. Credits you buy there show here too."))
                        .font(Theme.body).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                        .card(fill: Theme.grey, padding: 14)
                        .accessibilityIdentifier("buyWebPlanNote")
                } else {
                    Text(T("Monthly plans")).font(Theme.heading).foregroundStyle(Theme.black)
                    ForEach(Store.plans.filter { !$0.isTopUp }) { plan in
                        planRow(plan, current: state.me?.tier == plan.tier)
                    }
                    if planVia == "apple" {
                        Button(T("Change or cancel my plan")) {
                            openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("manageSubscription")
                    }
                }

                if hasPlan {
                    Text(T("Top up")).font(Theme.heading).foregroundStyle(Theme.black)
                    ForEach(Store.plans.filter(\.isTopUp)) { plan in
                        planRow(plan, current: false)
                    }
                } else {
                    NoteText(text: T("Top-ups are for plans. Start a plan first, then top up any time."))
                }

                Button {
                    Task { await store.restore() }
                } label: {
                    BusyLabel(title: T("Restore purchases"), busy: store.busyId == "restore")
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(store.busyId != nil)
                .accessibilityIdentifier("restorePurchases")

                // Apple requires these words and links next to a subscription.
                NoteText(text: T("Plans renew every month until you cancel. Payment is charged to your Apple ID when you confirm. It renews automatically unless cancelled at least 24 hours before the end of the month, and you are charged for the next month within 24 hours before it starts. Cancel any time in your iPhone Settings: tap your name, then Subscriptions. Unused plan credits carry over for one month."))
                HStack(spacing: 16) {
                    Link(T("Terms of Use"), destination: URL(string: "https://kinbir.com/terms")!)
                    Link(T("Privacy Policy"), destination: URL(string: "https://kinbir.com/privacy")!)
                }
                .font(Theme.smallMedium)
                .foregroundStyle(Theme.black)
            }
            .page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.start(state: state)
            await store.load()
        }
        .onDisappear { store.message = nil }
    }

    private func planRow(_ plan: Store.Plan, current: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(T(plan.title)).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                Text(plan.isTopUp ? Tf("%@ credits, once", "\(plan.credits)")
                                  : Tf("%@ credits every month", "\(plan.credits)"))
                    .font(Theme.small).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            if current {
                Pill(text: T("Your plan"), fill: Theme.lime)
            } else {
                Button {
                    Task { await store.buy(plan) }
                } label: {
                    if store.busyId == plan.id {
                        ProgressView().tint(Theme.white)
                    } else {
                        Text(priceLabel(plan)).font(Theme.smallMedium)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minWidth: 96, minHeight: 40)
                .background(Capsule().fill(Theme.black))
                .foregroundStyle(Theme.white)
                .buttonStyle(.plain)
                .disabled(store.busyId != nil || (store.price(plan) == nil && !Launch.isMock))
                .accessibilityIdentifier("buy-\(plan.tier)")
            }
        }
        .card(fill: Theme.white, padding: 14)
    }

    private func priceLabel(_ plan: Store.Plan) -> String {
        if Launch.isMock { return plan.isTopUp ? "$9.99" : "$19.99" }
        guard let price = store.price(plan) else { return store.loading ? "..." : T("Not available") }
        return plan.isTopUp ? price : Tf("%@ / month", price)
    }
}
