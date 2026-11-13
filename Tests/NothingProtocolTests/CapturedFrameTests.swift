import XCTest
@testable import NothingProtocol

/// Runs over packets captured from real headphones in Tests/Fixtures/captured.
/// Each `.hex` file holds one frame per line; `#` starts a comment. Fixtures
/// must come from a device, never be written by hand.
final class CapturedFrameTests: XCTestCase {
    private func capturedFrames() throws -> [[UInt8]] {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/captured")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "hex" }
        var frames: [[UInt8]] = []
        for file in files {
            for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
                let hex = line.prefix { $0 != "#" }.split(separator: " ")
                if !hex.isEmpty {
                    frames.append(try hex.map { try XCTUnwrap(UInt8($0, radix: 16)) })
                }
            }
        }
        try XCTSkipIf(frames.isEmpty, "No captured packets yet")
        return frames
    }

    func testCapturedFramesDecodeAndReencodeByteExact() throws {
        for bytes in try capturedFrames() {
            var decoder = FrameDecoder()
            let decoded = try XCTUnwrap(decoder.append(bytes).first)
            XCTAssertEqual(decoded.raw, bytes)
            XCTAssertNotEqual(decoded.crcValid, false)
            XCTAssertEqual(decoded.frame.encoded(), bytes)
        }
    }

    func testCapturedFramesSurviveSplitChunks() throws {
        let frames = try capturedFrames()
        var decoder = FrameDecoder()
        var output: [[UInt8]] = []
        for byte in frames.joined() {
            output += decoder.append([byte]).map(\.raw)
        }
        XCTAssertEqual(output, frames)
    }
}
