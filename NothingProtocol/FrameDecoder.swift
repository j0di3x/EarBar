import Foundation

/// A frame read from the stream, with the result of its CRC check.
public struct DecodedFrame: Equatable, Sendable {
    public var frame: Frame
    public var raw: [UInt8]
    /// `nil` when the frame carries no CRC.
    public var crcValid: Bool?
}

/// Splits an RFCOMM byte stream into frames. RFCOMM chunks need not line up
/// with frame boundaries, so bytes are buffered between calls.
public struct FrameDecoder: Sendable {
    /// Larger lengths are treated as a false start, so bad data cannot stall the stream.
    public static let maxPayloadLength = 1024

    private var buffer: [UInt8] = []

    public init() {}

    public mutating func append<S: Sequence>(_ bytes: S) -> [DecodedFrame] where S.Element == UInt8 {
        buffer += bytes
        var frames: [DecodedFrame] = []
        while let frame = nextFrame() {
            frames.append(frame)
        }
        return frames
    }

    private mutating func nextFrame() -> DecodedFrame? {
        while true {
            guard let start = buffer.firstIndex(of: Frame.magic) else {
                buffer.removeAll()
                return nil
            }
            buffer.removeFirst(start)
            guard buffer.count >= Frame.headerLength else { return nil }

            let control = UInt16(buffer[1]) | UInt16(buffer[2]) << 8
            let type = UInt16(buffer[3]) | UInt16(buffer[4]) << 8
            let length = Int(buffer[5]) | Int(buffer[6]) << 8
            guard length <= FrameDecoder.maxPayloadLength else {
                buffer.removeFirst()
                continue
            }

            let hasCRC = control & Frame.crcFlag != 0
            let bodyEnd = Frame.headerLength + length
            let total = bodyEnd + (hasCRC ? Frame.crcLength : 0)
            guard buffer.count >= total else { return nil }

            let raw = Array(buffer[..<total])
            buffer.removeFirst(total)

            var crcValid: Bool?
            if hasCRC {
                let received = UInt16(raw[bodyEnd]) | UInt16(raw[bodyEnd + 1]) << 8
                crcValid = received == FrameCRC.checksum(raw[..<bodyEnd])
            }
            let frame = Frame(control: control, type: type, sequence: raw[7],
                              payload: Array(raw[Frame.headerLength..<bodyEnd]))
            return DecodedFrame(frame: frame, raw: raw, crcValid: crcValid)
        }
    }
}
