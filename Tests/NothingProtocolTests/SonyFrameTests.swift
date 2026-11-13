import XCTest
@testable import NothingProtocol

/// Runs over packets captured from a Sony WH-CH720N in Tests/Fixtures/captured/sony.
final class SonyFrameTests: XCTestCase {
    private func capturedFrames() throws -> [[UInt8]] {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/captured/sony")
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
        try XCTSkipIf(frames.isEmpty, "No captured Sony packets yet")
        return frames
    }

    func testCapturedFramesDecodeAndReencodeByteExact() throws {
        for bytes in try capturedFrames() {
            var decoder = SonyFrameDecoder()
            let decoded = try XCTUnwrap(decoder.append(bytes).first, "\(bytes)")
            XCTAssertTrue(decoded.checksumValid, "\(bytes)")
            XCTAssertEqual(decoded.frame.encoded(), bytes)
        }
    }

    func testCapturedFramesSurviveSplitChunks() throws {
        let frames = try capturedFrames()
        var decoder = SonyFrameDecoder()
        var decoded: [SonyFrame] = []
        for byte in frames.joined() {
            decoded += decoder.append([byte]).map(\.frame)
        }
        XCTAssertEqual(decoded.map { $0.encoded() }, frames)
    }

    func testAcknowledgementMatchesCapturedAcks() throws {
        // The headphones answered our seq 0 with seq 1 and our seq 1 with seq 0.
        XCTAssertEqual(SonyFrame.acknowledging(sequence: 0).encoded(), [0x3E, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x02, 0x3C])
        XCTAssertEqual(SonyFrame.acknowledging(sequence: 1).encoded(), [0x3E, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x3C])
    }
}
