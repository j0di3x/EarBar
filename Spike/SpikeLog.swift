import Foundation

extension Sequence where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

/// Writes timestamped lines to stdout and to a file in ~/Library/Logs/EarBarSpike.
final class SpikeLog {
    let path: String
    private let handle: FileHandle?
    private let formatter = ISO8601DateFormatter()

    init() {
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/EarBarSpike", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("capture-\(name).log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        path = url.path
        handle = try? FileHandle(forWritingTo: url)
    }

    func note(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        print(line, terminator: "")
        handle?.write(Data(line.utf8))
    }

    func packet(_ label: String, _ bytes: [UInt8]) {
        note("\(label) [\(bytes.count)] \(bytes.hexString)")
    }
}
