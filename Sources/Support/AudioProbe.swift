import AVFoundation

/// Reads a downloaded reading so SpeechCheck can tell a word from breathing.
enum AudioProbe {
    /// True when the file sounds like a spoken word. True too when the file cannot be
    /// read, so a reading is never hidden because of the check itself.
    static func soundsLikeSpeech(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(min(file.length, 24_000 * 20))),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0]
        else { return true }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        return SpeechCheck.isSpeech(samples, sampleRate: file.processingFormat.sampleRate)
    }
}
