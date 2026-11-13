import Foundation

/// Nothing Ear (3), model B173.
public struct NothingEar3Protocol: HeadsetProtocol {
    public static let modelID: UInt16 = 0xB173

    private enum FrameType {
        static let modelRequest: UInt16 = 0xC01C
        static let modelReply: UInt16 = 0x401C
        static let noiseRequest: UInt16 = 0xC01E
        static let noiseReply: UInt16 = 0x401E
        static let noisePush: UInt16 = 0xE003
        // Confirmed by the owner on Ear (3) for high, transparency and off.
        static let noiseSet: UInt16 = 0xF00F
        static let latencyRequest: UInt16 = 0xC041
        static let latencyReply: UInt16 = 0x4041
        // UNVERIFIED on hardware: never seen from Ear (3).
        static let latencyPush: UInt16 = 0x7040
        // Confirmed by the owner on Ear (3).
        static let latencySet: UInt16 = 0xF040
        static let dualRequest: UInt16 = 0xC027
        static let dualReply: UInt16 = 0x4027
        // UNVERIFIED on hardware: never seen from Ear (3).
        static let dualPush: UInt16 = 0xE006
        // Confirmed by the owner on Ear (3).
        static let dualSet: UInt16 = 0xF01A
        static let devicesRequest: UInt16 = 0xC028
        static let devicesReply: UInt16 = 0x4028
        static let spatialRequest: UInt16 = 0xC04F
        static let spatialReply: UInt16 = 0x404F
        // Confirmed by the owner on Ear (3).
        static let spatialSet: UInt16 = 0xF052
        static let batteryRequest: UInt16 = 0xC007
        static let batteryReply: UInt16 = 0x4007
        static let batteryPush: UInt16 = 0xE001
        // Captured on Ear (3); payload layout not understood.
        static let devicesPush: UInt16 = 0xE00E
    }

    private var decoder = FrameDecoder()
    private var sequence: UInt8 = 0

    public init() {}

    public mutating func encode(_ command: HeadsetCommand) -> [UInt8] {
        sequence = sequence >= 250 ? 1 : sequence + 1
        switch command {
        case .requestModel:
            return Frame(type: FrameType.modelRequest, sequence: sequence).encoded()
        case .requestNoiseControl:
            return Frame(type: FrameType.noiseRequest, sequence: sequence).encoded()
        case .setNoiseControl(let mode):
            return Frame(type: FrameType.noiseSet, sequence: sequence,
                         payload: [0x01, Self.byte(for: mode), 0x00]).encoded()
        case .requestLowLatency:
            return Frame(type: FrameType.latencyRequest, sequence: sequence).encoded()
        case .setLowLatency(let enabled):
            return Frame(type: FrameType.latencySet, sequence: sequence,
                         payload: [enabled ? 0x01 : 0x02, 0x00]).encoded()
        case .requestDualConnection:
            return Frame(type: FrameType.dualRequest, sequence: sequence).encoded()
        case .setDualConnection(let enabled):
            return Frame(type: FrameType.dualSet, sequence: sequence,
                         payload: [enabled ? 0x01 : 0x00]).encoded()
        case .requestDevices(let start):
            return Frame(type: FrameType.devicesRequest, sequence: sequence,
                         payload: [UInt8(clamping: start)]).encoded()
        case .requestSpatialAudio:
            return Frame(type: FrameType.spatialRequest, sequence: sequence).encoded()
        case .setSpatialAudio(let enabled):
            return Frame(type: FrameType.spatialSet, sequence: sequence,
                         payload: [enabled ? 0x01 : 0x00]).encoded()
        case .requestBattery:
            return Frame(type: FrameType.batteryRequest, sequence: sequence).encoded()
        case .setAmbientSound:
            return []
        }
    }

    public mutating func decode(_ bytes: [UInt8]) -> [HeadsetEvent] {
        decoder.append(bytes).compactMap { decoded in
            decoded.crcValid == false ? nil : Self.event(from: decoded.frame)
        }
    }

