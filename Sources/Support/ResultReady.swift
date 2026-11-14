import Foundation
import StoreKit
import UIKit

/// What happens once a voiceover or video is ready to play (D-449): notification
/// permission is asked the first time, a reminder is set for 3 hours before the server
/// deletes it, and after the third result a rating is asked for (Apple shows it at most
/// three times a year, and only when it chooses to).
@MainActor
enum ResultReady {
    private static let seenKey = "kinbir.resultsSeen"
    private static let reviewKey = "kinbir.reviewAsked"

    static func handle(id: String, isVideo: Bool, finishedAt: String?) {
        guard !Launch.isMock else { return }
        var seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        let isNew = seen.insert(id).inserted
        if isNew {
            UserDefaults.standard.set(Array(seen.suffix(200)), forKey: seenKey)
        }
        Task {
            await Notifications.askOnce()
            await Notifications.remindBeforeDelete(id: id, isVideo: isVideo, finishedAt: finishedAt)
        }
        if isNew, seen.count >= 3, !UserDefaults.standard.bool(forKey: reviewKey) {
            UserDefaults.standard.set(true, forKey: reviewKey)
            Task {
                // a moment after the result shows, not on top of it
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if let scene = UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                    AppStore.requestReview(in: scene)
                }
            }
        }
    }
}
