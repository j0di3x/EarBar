import Foundation

/// One Nothing RFCOMM frame.
///
/// Layout, little endian, taken from community documentation:
/// `55 | control(2) | type(2) | length(2) | sequence | payload | crc(2)`
///
/// UNVERIFIED on hardware for Nothing Ear (3).
public struct Frame: Equatable, Sendable {
    public static let magic: UInt8 = 0x55
    public static let headerLength = 8
    public static let crcLength = 2
    /// Control value the community projects use for host requests.
    public static let requestControl: UInt16 = 0x0160
    /// Bit in `control` that says a CRC follows the payload.
    public static let crcFlag: UInt16 = 0x0020

    public var control: UInt16
    public var type: UInt16
    public var sequence: UInt8
    public var payload: [UInt8]

    public init(control: UInt16 = Frame.requestControl, type: UInt16, sequence: UInt8, payload: [UInt8] = []) {
        self.control = control
        self.type = type
        self.sequence = sequence
        self.payload = payload
    }

    public var hasCRC: Bool { control & Frame.crcFlag != 0 }

    public func encoded() -> [UInt8] {
        let length = UInt16(payload.count)
        var bytes: [UInt8] = [
            Frame.magic,
            UInt8(control & 0xFF), UInt8(control >> 8),
            UInt8(type & 0xFF), UInt8(type >> 8),
            UInt8(length & 0xFF), UInt8(length >> 8),
            sequence,
        ]
        bytes += payload
        if hasCRC {
            let crc = FrameCRC.checksum(bytes)
            bytes += [UInt8(crc & 0xFF), UInt8(crc >> 8)]
        }
        return bytes
    }
}

/// Reflected CRC-16, polynomial 0xA001, initial value 0xFFFF.
///
/// The EarA wiki calls this CRC-16/ARC, but BudsLink seeds it with 0xFFFF,
/// which is the MODBUS variant. Captured frames decide which one is right.
public enum FrameCRC {
    public static func checksum<S: Sequence>(_ bytes: S) -> UInt16 where S.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = crc & 1 != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }
}
