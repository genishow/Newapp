import Foundation
import Photos

/// Saves a finished video straight into the Photos app (D-449). Asks only for
/// "add" access, so Kinbir can put videos in but never sees the rest of the library.
enum PhotoSaver {
    enum Outcome: Equatable {
        case saved
        case notAllowed
        case failed
    }

    static func saveVideo(at url: URL) async -> Outcome {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .notAllowed }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                // keeps the file name ("Kinbir - first words.mp4") in Photos
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = url.lastPathComponent
                PHAssetCreationRequest.forAsset()
                    .addResource(with: .video, fileURL: url, options: options)
            }
            return .saved
        } catch {
            return .failed
        }
    }
}
