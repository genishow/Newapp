import AVFoundation
import Foundation

/// A small wrapper around AVAudioPlayer that SwiftUI can watch.
@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var isReady = false
    @Published var position: Double = 0
    @Published private(set) var duration: Double = 0
    /// Listening speed. 1 is normal.
    @Published private(set) var rate: Float = 1

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL) -> Bool {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // The simulator and odd audio routes can refuse; playback may still work.
        }
        guard let p = try? AVAudioPlayer(contentsOf: url) else {
            isReady = false
            return false
        }
        p.delegate = self
        p.enableRate = true
        p.rate = rate
        p.prepareToPlay()
        player = p
        duration = p.duration
        position = 0
        isReady = true
        return true
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func setRate(_ value: Float) {
        rate = value
        player?.rate = value
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        player.currentTime = min(max(0, seconds), player.duration)
        position = player.currentTime
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        isReady = false
        position = 0
        duration = 0
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.position = player.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.position = 0
            self.player?.currentTime = 0
            self.stopTimer()
        }
    }
}
