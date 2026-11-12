import SwiftUI
import UIKit

/// The iOS share sheet: Save to Files, AirDrop, messages and so on.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file URL that can drive `.sheet(item:)`.
struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
