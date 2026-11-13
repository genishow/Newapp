import AVFoundation
import Foundation

/// Speak-to-write the way the website does it: the words appear in the box while you are
/// still talking. The microphone is sent to the server as it is heard (16 kHz, 16-bit,
/// one channel) over a socket, and the server answers with the text so far. When you
/// stop, it answers once more with the final text.
///
/// Everything heard is also kept, so if the socket is not available the whole take can
/// still be sent in one go and nothing you said is lost.
final class LiveDictation {
    /// The text so far. Called on the main thread.
    var onPartial: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var outFormat: AVAudioFormat?
    private var socket: URLSessionWebSocketTask?
    private let queue = DispatchQueue(label: "kinbir.dictation")
    // Only touched on `queue`.
    private var pcm = Data()
    private var socketAlive = false
    private var waiter: CheckedContinuation<String?, Never>?
    private var running = false

    /// Asks for the microphone if needed and starts listening. False when not allowed.
    func start(base: URL, accessCode: String) async -> Bool {
        if Launch.isMock { return true }   // the simulator has no microphone to rely on
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
            let input = engine.inputNode
            let inFormat = input.outputFormat(forBus: 0)
            guard inFormat.sampleRate > 0,
                  let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                             channels: 1, interleaved: true),
                  let made = AVAudioConverter(from: inFormat, to: target) else { return false }
            converter = made
            outFormat = target
            queue.sync { pcm = Data() }
            openSocket(base: base, accessCode: accessCode)
            input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
                self?.heard(buffer)
            }
            engine.prepare()
            try engine.start()
            running = true
            return true
        } catch {
            return false
        }
    }

    /// Stops listening. Gives the final text from the socket, or nil when the socket was
    /// not available: then `takeFile()` has the whole recording to send the other way.
    func stop() async -> String? {
        halt()
        let alive = queue.sync { socketAlive }
        guard alive else {
            socket?.cancel(with: .goingAway, reason: nil)
            return nil
        }
        let text: String? = await withCheckedContinuation { continuation in
            queue.async {
                self.waiter = continuation
                self.socket?.send(.string("stop")) { [weak self] error in
                    if error != nil { self?.finish(nil) }
                }
                // No final after 30 seconds: give up on the socket, as the website does.
                self.queue.asyncAfter(deadline: .now() + 30) { [weak self] in self?.finish(nil) }
            }
        }
        socket?.cancel(with: .normalClosure, reason: nil)
        return text
    }

    /// Throws the take away.
    func cancel() {
        halt()
        socket?.cancel(with: .goingAway, reason: nil)
        queue.async {
            self.socketAlive = false
            self.pcm = Data()
        }
        finish(nil)
    }

    /// Everything that was heard, as a wav file, for the one-request way of transcribing.
    func takeFile() -> URL? {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinbir-speech-" + UUID().uuidString)
            .appendingPathExtension("wav")
        if Launch.isMock {
            try? Data("speech".utf8).write(to: target)
            return target
        }
        let samples = queue.sync { pcm }
        guard samples.count > 16_000 else { return nil }   // under half a second: nothing to send
        do {
            try LiveDictation.wav(samples).write(to: target)
            return target
        } catch {
            return nil
        }
    }

    /// A minimal wav file around 16 kHz, 16-bit, one-channel samples.
    static func wav(_ samples: Data) -> Data {
        func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        var out = Data()
        out.append(Data("RIFF".utf8))
        out.append(le32(UInt32(36 + samples.count)))
        out.append(Data("WAVEfmt ".utf8))
        out.append(le32(16))
        out.append(le16(1))          // PCM
        out.append(le16(1))          // one channel
        out.append(le32(16_000))     // samples a second
        out.append(le32(32_000))     // bytes a second
        out.append(le16(2))          // bytes a sample
        out.append(le16(16))         // bits a sample
        out.append(Data("data".utf8))
        out.append(le32(UInt32(samples.count)))
        out.append(samples)
        return out
    }

    // MARK: inside

    private func halt() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    /// Runs on the audio thread: turn what was heard into 16 kHz samples and pass them on.
    private func heard(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let outFormat else { return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
        var fed = false
        var failure: NSError?
        converter.convert(to: out, error: &failure) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard failure == nil, out.frameLength > 0, let channel = out.int16ChannelData else { return }
        let data = Data(bytes: channel[0], count: Int(out.frameLength) * 2)
        queue.async {
            self.pcm.append(data)
            guard self.socketAlive else { return }
            self.socket?.send(.data(data)) { [weak self] error in
                if error != nil { self?.queue.async { self?.socketAlive = false } }
            }
        }
    }

    private func openSocket(base: URL, accessCode: String) {
        let address = base.absoluteString.replacingOccurrences(of: "http", with: "ws",
                                                               options: .anchored) + "/transcribe/stream"
        guard let url = URL(string: address),
              let hello = try? JSONSerialization.data(withJSONObject: ["access_code": accessCode]),
              let first = String(data: hello, encoding: .utf8) else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        // The credential goes as the first message, never in the address.
        task.send(.string(first)) { [weak self] error in
            self?.queue.async { self?.socketAlive = (error == nil) }
        }
        listen(task)
    }

    private func listen(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.queue.async { self.socketAlive = false }
                self.finish(nil)
            case .success(let message):
                if case .string(let raw) = message, let data = raw.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let partial = object["partial"] as? String, !partial.isEmpty {
                        DispatchQueue.main.async { self.onPartial?(partial) }
                    } else if let final = object["final"] as? String {
                        self.finish(final)
                        return
                    } else if object["error"] != nil {
                        self.queue.async { self.socketAlive = false }
                        self.finish(nil)
                        return
                    }
                }
                self.listen(task)
            }
        }
    }

    /// Answers whoever is waiting for the final text, once.
    private func finish(_ text: String?) {
        queue.async {
            guard let waiting = self.waiter else { return }
            self.waiter = nil
            waiting.resume(returning: text)
        }
    }
}
