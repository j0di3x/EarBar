import Foundation

public enum ANCLevel: Equatable, Sendable {
    case high, mid, low, adaptive
}

public enum NoiseMode: Equatable, Sendable {
    case off
    case transparency
    case noiseCancellation(ANCLevel)
}

public enum HeadsetCommand: Equatable, Sendable {
    case requestModel
    case requestNoiseControl
    case setNoiseControl(NoiseMode)
    case requestLowLatency
    case setLowLatency(Bool)
    case requestDualConnection
    case setDualConnection(Bool)
    case requestDevices(start: Int)
    case requestSpatialAudio
    case setSpatialAudio(Bool)
    case requestBattery
    case setAmbientSound(level: Int, voiceFocus: Bool)
}

public enum BatteryPart: Hashable, Sendable {
    case left, right, `case`
    /// Over-ear headphones report one level for both sides.
    case single
}

public struct HeadsetDevice: Equatable, Sendable {
    public var address: [UInt8]
    public var name: String
    public var isConnected: Bool
}

public enum HeadsetEvent: Equatable, Sendable {
    case model(UInt16)
    /// The headphones answered the handshake and speak a supported protocol.
    case ready
    case noiseControl(NoiseMode)
    case lowLatency(Bool)
    case dualConnection(Bool)
    case devices([HeadsetDevice])
    case devicesChanged
    case spatialAudio(Bool)
    case battery([BatteryPart: Int])
    case ambientSound(level: Int, voiceFocus: Bool)
}

/// Headphones EarBar knows, matched by Bluetooth device name.
public enum HeadsetModel: Equatable, Sendable, CaseIterable {
    case nothingEar3
    case sonyWHCH720N

    public var name: String {
        switch self {
        case .nothingEar3: return "Nothing Ear (3)"
        case .sonyWHCH720N: return "Sony WH-CH720N"
        }
    }

    public var deviceNamePattern: String {
        switch self {
        case .nothingEar3: return "Nothing Ear"
        case .sonyWHCH720N: return "WH-CH720N"
        }
    }

    public static func matching(deviceName: String) -> HeadsetModel? {
        allCases.first { deviceName.localizedCaseInsensitiveContains($0.deviceNamePattern) }
    }

    public func makeProtocol() -> any HeadsetProtocol {
        switch self {
        case .nothingEar3: return NothingEar3Protocol()
        case .sonyWHCH720N: return SonyWHCH720NProtocol()
        }
    }
}

/// Turns commands into bytes and bytes into events. Knows nothing about
/// Bluetooth, so it can be tested with captured packets alone.
public protocol HeadsetProtocol {
    /// Bytes to write now. Empty when the model has no such command, or when
    /// the command waits in a queue until the headphones are ready for it.
    mutating func encode(_ command: HeadsetCommand) -> [UInt8]
    mutating func decode(_ bytes: [UInt8]) -> [HeadsetEvent]
    /// Bytes `decode` wants written, such as acknowledgements and queued commands.
    mutating func takeWrites() -> [[UInt8]]
}

extension HeadsetProtocol {
    public mutating func takeWrites() -> [[UInt8]] { [] }
}

public enum TransportState: Equatable, Sendable {
    case searching
    case connecting
    case connected
    case disconnected
}

/// Moves raw bytes to and from the headphones.
public protocol HeadsetTransport: AnyObject {
    /// The model behind the open channel, once connected.
    var model: HeadsetModel? { get }
    var onBytes: (([UInt8]) -> Void)? { get set }
    var onStateChange: ((TransportState) -> Void)? { get set }
    func start()
    func send(_ bytes: [UInt8])
}
