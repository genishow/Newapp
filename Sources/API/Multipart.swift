import Foundation

/// Builds a multipart/form-data body. Used once, for the enrollment video.
struct Multipart {
    let boundary: String
    private(set) var body = Data()

    init(boundary: String = "kinbir-" + UUID().uuidString) {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append(value)
        append("\r\n")
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    /// Call once, after the last part.
    func finished() -> Data {
        var out = body
        out.append(Data("--\(boundary)--\r\n".utf8))
        return out
    }

    private mutating func append(_ s: String) {
        body.append(Data(s.utf8))
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "mov": return "video/quicktime"
        case "mp4", "m4v": return "video/mp4"
        case "webm": return "video/webm"
        case "mkv": return "video/x-matroska"
        default: return "application/octet-stream"
        }
    }
}
