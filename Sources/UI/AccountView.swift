import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("kinbir.appearance") private var appearance = "system"

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return Tf("Version %@, build %@", v, b)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text(T("Account")).screenTitle(amharic: A("Account"))
                    .accessibilityIdentifier("accountHeading")

                VStack(alignment: .leading, spacing: 8) {
                    Text(state.me?.email ?? "Signed in")
                        .font(Theme.bodyMedium).foregroundStyle(Theme.black)
                        .accessibilityIdentifier("accountEmail")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.credits(state.balance))
                            .font(.system(size: 40, weight: .medium)).foregroundStyle(Theme.black)
                            .accessibilityIdentifier("accountBalance")
                        Text(T("credits")).font(Theme.body).foregroundStyle(Theme.black)
                    }
                    if let tier = state.me?.tier, !tier.isEmpty {
                        Pill(text: Tf("%@ plan", planName(tier)), fill: Theme.white)
                    }
                    Text(T("A one-minute voiceover is about 2.5 credits."))
                        .font(Theme.small).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink(value: Route.buyCredits) {
                        Text(state.me?.planVia == "web" ? T("My plan") : T("Buy credits"))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("buyCreditsButton")
                    NavigationLink(value: Route.promo) {
                        Text(T("Earn free credits with a video"))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("earnCreditsButton")
                }
                .card(fill: Theme.lime)

                VStack(spacing: 0) {
                    NavigationLink(value: Route.voices) { rowLabel(T("My voices")) }
                        .accessibilityIdentifier("myVoicesRow")
                    divider
                    NavigationLink(value: Route.scriptRules) { rowLabel(T("Script rules")) }
                        .accessibilityIdentifier("scriptRulesRow")
                    divider
                    Link(destination: URL(string: "https://kinbir.com/privacy")!) { rowLabel(T("Privacy")) }
                    divider
                    Link(destination: URL(string: "https://kinbir.com/terms")!) { rowLabel(T("Terms")) }
                    divider
                    Link(destination: URL(string: "mailto:support@kinbir.com")!) { rowLabel(T("Support")) }
                }
                .card(fill: Theme.white, padding: 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text(T("Appearance")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                    Picker(T("Appearance"), selection: $appearance) {
                        Text(T("Same as phone")).tag("system")
                        Text(T("Light")).tag("light")
                        Text(T("Dark")).tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("appearancePicker")
                }
                .card(fill: Theme.grey, padding: 14)

                Button(T("Sign out")) { state.signOut() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("signOutButton")

                NavigationLink(value: Route.deleteAccount) { Text(T("Delete my account")) }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("deleteAccountLink")

                NoteText(text: version)
            }
            .page()
        }
        .background(Theme.white)
        .toolbar(.hidden, for: .navigationBar)
        .task { await state.refresh() }
    }

    private var divider: some View {
        Rectangle().fill(Theme.grey).frame(height: 1).padding(.horizontal, 14)
    }

    private func rowLabel(_ title: String) -> some View {
        HStack {
            Text(title).font(Theme.body).foregroundStyle(Theme.black)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func planName(_ tier: String) -> String {
        switch tier {
        case "starter": return T("Starter")
        case "creator": return T("Pro")
        case "studio": return T("Studio")
        default: return tier.capitalized
        }
    }
}

/// Permanent. The email must be typed back; the server checks it too.
struct DeleteAccountView: View {
    @EnvironmentObject private var state: AppState
    @State private var typed = ""
    @State private var busy = false
    @State private var problem: String?

    private var email: String { state.me?.email ?? "" }
    private var matches: Bool {
        !email.isEmpty && typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email.lowercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text(T("Delete my account")).screenTitle(amharic: A("Delete my account"))
                    .accessibilityIdentifier("deleteHeading")

                whatGoes

                Text(Tf("Type your email to confirm: %@", email))
                    .font(Theme.small).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                TextField(T("Your email"), text: $typed)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .field()
                    .accessibilityIdentifier("deleteEmailField")

                if let problem {
                    ProblemCard(message: problem)
                }

                Button {
                    Task { await delete() }
                } label: {
                    BusyLabel(title: T("Delete my account for good"), busy: busy)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(busy || !matches)
                .accessibilityIdentifier("deleteConfirmButton")
            }
            .page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    /// What is removed, the credits that go with it, and what is kept. Shown before the
    /// email is typed, with the balance always stated, even at zero.
    private var whatGoes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("This removes your cloned voice, the enrollment video it was made from, your avatar photo and every clip made from it, and every voiceover and video you have generated. It cannot be undone."))
                .font(Theme.body).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
            Text(state.balance > 0
                 ? Tf("You will lose your %@ remaining credits.", Fmt.credits(state.balance))
                 : T("You have no credits left to lose."))
                .font(Theme.bodyMedium).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("deleteCreditsLine")
            Text(state.me?.planVia == "apple"
                 ? T("Your plan is billed by Apple, and we cannot cancel it for you. Cancel it first in your iPhone Settings: tap your name, then Subscriptions.")
                 : state.me?.hasSubscription == true
                 ? T("Your subscription is cancelled first, so you are not billed again.")
                 : T("You have no subscription, so there is nothing to cancel."))
                .font(Theme.small).foregroundStyle(Theme.black)
                .fixedSize(horizontal: false, vertical: true)
            NoteText(text: T("We keep our own billing records of what was charged, and a note that the account was deleted. Those hold no voice, video or photo."))
                .accessibilityIdentifier("deleteKeepNote")
        }
        .card(fill: Theme.grey, padding: 14)
    }

    private func delete() async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            try await state.api.deleteAccount(confirmEmail: email)
            state.signOut()
        } catch {
            problem = state.report(error)
        }
    }
}
