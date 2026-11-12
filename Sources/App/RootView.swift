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
