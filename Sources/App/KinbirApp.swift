import SwiftUI

@main
struct KinbirApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = {
        if !Launch.isMock { RequestBuilder.deviceId = { DeviceID.value } }
        return AppState.make()
    }()
    @StateObject private var store = Store()
    /// "light" or "dark", from the header button or the Account page.
    /// Anything else (the old "system") shows light.
    @AppStorage("kinbir.appearance") private var appearance = "light"

    private var scheme: ColorScheme? { appearance == "dark" ? .dark : .light }

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
                .onChange(of: state.phase) { _, phase in
                    // a purchase made before signing in is reported now, not next launch
                    if phase == .signedIn { Task { await store.resendUnfinished() } }
                }
        }
    }
}
