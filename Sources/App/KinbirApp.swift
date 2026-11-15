import SwiftUI

@main
struct KinbirApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = {
        if !Launch.isMock { RequestBuilder.deviceId = { DeviceID.value } }
        return AppState.make()
    }()
    @StateObject private var store = Store()
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
                .environmentObject(store)
                .preferredColorScheme(scheme)
                .tint(Theme.black)
                .task {
                    Notifications.state = state
                    // finishes App Store purchases left half done by a dropped connection
                    store.start(state: state)
                    await Notifications.refreshRegistration()
                }
        }
    }
}
