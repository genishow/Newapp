import Foundation
import StoreKit

/// App Store purchases (D-449). The same plans as kinbir.com, sold the way Apple
/// requires inside an iPhone app. Every finished purchase is sent to the server,
/// which checks it with Apple and adds the credits; only then is it marked finished,
/// so a purchase interrupted by a dropped connection is retried on the next launch.
@MainActor
final class Store: ObservableObject {
    struct Plan: Identifiable, Equatable {
        let id: String
        let tier: String
        let title: String
        let credits: Int
        let isTopUp: Bool
    }

    /// Product ids as created in App Store Connect, matching the server's list.
    static let plans: [Plan] = [
        Plan(id: "com.geni.kinbir.starter.monthly", tier: "starter", title: "Starter", credits: 110, isTopUp: false),
        Plan(id: "com.geni.kinbir.creator.monthly", tier: "creator", title: "Pro", credits: 325, isTopUp: false),
        Plan(id: "com.geni.kinbir.studio.monthly", tier: "studio", title: "Studio", credits: 650, isTopUp: false),
        Plan(id: "com.geni.kinbir.topup60", tier: "topup10", title: "Top-up", credits: 60, isTopUp: true),
    ]

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var loading = false
    @Published private(set) var busyId: String?
    @Published var message: String?

    private weak var state: AppState?
    private var updates: Task<Void, Never>?

    func start(state: AppState) {
        self.state = state
        guard updates == nil, !Launch.isMock else { return }
        // Renewals, purchases approved later (Ask to Buy) and anything left unfinished.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result, quiet: true)
            }
        }
        Task { [weak self] in
            for await result in Transaction.unfinished {
                await self?.handle(result, quiet: true)
            }
        }
    }

    func load() async {
        guard products.isEmpty, !Launch.isMock else { return }
        loading = true
        defer { loading = false }
        do {
            let found = try await Product.products(for: Self.plans.map(\.id))
            products = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        } catch {
            message = T("The App Store did not answer. Try again in a moment.")
        }
    }

    /// The price as the App Store shows it in this country, like "$19.99".
    func price(_ plan: Plan) -> String? {
        products[plan.id]?.displayPrice
    }

    func buy(_ plan: Plan) async {
        guard let state, busyId == nil else { return }
        message = nil
        busyId = plan.id
        defer { busyId = nil }
        if Launch.isMock {
            await mockBuy(plan, state: state)
            return
        }
        guard let product = products[plan.id] else {
            message = T("This is not on sale yet. Try again later.")
            return
        }
        var options: Set<Product.PurchaseOption> = []
        if let raw = state.me?.appleAccountToken, let token = UUID(uuidString: raw) {
            options.insert(.appAccountToken(token))
        }
        do {
            switch try await product.purchase(options: options) {
            case .success(let result):
                await handle(result, quiet: false)
            case .pending:
                message = T("Waiting for approval. The credits arrive as soon as it is approved.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = T("The purchase did not go through. You were not charged.")
        }
    }

    /// Sends every purchase Apple knows for this Apple ID to the server again.
    /// Nothing is added twice: the server counts each purchase once.
    func restore() async {
        guard let state, busyId == nil else { return }
        message = nil
        busyId = "restore"
        defer { busyId = nil }
        if Launch.isMock {
            message = T("Your purchases are up to date.")
            return
        }
        try? await AppStore.sync()
        var sent = 0
        for await result in Transaction.currentEntitlements {
            if case .verified = result {
                await handle(result, quiet: true)
                sent += 1
            }
        }
        await state.refresh()
        message = sent == 0 ? T("No purchases found for this Apple ID.")
                            : T("Your purchases are up to date.")
    }

    private func handle(_ result: VerificationResult<Transaction>, quiet: Bool) async {
        guard let state else { return }
        guard case .verified(let transaction) = result else {
            if !quiet { message = T("Apple could not confirm this purchase.") }
            return
        }
        do {
            let answer = try await state.api.reportApplePurchase(signedTransaction: result.jwsRepresentation)
            await transaction.finish()
            await state.refresh()
            if !quiet {
                let added = Fmt.credits(answer.creditsGranted ?? 0)
                message = answer.alreadyAdded == true ? T("Your purchases are up to date.")
                                                      : Tf("Thank you. %@ credits were added.", added)
                Haptics.success()
            }
        } catch {
            // Not finished on purpose: StoreKit hands it back and it is sent again later.
            if !quiet {
                message = T("Paid, but the credits are not added yet. They will be added automatically, or tap Restore purchases.")
            }
        }
    }

    private func mockBuy(_ plan: Plan, state: AppState) async {
        do {
            let answer = try await state.api.reportApplePurchase(signedTransaction: "mock." + plan.id)
            await state.refresh()
            message = Tf("Thank you. %@ credits were added.", Fmt.credits(answer.creditsGranted ?? 0))
        } catch {
            message = state.report(error)
        }
    }
}
