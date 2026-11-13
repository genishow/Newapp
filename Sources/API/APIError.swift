import Foundation

/// One error type for everything the server or the network can say.
struct APIError: Error, Equatable, LocalizedError {
    enum Kind: Equatable {
        case sessionExpired   // the stored access code is no longer valid
        case needsCredits     // 402
        case server           // 5xx
        case network          // no connection, timeout
        case other            // a 4xx with a sentence worth showing
    }

    let kind: Kind
    let status: Int
    let message: String

    var errorDescription: String? { message }

    static let network = APIError(
        kind: .network, status: 0,
        message: "No connection. Check your internet and try again.")

    static let buyingNote = "Buying credits in the app is coming soon."

    /// Turns an HTTP failure into the sentence the user reads.
    /// `path` is the request path; `/auth/` answers keep their own 401 sentences
    /// ("that code is not right - 4 tries left"), which are the useful ones.
    static func from(status: Int, data: Data, path: String) -> APIError {
        let detail = serverSentence(in: data)

        if status == 401 && !path.hasPrefix("/auth/") {
            return APIError(kind: .sessionExpired, status: status,
                            message: "Your session is not valid any more. Sign in again.")
        }
        if status == 402 {
            let base = detail ?? "You do not have enough credits for this."
            return APIError(kind: .needsCredits, status: status,
                            message: base + " " + buyingNote)
        }
        if status >= 500 {
            if let detail, isUseful(detail) {
                return APIError(kind: .server, status: status, message: detail)
            }
            return APIError(kind: .server, status: status,
                            message: "Something went wrong on our side. Try again in a moment.")
        }
        return APIError(kind: .other, status: status,
                        message: detail.map(sentenceCase) ?? "That did not work. Try again.")
    }

    /// `{"detail": "sentence"}` or `{"detail": {"message": "sentence"}}`.
    static func serverSentence(in data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let s = obj["detail"] as? String, !s.isEmpty { return s }
        if let d = obj["detail"] as? [String: Any], let s = d["message"] as? String, !s.isEmpty {
            return s
        }
        return nil
    }

    private static func isUseful(_ s: String) -> Bool {
        let lower = s.lowercased()
        return !lower.contains("internal server error") && !lower.hasPrefix("request failed")
    }

    /// The server writes sentences in lower case ("that code is not right").
    static func sentenceCase(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    static func wrap(_ error: Error) -> APIError {
        if let e = error as? APIError { return e }
        if error is CancellationError {
            return APIError(kind: .other, status: 0, message: "Cancelled.")
        }
        if (error as NSError).domain == NSURLErrorDomain { return .network }
        if error is DecodingError {
            return APIError(kind: .server, status: 0,
                            message: "Kinbir sent an answer the app did not understand. Try again.")
        }
        return APIError(kind: .other, status: 0, message: error.localizedDescription)
    }
}
