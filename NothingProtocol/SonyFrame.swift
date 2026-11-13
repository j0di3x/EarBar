import Foundation

/// One Sony headphones message, from the Gadgetbridge protocol description.
/// UNVERIFIED on WH-CH720N until captured frames confirm the layout.
///
/// Wire format: `3E | escaped(type, seq, length BE32, payload, sum8) | 3C`.
/// The checksum is the byte sum of type through payload.
public struct SonyFrame: Equatable, Sendable {
    public static let ack: UInt8 = 0x01
    public static let command1: UInt8 = 0x0C
    public static let command2: UInt8 = 0x0E

    static let header: UInt8 = 0x3E
    static let trailer: UInt8 = 0x3C
    static let escape: UInt8 = 0x3D
    static let escapeMask: UInt8 = 0xEF

    public var type: UInt8
    public var sequence: UInt8
    public var payload: [UInt8]

    public init(type: UInt8, sequence: UInt8, payload: [UInt8] = []) {
        self.type = type
        self.sequence = sequence
        self.payload = payload
    }

    /// The reply the headphones expect for every command they send.
    public static func acknowledging(sequence: UInt8) -> SonyFrame {
        SonyFrame(type: ack, sequence: 1 &- sequence)
    }

    public func encoded() -> [UInt8] {
        let length = UInt32(payload.count)
        var body: [UInt8] = [type, sequence,
                             UInt8(length >> 24), UInt8(length >> 16 & 0xFF),
                             UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)]
        body += payload
        body.append(Self.checksum(body))

        var bytes = [Self.header]
        for byte in body {
            if byte == Self.header || byte == Self.trailer || byte == Self.escape {
                bytes += [Self.escape, byte & Self.escapeMask]
            } else {
                bytes.append(byte)
            }
        }
        bytes.append(Self.trailer)
        return bytes
    }

    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(0, &+)
    }
}

public struct DecodedSonyFrame: Equatable, Sendable {
    public let frame: SonyFrame
    public let checksumValid: Bool
}

/// Splits a byte stream into Sony frames. Drops bytes outside `3E ... 3C`
/// and frames whose length field does not match.
public struct SonyFrameDecoder: Sendable {
    private var body: [UInt8]?
    private var escaping = false

    public init() {}

    public mutating func append(_ bytes: [UInt8]) -> [DecodedSonyFrame] {
        var frames: [DecodedSonyFrame] = []
        for byte in bytes {
            if byte == SonyFrame.header {
                body = []
                escaping = false
            } else if byte == SonyFrame.trailer {
                if let body, let frame = Self.decode(body) {
                    frames.append(frame)
                }
                body = nil
            } else if body != nil {
                if escaping {
                    body?.append(byte | ~SonyFrame.escapeMask)
                    escaping = false
                } else if byte == SonyFrame.escape {
                    escaping = true
                } else {
                    body?.append(byte)
                }
            }
        }
        return frames
    }

    private static func decode(_ body: [UInt8]) -> DecodedSonyFrame? {
        guard body.count >= 7 else { return nil }
        let length = body[2...5].reduce(0) { $0 << 8 | Int($1) }
        guard body.count == 7 + length else { return nil }
        let payload = Array(body[6..<(6 + length)])
        let frame = SonyFrame(type: body[0], sequence: body[1], payload: payload)
        return DecodedSonyFrame(frame: frame, checksumValid: SonyFrame.checksum(Array(body.dropLast())) == body.last)
    }
}
