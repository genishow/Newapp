import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var state: AppState
    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v), build \(b)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text("Account").font(Theme.title).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("accountHeading")

                VStack(alignment: .leading, spacing: 8) {
                    Text(state.me?.email ?? "Signed in")
                        .font(Theme.body.weight(.medium)).foregroundStyle(Theme.black)
                        .accessibilityIdentifier("accountEmail")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.credits(state.balance))
                            .font(.system(size: 40, weight: .medium)).foregroundStyle(Theme.black)
                            .accessibilityIdentifier("accountBalance")
                        Text("credits").font(Theme.body).foregroundStyle(Theme.black)
                    }
                    if let tier = state.me?.tier, !tier.isEmpty {
                        Pill(text: planName(tier) + " plan", fill: Theme.white)
                    }
                    Text("A one-minute voiceover is about 2.5 credits. " + APIError.buyingNote)
                        .font(Theme.small).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card(fill: Theme.lime)

                VStack(spacing: 0) {
                    NavigationLink(value: Route.voices) { rowLabel("My voices") }
                        .accessibilityIdentifier("myVoicesRow")
                    divider
                    Link(destination: URL(string: "https://kinbir.com/privacy")!) { rowLabel("Privacy") }
                    divider
                    Link(destination: URL(string: "https://kinbir.com/terms")!) { rowLabel("Terms") }
                    divider
                    Link(destination: URL(string: "mailto:support@kinbir.com")!) { rowLabel("Support") }
                }
                .card(fill: Theme.white, padding: 4)

                Button("Sign out") { state.signOut() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("signOutButton")

                NavigationLink(value: Route.deleteAccount) { Text("Delete my account") }
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
        case "starter": return "Starter"
        case "creator": return "Pro"
        case "studio": return "Studio"
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
                Text("Delete my account").font(Theme.title).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("deleteHeading")

                Text("This removes your account, your voices, your scripts and any credits left. It cannot be undone.")
                    .font(Theme.body).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .card(fill: Theme.grey, padding: 14)

                Text("Type your email to confirm: \(email)")
                    .font(Theme.small).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Your email", text: $typed)
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
                    BusyLabel(title: "Delete my account for good", busy: busy)
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
