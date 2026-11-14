import SwiftUI

@main
struct KinbirApp: App {
    @StateObject private var state = AppState.make()
    /// "system", "light" or "dark", chosen on the Account page.
    @AppStorage("kinbir.appearance") private var appearance = "system"

    private var scheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(scheme)
                .tint(Theme.black)
        }
    }
}
