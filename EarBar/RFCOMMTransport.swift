import AppKit
import IOBluetooth
import NothingProtocol

/// Holds one RFCOMM channel to a supported pair of headphones. When several
/// are connected, the one connected last wins. Driven by Bluetooth and
/// workspace notifications only.
final class RFCOMMTransport: NSObject, HeadsetTransport {
    /// Nothing "NT LINK" service. Found over SDP on Ear (3) at channel 15.
    private static let nothingServiceUUID: [UInt8] = [
        0xAE, 0xAC, 0x4A, 0x03, 0xDF, 0xF5, 0x49, 0x8F,
        0x84, 0x3A, 0x34, 0x48, 0x7C, 0xF1, 0x33, 0xEB,
    ]
    private static let nothingFallbackChannel: BluetoothRFCOMMChannelID = 15
    /// Sony V2 service. Found over SDP on WH-CH720N at channel 18.
    private static let sonyServiceUUID: [UInt8] = [
        0x95, 0x6C, 0x7B, 0x26, 0xD4, 0x9A, 0x4B, 0xA8,
        0xB0, 0x3F, 0xB1, 0x7D, 0x39, 0x3C, 0xB6, 0xE2,
    ]

    var onBytes: (([UInt8]) -> Void)?
    var onStateChange: ((TransportState) -> Void)?
    private(set) var model: HeadsetModel?

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?

    func start() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        connectToPairedHeadphones()
    }

    func send(_ bytes: [UInt8]) {
        guard let channel, !bytes.isEmpty else { return }
        var bytes = bytes
        _ = channel.writeSync(&bytes, length: UInt16(bytes.count))
    }

    private func connectToPairedHeadphones(excluding gone: IOBluetoothDevice? = nil) {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let candidates = paired.filter { $0.addressString != gone?.addressString }
        if let device = candidates.first(where: { Self.model(of: $0) != nil && $0.isConnected() }) {
            connect(to: device)
        } else {
            onStateChange?(.searching)
        }
    }

    private static func model(of device: IOBluetoothDevice) -> HeadsetModel? {
        HeadsetModel.matching(deviceName: device.name ?? "")
    }

    private func connect(to newDevice: IOBluetoothDevice) {
        guard let newModel = Self.model(of: newDevice), !isCurrent(newDevice) else { return }
        // Another pair of headphones takes over the channel.
        if device != nil {
            channel?.close()
            dropChannel()
        }
        device = newDevice
        model = newModel
        onStateChange?(.connecting)
        disconnectNotification?.unregister()
        disconnectNotification = newDevice.register(
            forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        if newDevice.performSDPQuery(self) != kIOReturnSuccess {
            sdpQueryComplete(newDevice, status: kIOReturnError)
        }
    }

    private func isCurrent(_ other: IOBluetoothDevice) -> Bool {
        device?.addressString == other.addressString
    }

    @objc func sdpQueryComplete(_ queried: IOBluetoothDevice, status: IOReturn) {
        guard isCurrent(queried), let model, let id = Self.channelID(on: queried, for: model) else {
            if isCurrent(queried) {
                dropChannel()
            }
            return
        }
        var opened: IOBluetoothRFCOMMChannel?
        if queried.openRFCOMMChannelAsync(&opened, withChannelID: id, delegate: self) == kIOReturnSuccess {
            channel = opened
        } else {
            dropChannel()
        }
    }

    private static func channelID(on device: IOBluetoothDevice, for model: HeadsetModel) -> BluetoothRFCOMMChannelID? {
        let serviceUUID = model == .sonyWHCH720N ? sonyServiceUUID : nothingServiceUUID
        let uuid = IOBluetoothSDPUUID(bytes: serviceUUID, length: serviceUUID.count)
        var id: BluetoothRFCOMMChannelID = 0
        if device.getServiceRecord(for: uuid)?.getRFCOMMChannelID(&id) == kIOReturnSuccess {
            return id
        }
        return model == .nothingEar3 ? nothingFallbackChannel : nil
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        connect(to: device)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device gone: IOBluetoothDevice) {
        guard isCurrent(gone) else { return }
        dropChannel()
        // Fall back to other supported headphones that are still connected.
        connectToPairedHeadphones(excluding: gone)
    }

    @objc private func willSleep() {
        channel?.close()
        dropChannel()
    }

    @objc private func didWake() {
        connectToPairedHeadphones()
    }

    private func dropChannel() {
        channel = nil
        device = nil
        model = nil
        onStateChange?(.disconnected)
    }
}

extension RFCOMMTransport: IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        if error == kIOReturnSuccess {
            onStateChange?(.connected)
        } else {
            dropChannel()
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        onBytes?(Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength)))
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        if rfcommChannel === channel {
            dropChannel()
        }
    }
}
