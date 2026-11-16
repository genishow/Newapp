import Foundation
import SwiftUI

/// The one shared object: who is signed in and what the server last said about them.
@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case loading
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var me: WhoAmI?
    /// Shown once on the Welcome screen after a forced sign-out.
    @Published var notice: String?
    /// The tab on show: 0 Create, 1 Library, 2 Account.
    @Published var selectedTab = 0
    /// A screen to open in the Library, from a tapped notification.
    @Published var pendingRoute: Route?
    /// A screen to open on the Account tab, e.g. buying credits from the script page.
    @Published var pendingAccountRoute: Route?

    let api: KinbirAPI
    private let store: CodeStore

    init(api: KinbirAPI, store: CodeStore) {
        self.api = api
        self.store = store
    }

    /// Builds the app's real dependencies, or the mock ones for UI tests.
    static func make() -> AppState {
        if Launch.isMock {
            // Each UI test starts from the same place: Amharic, nothing half done.
            UserDefaults.standard.removeObject(forKey: "kinbir.language")
            UserDefaults.standard.removeObject(forKey: "kinbir.welcomeLang")
            UserDefaults.standard.removeObject(forKey: "kinbir.pendingScript")
            UserDefaults.standard.removeObject(forKey: "kinbir.voiceChoice")
            // Each UI test starts clean: nothing remembered from the test before it.
            for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix("videojob.") || key.hasPrefix("planjob.") || key.hasPrefix("kinbir.fixBatch.")
                || key.hasPrefix("kinbir.tries.") || key.hasPrefix("kinbir.ear.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
            let store = MemoryCodeStore()
            let api = MockAPI(scenario: .init(noVoice: Launch.mockNoVoice,
                                              noCredits: Launch.mockNoCredits))
            return AppState(api: api, store: store)
        }
        let store = KeychainCodeStore()
        let api = LiveAPI(accessCode: { store.load() })
        return AppState(api: api, store: store)
    }

    var accessCode: String? { store.load() }
    var balance: Double { me?.balance ?? 0 }
    var activeVoice: VoiceSummary? {
        guard let me else { return nil }
        return me.allVoices.first { $0.voiceId == me.activeVoiceId } ?? me.allVoices.first
    }

    func start() async {
        TempFiles.clear()
        guard store.load() != nil else {
            phase = .signedOut
            return
        }
        do {
            me = try await api.whoami()
            phase = .signedIn
        } catch {
            let e = APIError.wrap(error)
            if e.kind == .sessionExpired {
                signOut()
            } else {
                // Offline at launch: stay signed in, the screens show their own errors.
                phase = .signedIn
            }
        }
    }

    func signIn(with result: AuthResult) async {
        store.save(result.accessCode)
        selectedTab = 0          // signed in: the script page first
        me = WhoAmI(email: result.email, voices: nil, activeVoiceId: nil,
                    creditsBalance: result.creditsBalance, tier: nil, hasPaid: nil,
                    trialMaxChars: nil, scriptRules: nil, scriptRulesDefault: nil,
                    enPace: nil, enEmphasis: nil)
        phase = .signedIn
        await refresh()
    }

    /// Reloads the account. Quiet on failure: the caller's own request reports errors.
    func refresh() async {
        guard store.load() != nil else { return }
        do {
            me = try await api.whoami()
        } catch {
            _ = report(error)
        }
    }

    func signOut(notice: String? = nil) {
        Notifications.signedOut(api: api, accessCode: store.load())
        store.clear()
        me = nil
        self.notice = notice
        phase = .signedOut
    }

    /// Turns any error into the sentence to show, and signs out if the session died.
    func report(_ error: Error) -> String {
        let e = APIError.wrap(error)
        if e.kind == .sessionExpired {
            signOut(notice: e.message)
        }
        return e.message
    }

    /// Opens a voiceover or video in the Library, from a notification.
    func open(_ route: Route) {
        guard phase == .signedIn else { return }
        selectedTab = 1
        pendingRoute = route
    }

    // MARK: AI processing consent

    /// Apple's review rule 5.1.2(i): before personal data goes to a third-party
    /// AI service, the app says so and the person agrees. Asked once per account
    /// on this phone, right after sign in.
    @Published var aiConsentTick = 0

    private var aiConsentKey: String? {
        guard let code = store.load() else { return nil }
        return "aiConsent." + Fmt.ownerTag(code)
    }

    var needsAIConsent: Bool {
        if Launch.isMock { return Launch.mockAskAIConsent && aiConsentTick == 0 }
        guard let key = aiConsentKey else { return false }
        return !UserDefaults.standard.bool(forKey: key)
    }

    func giveAIConsent() {
        if let key = aiConsentKey, !Launch.isMock { UserDefaults.standard.set(true, forKey: key) }
        aiConsentTick += 1
    }

    // MARK: library cache

    /// The last Library list, kept on the phone so the Library shows at once
    /// and refreshes behind it. Per account; never in UI-test runs.
    private var libraryKey: String? {
        guard let code = store.load() else { return nil }
        return "library." + Fmt.ownerTag(code)
    }

    func loadLibraryCache() -> LibraryCache? {
        guard !Launch.isMock, let key = libraryKey,
              let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return (try? JSONDecoder().decode(LibraryCache.self, from: data))?.fresh()
    }

    func saveLibraryCache(_ cache: LibraryCache) {
        guard !Launch.isMock, let key = libraryKey,
              let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: draft

    private var draftKey: String? {
        guard let code = store.load() else { return nil }
        return "draft." + Fmt.ownerTag(code)
    }

    func loadDraft() -> String {
        // UI tests share one simulator, so a draft from one test must not leak into the next.
        guard !Launch.isMock, let key = draftKey else { return "" }
        return UserDefaults.standard.string(forKey: key) ?? ""
    }

    func saveDraft(_ text: String) {
        guard let key = draftKey else { return }
        UserDefaults.standard.set(text, forKey: key)
    }
}
