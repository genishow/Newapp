import SwiftUI

@main
struct KinbirApp: App {
    @StateObject private var state = AppState.make()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.light)
                .tint(Theme.black)
        }
    }
}
