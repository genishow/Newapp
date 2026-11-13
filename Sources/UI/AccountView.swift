import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(UILanguage.key) private var uiLanguage = UILanguage.am.rawValue

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return Tf("Version %@, build %@", v, b)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text(T("Account")).font(Theme.title).foregroundStyle(Theme.black)
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
                        Pill(text: planName(tier) + " plan", fill: Theme.white)
                    }
                    Text(T("A one-minute voiceover is about 2.5 credits. ") + T(APIError.buyingNote))
                        .font(Theme.small).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
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

                VStack(alignment: .leading, spacing: 10) {
                    Text(T("Interface language")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                    Picker(T("Interface language"), selection: $uiLanguage) {
                        ForEach(UILanguage.allCases) { Text($0.name).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("uiLanguagePicker")
                }
                .card(fill: Theme.white, padding: 14)

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
                Text(T("Delete my account")).font(Theme.title).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("deleteHeading")

                Text(T("This removes your account, your voices, your scripts and any credits left. It cannot be undone."))
                    .font(Theme.body).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .card(fill: Theme.grey, padding: 14)

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
