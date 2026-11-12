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

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text(codeSent ? "Enter your code" : "Start with your email")
                    .font(Theme.title).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("signInHeading")

                if codeSent {
                    Text("We sent a 6-digit code to \(email). It works for 10 minutes.")
                        .font(Theme.body).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("6-digit code", text: $code)
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
                        BusyLabel(title: "Continue", busy: busy)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || code.count != 6)
                    .accessibilityIdentifier("verifyButton")

                    HStack(spacing: 20) {
                        Button("Send a new code") { Task { await sendCode() } }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(busy || now < canResendAt)
                            .opacity(now < canResendAt ? 0.4 : 1)
                            .accessibilityIdentifier("resendButton")
                        Button("Use a different email") {
                            codeSent = false
                            code = ""
                            problem = nil
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                } else {
                    Text("No password. We email you a code. If you are new, this also creates your account.")
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
                        BusyLabel(title: "Send me a code", busy: busy)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || !EmailRules.looksValid(email))
                    .accessibilityIdentifier("sendCodeButton")
                }

                if let problem {
                    ProblemCard(message: problem)
                }
            }
            .page()
        }
        .background(Theme.white)
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(clock) { now = $0 }
    }

    private var cleanEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sendCode() async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            try await state.api.requestCode(email: cleanEmail)
            email = cleanEmail
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
