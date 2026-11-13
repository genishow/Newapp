import SwiftUI

/// Email, then a six-digit code. Signing up and signing in are the same step.
struct SignInView: View {
    @EnvironmentObject private var state: AppState

    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var problem: String?
    @State private var canResendAt = Date.distantPast
    @State private var now = Date()
    /// What the server said after sending: how long the code works, or that email is off.
    @State private var sentNotice = ""

    private var resendTitle: String {
        guard now < canResendAt else { return T("Send a new code") }
        let left: String = Fmt.clock(canResendAt.timeIntervalSince(now))
        return T("Send a new code") + " (" + left + ")"
    }

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text(codeSent ? T("Enter your code") : T("Start with your email"))
                    .screenTitle()
                    .accessibilityIdentifier("signInHeading")

                if codeSent {
                    Text(sentNotice)
                        .font(Theme.body).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("codeSentNotice")

                    TextField(T("6-digit code"), text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .field()
                        .accessibilityIdentifier("codeField")
                        .onChange(of: code) { _, new in
                            let digits = new.filter { $0.isNumber }
                            if digits != new || digits.count > 6 { code = String(digits.prefix(6)) }
                        }

                    Button {
                        Task { await verify() }
                    } label: {
                        BusyLabel(title: T("Continue"), busy: busy)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || code.count != 6)
                    .accessibilityIdentifier("verifyButton")

                    HStack(spacing: 20) {
                        Button(resendTitle) { Task { await sendCode() } }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(busy || now < canResendAt)
                            .opacity(now < canResendAt ? 0.4 : 1)
                            .accessibilityIdentifier("resendButton")
                        Button(T("Use a different email")) {
                            codeSent = false
                            code = ""
                            problem = nil
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                } else {
                    Text(T("No password. We email you a code. If you are new, this also creates your account."))
                        .font(Theme.body).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("you@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .field()
                        .accessibilityIdentifier("emailField")

                    Button {
                        Task { await sendCode() }
                    } label: {
                        BusyLabel(title: T("Send me a code"), busy: busy)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || !EmailRules.looksValid(email))
                    .accessibilityIdentifier("sendCodeButton")
                }

                if let problem {
                    ProblemCard(message: problem)
                }

                legal
            }
            .page()
        }
        .background(Theme.white)
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(clock) { now = $0 }
    }

    /// Signing in creates the account, so this is where the terms are agreed to.
    private var legal: some View {
        VStack(alignment: .leading, spacing: 6) {
            NoteText(text: T("By signing in you agree to the Terms, the Voice Policy and the Privacy Policy. You must be 18 or older."))
                .accessibilityIdentifier("signInAgeNote")
            HStack(spacing: 20) {
                Link(T("Terms"), destination: URL(string: "https://kinbir.com/terms")!)
                    .accessibilityIdentifier("signInTermsLink")
                Link(T("Voice Policy"), destination: URL(string: "https://kinbir.com/voice-policy")!)
                    .accessibilityIdentifier("signInVoicePolicyLink")
                Link(T("Privacy Policy"), destination: URL(string: "https://kinbir.com/privacy")!)
                    .accessibilityIdentifier("signInPrivacyLink")
            }
            .font(Theme.smallMedium)
            .foregroundStyle(Theme.black)
        }
    }

    private var cleanEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sendCode() async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            let answer = try await state.api.requestCode(email: cleanEmail)
            email = cleanEmail
            sentNotice = T(answer.notice(email: cleanEmail))
            codeSent = true
            canResendAt = Date().addingTimeInterval(30)
        } catch {
            problem = APIError.wrap(error).message
        }
    }

    private func verify() async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            let result = try await state.api.verify(email: cleanEmail, code: code)
            await state.signIn(with: result)
        } catch {
            problem = APIError.wrap(error).message
            code = ""
        }
    }
}