    private static func event(from frame: Frame) -> HeadsetEvent? {
        switch frame.type {
        case FrameType.modelReply where frame.payload.count >= 2:
            return .model(UInt16(frame.payload[1]) << 8 | UInt16(frame.payload[0]))
        case FrameType.noiseReply where frame.payload.count >= 2,
             FrameType.noisePush where frame.payload.count >= 2:
            return mode(for: frame.payload[1]).map(HeadsetEvent.noiseControl)
        case FrameType.latencyReply where frame.payload.count >= 1,
             FrameType.latencyPush where frame.payload.count >= 1:
            // Captured on Ear (3): 01 on, 02 off.
            return .lowLatency(frame.payload[0] == 0x01)
        case FrameType.spatialReply where frame.payload.count >= 1:
            // Captured on Ear (3): 01 fixed, 00 off.
            return .spatialAudio(frame.payload[0] == 0x01)
        case FrameType.dualReply where frame.payload.count >= 1,
             FrameType.dualPush where frame.payload.count >= 1:
            // Captured on Ear (3): 01 on, 00 off.
            return .dualConnection(frame.payload[0] == 0x01)
        case FrameType.batteryReply, FrameType.batteryPush:
            return .battery(battery(from: frame.payload))
        case FrameType.devicesReply:
            return .devices(devices(from: frame.payload))
        case FrameType.devicesPush:
            return .devicesChanged
        default:
            return nil
        }
    }

    // Captured on Ear (3): entry count, then id and percent pairs. 02 left, 03 right, 04 case.
    private static func battery(from payload: [UInt8]) -> [BatteryPart: Int] {
        var levels: [BatteryPart: Int] = [:]
        for index in stride(from: 1, to: payload.count - 1, by: 2) {
            // UNVERIFIED on hardware: the top bit may mean charging, so it is masked.
            let level = Int(payload[index + 1] & 0x7F)
            switch payload[index] {
            case 0x02: levels[.left] = level
            case 0x03: levels[.right] = level
            case 0x04: levels[.case] = level
            default: break
            }
        }
        return levels
    }

    // Layout from BudsLink, checked against a local capture: two bytes, device
    // count, then per device flags, 6 byte address, name length (0x80 = clipped), name.
    private static func devices(from payload: [UInt8]) -> [HeadsetDevice] {
        guard payload.count >= 3 else { return [] }
        var devices: [HeadsetDevice] = []
        var index = 3
        while devices.count < Int(payload[2]), index + 8 <= payload.count {
            let lengthByte = payload[index + 7]
            let nameLength = lengthByte & 0x80 != 0 ? 0x1F : Int(lengthByte & 0x7F)
            guard index + 8 + nameLength <= payload.count else { break }
            devices.append(HeadsetDevice(
                address: Array(payload[(index + 1)..<(index + 7)]),
                name: String(decoding: payload[(index + 8)..<(index + 8 + nameLength)], as: UTF8.self),
                isConnected: payload[index] & 0x0F == 0x01))
            index += 8 + nameLength
        }
        return devices
    }

    // Confirmed on Ear (3): 01 high, 05 off, 07 transparency.
    // UNVERIFIED on hardware: 02 mid, 03 low, 04 adaptive.
    private static func mode(for byte: UInt8) -> NoiseMode? {
        switch byte {
        case 0x01: return .noiseCancellation(.high)
        case 0x02: return .noiseCancellation(.mid)
        case 0x03: return .noiseCancellation(.low)
        case 0x04: return .noiseCancellation(.adaptive)
        case 0x05: return .off
        case 0x07: return .transparency
        default: return nil
        }
    }

    private static func byte(for mode: NoiseMode) -> UInt8 {
        switch mode {
        case .noiseCancellation(.high): return 0x01
        case .noiseCancellation(.mid): return 0x02
        case .noiseCancellation(.low): return 0x03
        case .noiseCancellation(.adaptive): return 0x04
        case .off: return 0x05
        case .transparency: return 0x07
        }
    }
}
