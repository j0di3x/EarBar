import XCTest
@testable import NothingProtocol

/// Bytes below are copied from captures in Tests/Fixtures/captured.
final class NoiseControlTests: XCTestCase {
    private func events(_ hex: String) throws -> [HeadsetEvent] {
        var handler = NothingEar3Protocol()
        return handler.decode(try hex.split(separator: " ").map { try XCTUnwrap(UInt8($0, radix: 16)) })
    }

    func testModelReply() throws {
        XCTAssertEqual(try events("55 60 01 1C 40 02 00 01 73 B1 14 DD"), [.model(NothingEar3Protocol.modelID)])
    }

    func testTransparencyPush() throws {
        XCTAssertEqual(try events("55 60 01 03 E0 03 00 00 01 07 00 EA 1F"), [.noiseControl(.transparency)])
    }

    func testNoiseCancellationPush() throws {
        XCTAssertEqual(try events("55 60 01 03 E0 03 00 00 01 01 00 E9 BF"), [.noiseControl(.noiseCancellation(.high))])
    }

    func testLowLatencyOffReply() throws {
        XCTAssertEqual(try events("55 60 01 41 40 01 00 05 02 52 F8"), [.lowLatency(false)])
    }

    func testDualConnectionOnReply() throws {
        XCTAssertEqual(try events("55 60 01 27 40 01 00 07 01 1A 5F"), [.dualConnection(true)])
    }

    func testLowLatencyOnReply() throws {
        XCTAssertEqual(try events("55 60 01 41 40 01 00 05 01 12 F9"), [.lowLatency(true)])
    }

    func testSpatialAudioReplies() throws {
        XCTAssertEqual(try events("55 60 01 4F 40 02 00 06 01 00 22 CD"), [.spatialAudio(true)])
        XCTAssertEqual(try events("55 60 01 4F 40 02 00 06 00 00 23 5D"), [.spatialAudio(false)])
    }

    /// Runs only where the local capture exists, since it holds addresses.
    func testCapturedDeviceListParses() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/captured/device-list.local.hex")
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { !$0.hasPrefix("#") }) else {
            throw XCTSkip("No local device list capture")
        }
        guard case .devices(let devices)? = try events(String(line)).first else {
            return XCTFail("Expected a device list")
        }
        XCTAssertFalse(devices.isEmpty)
        XCTAssertTrue(devices.allSatisfy { !$0.name.isEmpty && $0.address.count == 6 })
    }

    func testBatteryFrames() throws {
        XCTAssertEqual(try events("55 60 01 07 40 05 00 03 02 02 50 03 50 73 72"), [.battery([.left: 80, .right: 80])])
        XCTAssertEqual(try events("55 60 01 01 E0 07 00 00 03 02 50 03 50 04 32 DD 15"),
                       [.battery([.left: 80, .right: 80, .case: 50])])
        XCTAssertEqual(try events("55 60 01 01 E0 03 00 00 01 02 50 68 AA"), [.battery([.left: 80])])
    }

    func testNoiseControlReply() throws {
        XCTAssertEqual(try events("55 60 01 1E 40 06 00 04 01 07 00 02 01 00 9A EA"), [.noiseControl(.transparency)])
    }
}
