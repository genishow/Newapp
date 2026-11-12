import Foundation

/// The script writer answers as server-sent events, one JSON object per `data:` line:
///   data: {"type":"delta","text":"..."}
///   data: {"type":"done","amharic":"...", ...}
///   data: {"type":"error","error":"..."}
enum SSEEvent: Equatable {
    case delta(String)
    case done(RewriteResult)
    case error(String)
}

enum SSEParser {
    private struct Envelope: Decodable {
        let type: String
        let text: String?
        let error: String?
    }

    /// Parses one line of the stream. Lines that are not a complete event return nil.
    static func parse(line: String) -> SSEEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let env = try? JSON.decoder.decode(Envelope.self, from: data) else { return nil }
        switch env.type {
        case "delta":
            guard let text = env.text else { return nil }
            return .delta(text)
        case "done":
            guard let result = try? JSON.decoder.decode(RewriteResult.self, from: data) else {
                return nil
            }
            return .done(result)
        case "error":
            return .error(env.error ?? "The script could not be written. Try again.")
        default:
            return nil
        }
    }
}
