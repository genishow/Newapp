import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Records a short video with the front camera.
struct VideoRecorder: UIViewControllerRepresentable {
    /// The words to read, shown over the camera so nobody has to memorise them.
    var script: String = ""
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
        if !script.isEmpty {
            picker.cameraOverlayView = VideoRecorder.prompter(for: script, in: picker.view.bounds)
        }
        return picker
    }

    /// A panel across the upper part of the camera with the script on it. It ignores
    /// touches, so the camera's own buttons keep working.
    static func prompter(for script: String, in bounds: CGRect) -> UIView {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let panel = UIView(frame: CGRect(x: 12, y: 110, width: width - 24, height: 250))
        panel.backgroundColor = UIColor(red: 0x19 / 255, green: 0x1A / 255, blue: 0x23 / 255, alpha: 0.72)
        panel.layer.cornerRadius = 20
        panel.isUserInteractionEnabled = false
        panel.autoresizingMask = [.flexibleWidth]

        let label = UILabel(frame: panel.bounds.insetBy(dx: 16, dy: 12))
        label.text = script
        label.numberOfLines = 0
        label.textColor = .white
        label.font = .systemFont(ofSize: 20, weight: .medium)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        panel.addSubview(label)
        return panel
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
        let target = TempFiles.folder
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
    /// How many can be picked at once. One for a single shot.
    var limit = 10
    let onFinish: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.videos, .images])
        config.selectionLimit = limit
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
