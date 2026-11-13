import Foundation

/// Sony WH-CH720N, Sony protocol V2. Payload codes from Gadgetbridge, checked
/// against captures from the owner's headphones (firmware 1.1.4) where noted.
///
/// The headphones take one command at a time: each must be acknowledged
/// before the next is sent, and every command they send needs an ACK back.
public struct SonyWHCH720NProtocol: HeadsetProtocol {
    private enum Payload {
        // Captured on WH-CH720N.
        static let initRequest: [UInt8] = [0x00, 0x00]
        static let initReply: UInt8 = 0x01
        static let batteryRequest: [UInt8] = [0x22, 0x00]
        static let batteryReply: UInt8 = 0x23
        // UNVERIFIED on hardware: never seen from WH-CH720N.
        static let batteryNotify: UInt8 = 0x25
        static let ambientRequest: UInt8 = 0x66
        static let ambientReply: UInt8 = 0x67
        // Confirmed by the owner on WH-CH720N: mode, ambient level and voice focus.
        static let ambientSet: UInt8 = 0x68
        static let ambientNotify: UInt8 = 0x69
        /// Gadgetbridge uses 0x15; the WH-CH720N answers only 0x17.
        static let ambientKind: UInt8 = 0x17
        static let singleBattery: UInt8 = 0x00
    }

    /// The V2 handshake reply has 8 bytes; V1 has 4 and is not supported.
    private static let initReplyLength = 8
    /// A command still unacknowledged after this long is taken as lost.
    private static let ackTimeout: TimeInterval = 3

    private var decoder = SonyFrameDecoder()
    private var sequence: UInt8 = 0
    private var queue: [[UInt8]] = []
    private var sentAt: Date?
    private var writes: [[UInt8]] = []

    // Last reported ambient sound state, so a change to one field keeps the others.
    private var enabled: UInt8 = 0x01
    private var ambient: UInt8 = 0x00
    private var voiceFocus: UInt8 = 0x00
    private var level: UInt8 = 20

    public init() {}

    public mutating func encode(_ command: HeadsetCommand) -> [UInt8] {
        guard let payload = payload(for: command) else { return [] }
        queue.append(payload)
        if let sentAt, Date().timeIntervalSince(sentAt) > Self.ackTimeout {
            self.sentAt = nil
        }
        return nextCommand() ?? []
    }

    public mutating func decode(_ bytes: [UInt8]) -> [HeadsetEvent] {
        var events: [HeadsetEvent] = []
        for decoded in decoder.append(bytes) where decoded.checksumValid {
            let frame = decoded.frame
            if frame.type == SonyFrame.ack {
                sequence = frame.sequence
                sentAt = nil
                if let next = nextCommand() {
                    writes.append(next)
                }
            } else {
                writes.append(SonyFrame.acknowledging(sequence: frame.sequence).encoded())
                events += event(from: frame.payload)
            }
        }
        return events
    }

    public mutating func takeWrites() -> [[UInt8]] {
        defer { writes = [] }
        return writes
    }

    private mutating func nextCommand() -> [UInt8]? {
        guard sentAt == nil, !queue.isEmpty else { return nil }
        sentAt = Date()
        return SonyFrame(type: SonyFrame.command1, sequence: sequence, payload: queue.removeFirst()).encoded()
    }

    private func payload(for command: HeadsetCommand) -> [UInt8]? {
        switch command {
        case .requestModel:
            return Payload.initRequest
        case .requestBattery:
            return Payload.batteryRequest
        case .requestNoiseControl:
            return [Payload.ambientRequest, Payload.ambientKind]
        case .setNoiseControl(let mode):
            switch mode {
            case .off: return ambientSet(enabled: 0x00, ambient: ambient, voiceFocus: voiceFocus, level: level)
            case .transparency: return ambientSet(enabled: 0x01, ambient: 0x01, voiceFocus: voiceFocus, level: level)
            case .noiseCancellation: return ambientSet(enabled: 0x01, ambient: 0x00, voiceFocus: voiceFocus, level: level)
            }
        case .setAmbientSound(let newLevel, let newVoiceFocus):
            return ambientSet(enabled: enabled, ambient: ambient,
                              voiceFocus: newVoiceFocus ? 0x01 : 0x00, level: UInt8(clamping: newLevel))
        case .requestLowLatency, .setLowLatency, .requestDualConnection, .setDualConnection,
             .requestDevices, .requestSpatialAudio, .setSpatialAudio:
            return nil
        }
    }

    private func ambientSet(enabled: UInt8, ambient: UInt8, voiceFocus: UInt8, level: UInt8) -> [UInt8] {
        // Gadgetbridge notes the third byte may be 00 while a slider is dragged.
        [Payload.ambientSet, Payload.ambientKind, 0x01, enabled, ambient, voiceFocus, level]
    }

    private mutating func event(from payload: [UInt8]) -> [HeadsetEvent] {
        guard let code = payload.first else { return [] }
        switch code {
        case Payload.initReply where payload.count == Self.initReplyLength:
            return [.ready]
        case Payload.batteryReply, Payload.batteryNotify:
            // Captured: 23 00 46 00 = single battery, 70 %, not charging.
            guard payload.count >= 3, payload[1] == Payload.singleBattery else { return [] }
            return [.battery([.single: Int(payload[2])])]
        case Payload.ambientReply, Payload.ambientNotify:
            // Captured: 17 01 <enabled> <ambient> <voice focus> <level>.
            guard payload.count >= 7, payload[1] == Payload.ambientKind else { return [] }
            enabled = payload[3]
            ambient = payload[4]
            voiceFocus = payload[5]
            level = payload[6]
            let mode: NoiseMode = enabled == 0x00 ? .off
                : ambient == 0x01 ? .transparency : .noiseCancellation(.high)
            return [.noiseControl(mode), .ambientSound(level: Int(level), voiceFocus: voiceFocus == 0x01)]
        default:
            return []
        }
    }
}
