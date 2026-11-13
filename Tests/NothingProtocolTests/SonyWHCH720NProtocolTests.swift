import XCTest
@testable import NothingProtocol

/// Every frame here was captured from a WH-CH720N, or sent by Spike and
/// answered by the headphones, on 2026-11-13 (see Tests/Fixtures/captured/sony).
final class SonyWHCH720NProtocolTests: XCTestCase {
    private func bytes(_ hex: String) throws -> [UInt8] {
        try hex.split(separator: " ").map { try XCTUnwrap(UInt8($0, radix: 16)) }
    }

    func testHandshakeSendsInitAndAcknowledgesTheReply() throws {
        var handler = SonyWHCH720NProtocol()
        XCTAssertEqual(handler.encode(.requestModel), try bytes("3E 0C 00 00 00 00 02 00 00 0E 3C"))

        XCTAssertEqual(handler.decode(try bytes("3E 01 01 00 00 00 00 02 3C")), [])
        XCTAssertEqual(handler.takeWrites(), [])

        XCTAssertEqual(handler.decode(try bytes("3E 0C 00 00 00 00 08 01 00 03 00 10 02 00 00 2A 3C")), [.ready])
        XCTAssertEqual(handler.takeWrites(), [try bytes("3E 01 01 00 00 00 00 02 3C")])
    }

    func testRequestsWaitForTheAcknowledgement() throws {
        var handler = SonyWHCH720NProtocol()
        XCTAssertEqual(handler.encode(.requestBattery), try bytes("3E 0C 00 00 00 00 02 22 00 30 3C"))
        XCTAssertEqual(handler.encode(.requestNoiseControl), [], "Must wait for the battery ACK")

        // The queued request goes out with the sequence number the ACK carries.
        _ = handler.decode(try bytes("3E 01 00 00 00 00 00 01 3C"))
        XCTAssertEqual(handler.takeWrites(), [try bytes("3E 0C 00 00 00 00 02 66 17 8B 3C")])
    }

    func testUnsupportedCommandsSendNothing() {
        var handler = SonyWHCH720NProtocol()
        XCTAssertEqual(handler.encode(.requestLowLatency), [])
        XCTAssertEqual(handler.encode(.setSpatialAudio(true)), [])
        XCTAssertEqual(handler.encode(.requestDevices(start: 0)), [])
    }

    func testBatteryReply() throws {
        var handler = SonyWHCH720NProtocol()
        XCTAssertEqual(handler.decode(try bytes("3E 0C 00 00 00 00 04 23 00 46 00 79 3C")), [.battery([.single: 70])])
        XCTAssertEqual(handler.takeWrites(), [try bytes("3E 01 01 00 00 00 00 02 3C")])
    }

    func testAmbientSoundFromButtonPresses() throws {
        var handler = SonyWHCH720NProtocol()
        let ambient = HeadsetEvent.ambientSound(level: 20, voiceFocus: false)
        XCTAssertEqual(handler.decode(try bytes("3E 0C 01 00 00 00 07 69 17 01 00 01 00 14 AA 3C")), [.noiseControl(.off), ambient])
        XCTAssertEqual(handler.decode(try bytes("3E 0C 00 00 00 00 07 69 17 01 01 00 00 14 A9 3C")),
                       [.noiseControl(.noiseCancellation(.high)), ambient])
        XCTAssertEqual(handler.decode(try bytes("3E 0C 01 00 00 00 07 69 17 01 01 01 00 14 AB 3C")), [.noiseControl(.transparency), ambient])
        XCTAssertEqual(handler.decode(try bytes("3E 0C 01 00 00 00 07 67 17 01 00 01 00 14 A8 3C")), [.noiseControl(.off), ambient])
    }
}
