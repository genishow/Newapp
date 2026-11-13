import Foundation

/// Downloaded audio lives in one temporary folder that is emptied at launch.
enum TempFiles {
    static var folder: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kinbir-audio",
                                                                                 isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(name: String, ext: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        return folder.appendingPathComponent(safe).appendingPathExtension(ext)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: folder)
    }
}
