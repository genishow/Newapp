import AVFoundation
import Foundation

/// Records the user speaking, to be turned into text by the server.
@MainActor
final class SpeechRecorder: ObservableObject {
    private var recorder: AVAudioRecorder?
    private var file: URL?

    /// Asks for the microphone if needed and starts recording. False when not allowed.
    func start() async -> Bool {
        let target = TempFiles.folder
            .appendingPathComponent("kinbir-speech-" + UUID().uuidString)
            .appendingPathExtension("m4a")
        file = target
        if Launch.isMock { return true }   // the simulator has no microphone to rely on

        guard await AVAudioApplication.requestRecordPermission() else { return false }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let made = try AVAudioRecorder(url: target, settings: settings)
            guard made.record(forDuration: 600) else { return false }
            recorder = made
            return true
        } catch {
            return false
        }
    }

    /// Stops and hands back the recording.
    func stop() -> URL? {
        if Launch.isMock, let file {
            try? Data("speech".utf8).write(to: file)
            return file
        }
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        return file
    }
}
