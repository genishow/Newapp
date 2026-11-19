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
        // Kinbir's own Start and Done buttons, so recording can begin BEFORE the
        // reading does. People pressed record and spoke at once, and the camera
        // missed their first words (Geni, 2026-11-19: "the first 3 words are cut
        // off"). Now: Start begins recording, 3-2-1 counts on screen, then "Read now".
        picker.showsCameraControls = false
        let screen = UIScreen.main.bounds
        // Without its own controls the camera picture sits at the top; fill the screen.
        let pictureHeight = screen.width * 4 / 3
        if pictureHeight > 0, screen.height > pictureHeight {
            let scale = screen.height / pictureHeight
            picker.cameraViewTransform = CGAffineTransform(translationX: 0, y: (screen.height - pictureHeight) / 2)
                .scaledBy(x: scale, y: scale)
        }
        picker.cameraOverlayView = context.coordinator.controls(for: picker, script: script, in: screen)
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

        private weak var picker: UIImagePickerController?
        private let status = UILabel()
        private let startButton = UIButton(type: .system)
        private let doneButton = UIButton(type: .system)
        private let cancelButton = UIButton(type: .system)
        private var recording = false

        /// The words, a status line and Kinbir's own buttons, laid over the camera.
        func controls(for picker: UIImagePickerController, script: String, in bounds: CGRect) -> UIView {
            self.picker = picker
            let root = UIView(frame: bounds)
            root.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            if !script.isEmpty {
                root.addSubview(VideoRecorder.prompter(for: script, in: bounds))
            }
            let ink = UIColor(red: 0x19 / 255, green: 0x1A / 255, blue: 0x23 / 255, alpha: 1)
            let lime = UIColor(red: 0xB9 / 255, green: 0xFF / 255, blue: 0x66 / 255, alpha: 1)

            status.frame = CGRect(x: 12, y: 372, width: bounds.width - 24, height: 64)
            status.autoresizingMask = [.flexibleWidth]
            status.textAlignment = .center
            status.numberOfLines = 2
            status.font = .systemFont(ofSize: 22, weight: .bold)
            status.textColor = ink
            status.backgroundColor = lime
            status.layer.cornerRadius = 14
            status.layer.masksToBounds = true
            status.adjustsFontSizeToFitWidth = true
            status.minimumScaleFactor = 0.6
            status.text = T("Tap Start, wait for 3, 2, 1, then read")
            root.addSubview(status)

            func style(_ button: UIButton, _ title: String, fill: UIColor, text: UIColor) {
                button.setTitle(title, for: .normal)
                button.setTitleColor(text, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
                button.backgroundColor = fill
                button.layer.cornerRadius = 14
            }
            let bottom = bounds.height - 120
            style(startButton, T("Start"), fill: lime, text: ink)
            startButton.frame = CGRect(x: 24, y: bottom, width: bounds.width - 48, height: 60)
            startButton.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
            startButton.accessibilityIdentifier = "recorderStart"
            startButton.addTarget(self, action: #selector(start), for: .touchUpInside)
            root.addSubview(startButton)

            style(doneButton, T("Done reading"), fill: .white, text: ink)
            doneButton.frame = startButton.frame
            doneButton.autoresizingMask = startButton.autoresizingMask
            doneButton.isHidden = true
            doneButton.accessibilityIdentifier = "recorderDone"
            doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)
            root.addSubview(doneButton)

            style(cancelButton, T("Cancel"), fill: UIColor(white: 0, alpha: 0.5), text: .white)
            cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            cancelButton.frame = CGRect(x: 12, y: 56, width: 96, height: 44)
            cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
            root.addSubview(cancelButton)
            return root
        }

        @objc private func start() {
            guard !recording, let picker else { return }
            // Recording starts now; the count gives the camera time before any word.
            guard picker.startVideoCapture() else {
                status.text = T("The camera is not ready yet. Tap Start again.")
                return
            }
            recording = true
            startButton.isHidden = true
            cancelButton.isHidden = true
            count(3)
        }

        private func count(_ n: Int) {
            guard recording else { return }
            if n == 0 {
                status.text = T("Read now")
                doneButton.isHidden = false
                return
            }
            status.text = "\(n)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.count(n - 1) }
        }

        @objc private func done() {
            guard recording else { return }
            doneButton.isEnabled = false
            // A short tail, so the last word is not cut either.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.picker?.stopVideoCapture()
            }
        }

        @objc private func cancel() {
            guard !recording else { return }
            onFinish(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            recording = false
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
