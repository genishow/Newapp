import Foundation

/// Sends one upload in a way that survives leaving the app (Geni, 2026-11-17:
/// "let them leave"). Voice cloning takes about a minute on the server, and an
/// ordinary request dies when the app is put away; this one is handed to iOS,
/// which finishes it and wakes the app with the answer.
final class BackgroundUploader: NSObject, URLSessionDataDelegate {
    static let shared = BackgroundUploader()
    static let sessionId = "com.geni.kinbir.upload"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionId)
        config.isDiscretionary = false          // now, not "when convenient"
        config.sessionSendsLaunchEvents = true
        // The server answers only when the voice is made, so a quiet minute is normal.
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 900
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private let lock = NSLock()
    private var buffers: [Int: Data] = [:]
    private var waiters: [Int: CheckedContinuation<(Data, Int), Error>] = [:]

    /// iOS's "I am done delivering events" callback, kept until they are delivered.
    var systemCompletion: (() -> Void)?
    /// An upload that finished after the app had been closed completely: nobody is
    /// waiting for it any more, so the app is only told how it ended.
    var onFinishedUnattended: ((_ status: Int) -> Void)?

    /// Connects to uploads started before the app was closed, so their end is heard.
    func wake() { _ = session }

    /// A place for the request body that is not emptied when the app starts.
    static func bodyFile() -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kinbir-upload", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(UUID().uuidString).appendingPathExtension("body")
    }

    /// Uploads the file and gives back the server's answer and its status.
    func upload(_ request: URLRequest, bodyFile: URL) async throws -> (Data, Int) {
        let task = session.uploadTask(with: request, fromFile: bodyFile)
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            waiters[task.taskIdentifier] = continuation
            lock.unlock()
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffers[dataTask.taskIdentifier, default: Data()].append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let data = buffers.removeValue(forKey: task.taskIdentifier) ?? Data()
        let waiter = waiters.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        if let waiter {
            if let error { waiter.resume(throwing: error) } else { waiter.resume(returning: (data, status)) }
        } else {
            onFinishedUnattended?(error == nil ? status : 0)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.systemCompletion?()
            self.systemCompletion = nil
        }
    }
}
