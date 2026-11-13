import SwiftUI

/// Places a screen can lead to inside a tab.
enum Route: Hashable {
    case job(String)
    /// Make a video from this voiceover.
    case video(String)
    /// A video that is rendering or finished.
    case videoJob(String)
    case voices
    case enroll
    case deleteAccount
}

/// The signed-in app: Create, Library, Account.
struct HomeView: View {
    @EnvironmentObject private var state: AppState

    init() {
        let bar = UITabBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColor.white
        UITabBar.appearance().standardAppearance = bar
        UITabBar.appearance().scrollEdgeAppearance = bar
    }

    var body: some View {
        TabView {
            CreateTab()
                .tabItem { Label("Create", systemImage: "waveform") }
            LibraryTab()
                .tabItem { Label("Library", systemImage: "square.stack") }
            AccountTab()
                .tabItem { Label("Account", systemImage: "person") }
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
            case .video(let jobId):
                VideoFlowView(jobId: jobId)
            case .videoJob(let id):
                VideoJobScreen(videoJobId: id)
            case .voices:
                VoicesView()
            case .enroll:
                EnrollView()
            case .deleteAccount:
                DeleteAccountView()
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
