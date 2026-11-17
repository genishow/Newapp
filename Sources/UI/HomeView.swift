import SwiftUI

/// Places a screen can lead to inside a tab.
enum Route: Hashable {
    case job(String)
    /// Fix words or sentences of this voiceover.
    case fix(String)
    /// Make a video from this voiceover.
    case video(String)
    /// A video that is rendering or finished.
    case videoJob(String, landscape: Bool)
    case voices
    case enroll
    case deleteAccount
    case scriptRules
    case buyCredits
    case promo
    case creditHistory
}

/// The signed-in app: Create, Library, Account.
struct HomeView: View {
    @EnvironmentObject private var state: AppState

    init() {
        let bar = UITabBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = Theme.dynamicUI(light: 0xFFFFFF, dark: 0x0B0B0F)
        UITabBar.appearance().standardAppearance = bar
        UITabBar.appearance().scrollEdgeAppearance = bar
        BrandControls.apply()
    }

    var body: some View {
        TabView(selection: $state.selectedTab) {
            CreateTab()
                .tabItem { Label(T("Create"), systemImage: "waveform") }
                .tag(0)
            LibraryTab()
                .tabItem { Label(T("Library"), systemImage: "square.stack") }
                .tag(1)
            AccountTab()
                .tabItem { Label(T("Account"), systemImage: "person") }
                .tag(2)
        }
        .tint(Theme.black)
        .fullScreenCover(isPresented: Binding(get: { state.needsAIConsent }, set: { _ in })) {
            AIConsentView()
        }
    }
}

/// Asked once after sign in: what is sent to AI services, and who they are in
/// kind. Agree to go on, or sign out. The same facts are in the Privacy Policy.
struct AIConsentView: View {
    @EnvironmentObject private var state: AppState

    private let rows: [(String, String, String)] = [
        ("text.alignleft", "Your scripts and ideas",
         "sent to an AI writing service to write and improve scripts, and to plan your video."),
        ("waveform", "Your voice recordings",
         "used to make your cloned voice and to turn speech into text."),
        ("person.crop.square", "Your photo and voiceover",
         "sent to an AI video service to make your presenter, only if you add one."),
        ("film", "Your clips and video frames",
         "checked by an AI service so footage matches your words."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                LogoMark(size: 44)
                Text(T("How Kinbir uses AI")).screenTitle()
                    .accessibilityIdentifier("aiConsentHeading")
                Text(T("Kinbir makes your content with AI. Some of it runs on services from other companies that work for us. Here is what they receive:"))
                    .font(Theme.body).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(rows, id: \.1) { row in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: row.0)
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.black)
                                .frame(width: 36, height: 36)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lime))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(T(row.1)).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                                Text(T(row.2)).font(Theme.small).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .card(fill: Theme.grey)

                NoteText(text: T("They receive it only to make what you ask for. It is not sold and not used for advertising. You can delete your account and everything in it at any time."))
                Link(T("Privacy Policy"), destination: URL(string: "https://kinbir.com/privacy")!)
                    .font(Theme.smallMedium).foregroundStyle(Theme.black)
            }
            .page()
        }
        .background(Theme.white)
        .safeAreaInset(edge: .bottom) {
            BottomBar {
                VStack(spacing: 10) {
                    Button(T("I agree")) { state.giveAIConsent() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("aiConsentAgree")
                    Button(T("Not now, sign me out")) { state.signOut() }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("aiConsentDecline")
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

/// Shared by every tab so a route always opens the same screen.
struct RouteDestinations: ViewModifier {
    var onMakeAnother: (() -> Void)?

    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            switch route {
            case .job(let id):
                JobView(jobId: id, onMakeAnother: onMakeAnother)
            case .fix(let jobId):
                ScrollView { FixView(jobId: jobId).page() }.background(Theme.white)
            case .video(let jobId):
                VideoFlowView(jobId: jobId)
            case .videoJob(let id, let landscape):
                VideoJobScreen(videoJobId: id, shape: landscape ? .landscape : .portrait)
            case .voices:
                VoicesView()
            case .enroll:
                EnrollView()
            case .deleteAccount:
                DeleteAccountView()
            case .scriptRules:
                ScriptRulesView()
            case .buyCredits:
                BuyCreditsView()
            case .promo:
                PromoView()
            case .creditHistory:
                CreditHistoryView()
            }
        }
    }
}

struct CreateTab: View {
    @EnvironmentObject private var state: AppState
    @State private var path: [Route] = []
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack(path: $path) {
            CreateView(text: $text, path: $path)
                .modifier(RouteDestinations(onMakeAnother: {
                    text = ""
                    state.saveDraft("")
                    path.removeAll()
                }))
        }
        .onAppear {
            if !loaded {
                text = state.loadDraft()
                // What they typed on the welcome page is waiting for them.
                if text.isEmpty, let pending = PendingScript.take() { text = pending }
                loaded = true
            }
        }
    }
}

struct LibraryTab: View {
    @EnvironmentObject private var state: AppState
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView()
                .modifier(RouteDestinations(onMakeAnother: nil))
        }
        .onChange(of: state.pendingRoute) { _, route in
            guard let route else { return }
            path = [route]
            state.pendingRoute = nil
        }
    }
}

struct AccountTab: View {
    @EnvironmentObject private var state: AppState
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            AccountView()
                .modifier(RouteDestinations(onMakeAnother: nil))
        }
        .onChange(of: state.pendingAccountRoute) { _, route in
            guard let route else { return }
            path = [route]
            state.pendingAccountRoute = nil
        }
    }
}
