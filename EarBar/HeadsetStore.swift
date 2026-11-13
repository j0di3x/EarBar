import Observation
import NothingProtocol

/// App state. Rows show what the headphones last reported, so changes made on
/// the headphones appear the same way as changes made here.
@Observable
final class HeadsetStore {
    private(set) var connection: TransportState = .searching
    /// The headphones behind the channel, known from their Bluetooth name.
    private(set) var model: HeadsetModel?
    private(set) var isSupportedModel = false
    private(set) var noiseMode: NoiseMode?
    private(set) var lowLatency: Bool?
    private(set) var dualConnection: Bool?
    private(set) var devices: [HeadsetDevice] = []
    private(set) var spatialAudio: Bool?
    private(set) var battery: [BatteryPart: Int] = [:]
    /// Ambient sound level and voice focus, on headphones that have them.
    private(set) var ambientLevel: Int?
    private(set) var voiceFocus: Bool?

    private static let maxDevices = 20

    @ObservationIgnored private var protocolHandler: any HeadsetProtocol = NothingEar3Protocol()
    @ObservationIgnored private let transport: HeadsetTransport
    /// Restored when the user picks noise cancellation again.
    @ObservationIgnored private var lastANCLevel: ANCLevel = .high

    init(transport: HeadsetTransport) {
        self.transport = transport
        transport.onBytes = { [weak self] in self?.handle($0) }
        transport.onStateChange = { [weak self] in self?.handle($0) }
        transport.start()
    }

    func setNoiseMode(_ mode: NoiseMode) {
        send(.setNoiseControl(mode))
        send(.requestNoiseControl)
    }

    func selectNoiseCancellation() {
        setNoiseMode(.noiseCancellation(lastANCLevel))
    }

    func setLowLatency(_ enabled: Bool) {
        send(.setLowLatency(enabled))
        send(.requestLowLatency)
    }

    func setDualConnection(_ enabled: Bool) {
        send(.setDualConnection(enabled))
        send(.requestDualConnection)
    }

    func setSpatialAudio(_ enabled: Bool) {
        send(.setSpatialAudio(enabled))
        send(.requestSpatialAudio)
    }

    func setAmbientLevel(_ level: Int) {
        guard let voiceFocus else { return }
        send(.setAmbientSound(level: level, voiceFocus: voiceFocus))
        send(.requestNoiseControl)
    }

    func setVoiceFocus(_ enabled: Bool) {
        guard let ambientLevel else { return }
        send(.setAmbientSound(level: ambientLevel, voiceFocus: enabled))
        send(.requestNoiseControl)
    }

    /// Re-reads settings the headphones do not push, such as changes made in
    /// the phone app. Called when the popover opens.
    func refresh() {
        guard isSupportedModel else { return }
        send(.requestNoiseControl)
        send(.requestLowLatency)
        send(.requestDualConnection)
        send(.requestDevices(start: 0))
        send(.requestSpatialAudio)
        send(.requestBattery)
    }

    private func send(_ command: HeadsetCommand) {
        transport.send(protocolHandler.encode(command))
    }

    private func flushWrites() {
        for bytes in protocolHandler.takeWrites() {
            transport.send(bytes)
        }
    }

    private func handle(_ state: TransportState) {
        connection = state
        if state == .connected, let connected = transport.model {
            model = connected
            protocolHandler = connected.makeProtocol()
            send(.requestModel)
        } else {
            model = state == .connecting ? transport.model : nil
            isSupportedModel = false
            ambientLevel = nil
            voiceFocus = nil
            noiseMode = nil
            lowLatency = nil
            dualConnection = nil
            devices = []
            spatialAudio = nil
            battery = [:]
        }
    }

    private func handle(_ bytes: [UInt8]) {
        let events = protocolHandler.decode(bytes)
        flushWrites()
        for event in events {
            switch event {
            case .model(let id):
                isSupportedModel = id == NothingEar3Protocol.modelID
                refresh()
            case .ready:
                isSupportedModel = true
                refresh()
            case .ambientSound(let level, let focus):
                ambientLevel = level
                voiceFocus = focus
            case .noiseControl(let mode):
                noiseMode = mode
                if case .noiseCancellation(let level) = mode {
                    lastANCLevel = level
                }
            case .lowLatency(let enabled):
                lowLatency = enabled
            case .dualConnection(let enabled):
                dualConnection = enabled
            case .devices(let reported):
                // The list arrives in pages. Ask for more while new devices show up.
                let added = reported.filter { device in
                    !devices.contains { $0.address == device.address }
                }
                devices = devices.map { old in
                    reported.first { $0.address == old.address } ?? old
                } + added
                if !added.isEmpty, devices.count < Self.maxDevices {
                    send(.requestDevices(start: devices.count))
                }
            case .devicesChanged:
                send(.requestDevices(start: 0))
            case .spatialAudio(let enabled):
                spatialAudio = enabled
            case .battery(let levels):
                // Each frame lists every part that is connected right now.
                battery = levels
            }
        }
    }
}
