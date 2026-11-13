import Foundation

/// Read-only requests, from BudsLink and nothing-x-macos.
/// All UNVERIFIED on hardware for Nothing Ear (3). `verified` flips per command
/// once the owner confirms it on real headphones.
public enum NothingRequest: UInt16, CaseIterable, Sendable {
    case modelID = 0xC01C
    case firmware = 0xC042
    case battery = 0xC007
    case noiseControl = 0xC01E
    case lowLatency = 0xC041
    case spatialAudio = 0xC04F
    case dualConnection = 0xC027
    case dualConnectionDevices = 0xC028

    public var verified: Bool { false }
}
