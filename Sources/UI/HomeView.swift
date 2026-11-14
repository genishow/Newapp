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
        TabView {
            CreateTab()
                .tabItem { Label(T("Create"), systemImage: "waveform") }
            LibraryTab()
                .tabItem { Label(T("Library"), systemImage: "square.stack") }
            AccountTab()
                .tabItem { Label(T("Account"), systemImage: "person") }
        }
        .tint(Theme.black)
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
                loaded = true
            }
        }
    }
}

struct LibraryTab: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView()
                .modifier(RouteDestinations(onMakeAnother: nil))
        }
    }
}

struct AccountTab: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            AccountView()
                .modifier(RouteDestinations(onMakeAnother: nil))
        }
    }
}
