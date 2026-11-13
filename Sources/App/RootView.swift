import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            switch state.phase {
            case .loading:
                VStack(spacing: 16) {
                    LogoMark(size: 64)
                    ProgressView().tint(Theme.black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.white)
            case .signedOut:
                WelcomeView()
            case .signedIn:
                HomeView()
            }
        }
        .task { await state.start() }
    }
}

/// Lets one call site pick between two button styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
