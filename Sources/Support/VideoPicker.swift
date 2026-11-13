import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Records a short video with the front camera.
struct VideoRecorder: UIViewControllerRepresentable {
    let onFinish: (URL?) -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        if UIImagePickerController.isCameraDeviceAvailable(.front) {
            picker.cameraDevice = .front
        }
        picker.videoMaximumDuration = EnrollRules.maxSeconds
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (URL?) -> Void
        init(onFinish: @escaping (URL?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let url = info[.mediaURL] as? URL
            onFinish(url.flatMap { VideoFiles.copyToTemp($0) })
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

/// Chooses an existing video from the photo library. Needs no permission prompt.
struct VideoLibraryPicker: UIViewControllerRepresentable {
    let onFinish: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onFinish: (URL?) -> Void
        init(onFinish: @escaping (URL?) -> Void) { self.onFinish = onFinish }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                onFinish(nil)
                return
            }
            let finish = onFinish
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                // The file only exists inside this callback, so copy it now.
                let copy = url.flatMap { VideoFiles.copyToTemp($0) }
                DispatchQueue.main.async { finish(copy) }
            }
        }
    }
}

enum VideoFiles {
    static func copyToTemp(_ source: URL) -> URL? {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinbir-enroll-" + UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try FileManager.default.copyItem(at: source, to: target)
            return target
        } catch {
            return nil
        }
    }

    static func seconds(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let s = CMTimeGetSeconds(duration)
        return s.isFinite ? s : 0
    }

    static func bytes(of url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }
}

/// Chooses several of the user's own videos or photos to use as footage.
struct ClipPicker: UIViewControllerRepresentable {
    let onFinish: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.videos, .images])
        config.selectionLimit = 10
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onFinish: ([URL]) -> Void
        init(onFinish: @escaping ([URL]) -> Void) { self.onFinish = onFinish }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let finish = onFinish
            guard !results.isEmpty else {
                finish([])
                return
            }
            let group = DispatchGroup()
            let lock = NSLock()
            var files: [URL] = []
            for result in results {
                let provider = result.itemProvider
                let type = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                    ? UTType.movie.identifier : UTType.image.identifier
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                    // The file only exists inside this callback, so copy it now.
                    if let url, let copy = VideoFiles.copyToTemp(url) {
                        lock.lock()
                        files.append(copy)
                        lock.unlock()
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) { finish(files) }
        }
    }
}
