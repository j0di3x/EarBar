import AppKit
import IOBluetooth
import NothingProtocol

/// Opens the Nothing (or, with `--sony`, the Sony) RFCOMM service and logs every byte as hex.
/// Listens only, unless `--probe` is given. Never sends a SET command.
final class SpikeDelegate: NSObject, NSApplicationDelegate {
    /// Vendor service UUID from BudsLink and the EarA wiki. UNVERIFIED on Ear (3).
    private static let serviceUUID: [UInt8] = [
        0xAE, 0xAC, 0x4A, 0x03, 0xDF, 0xF5, 0x49, 0x8F,
        0x84, 0x3A, 0x34, 0x48, 0x7C, 0xF1, 0x33, 0xEB,
    ]
    /// Community write-ups use this channel when SDP finds nothing.
    private static let fallbackChannel: BluetoothRFCOMMChannelID = 15
    private static let probeSpacing: TimeInterval = 0.3
    /// Sony service UUIDs from Gadgetbridge; V2 is preferred when both exist. UNVERIFIED on WH-CH720N.
    private static let sonyServiceUUIDs: [(name: String, bytes: [UInt8])] = [
        ("V2", [0x95, 0x6C, 0x7B, 0x26, 0xD4, 0x9A, 0x4B, 0xA8,
                0xB0, 0x3F, 0xB1, 0x7D, 0x39, 0x3C, 0xB6, 0xE2]),
        ("V1", [0x96, 0xCC, 0x20, 0x3E, 0x50, 0x68, 0x46, 0xAD,
                0xB3, 0x2D, 0xE3, 0x16, 0xF5, 0xE0, 0x69, 0xBA]),
    ]

    private let probe: Bool
    private let sony: Bool
    private var sonyDecoder = SonyFrameDecoder()
    /// Read-only Sony requests still to send; one at a time, each after the previous ACK.
    private var sonyQueue: [(label: String, type: UInt8, payload: [UInt8])] = []
    private var sonyWaitingForAck = false
    private let forcedChannel: BluetoothRFCOMMChannelID?
    private let log = SpikeLog()
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var decoder = FrameDecoder()
    private var sequence: UInt8 = 0

    init(arguments: [String]) {
        probe = arguments.contains("--probe")
        sony = arguments.contains("--sony")
        if let index = arguments.firstIndex(of: "--channel"), index + 1 < arguments.count {
            forcedChannel = BluetoothRFCOMMChannelID(arguments[index + 1])
        } else {
            forcedChannel = nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.note("Spike started. probe=\(probe) sony=\(sony) log=\(log.path)")
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        log.note("Paired devices visible: \(paired.count)")
        let brand = sony ? "WH-CH720N" : "Nothing"
        let matches = paired.filter { ($0.name ?? "").localizedCaseInsensitiveContains(brand) }
        guard let found = matches.first(where: { $0.isConnected() }) ?? matches.first else {
            log.note("No paired \(brand) device. If the count above is 0, grant Bluetooth access in System Settings.")
            NSApp.terminate(nil)
            return
        }
        device = found
        log.note("Device: \(found.name ?? "?") \(found.addressString ?? "?") connected=\(found.isConnected())")

        if let forcedChannel {
            open(channelID: forcedChannel, reason: "--channel")
            return
        }
        let status = found.performSDPQuery(self)
        log.note("SDP query started, status \(hex(status))")
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        log.note("SDP query complete, status \(hex(status))")
        var id: BluetoothRFCOMMChannelID = 0
        let records = device.services as? [IOBluetoothSDPServiceRecord] ?? []
        for record in records {
            var recordID: BluetoothRFCOMMChannelID = 0
            let rfcomm = record.getRFCOMMChannelID(&recordID) == kIOReturnSuccess ? "rfcomm=\(recordID)" : "no rfcomm"
            log.note("Service: \(record.getServiceName() ?? "unnamed") \(rfcomm)")
        }

        if sony {
            for service in Self.sonyServiceUUIDs {
                let uuid = IOBluetoothSDPUUID(bytes: service.bytes, length: service.bytes.count)
                if let record = device.getServiceRecord(for: uuid), record.getRFCOMMChannelID(&id) == kIOReturnSuccess {
                    open(channelID: id, reason: "SDP, Sony \(service.name) UUID")
                    return
                }
            }
            log.note("No Sony service UUID in SDP. Stopping; there is no known fallback channel.")
            NSApp.terminate(nil)
            return
        }

        let uuid = IOBluetoothSDPUUID(bytes: Self.serviceUUID, length: Self.serviceUUID.count)
        if let record = device.getServiceRecord(for: uuid), record.getRFCOMMChannelID(&id) == kIOReturnSuccess {
            open(channelID: id, reason: "SDP")
        } else {
            open(channelID: Self.fallbackChannel, reason: "fallback, vendor UUID not in SDP")
        }
    }

    private func open(channelID: BluetoothRFCOMMChannelID, reason: String) {
        log.note("Opening RFCOMM channel \(channelID) (\(reason))")
        var opened: IOBluetoothRFCOMMChannel?
        let status = device?.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
        channel = opened
        if status != kIOReturnSuccess {
            log.note("Open failed at once, status \(hex(status ?? kIOReturnError))")
            NSApp.terminate(nil)
        }
    }

    private func sendProbes(_ requests: ArraySlice<NothingRequest>) {
        guard let request = requests.first, let channel else {
            log.note("Probes done. Keep using the controls on the headphones.")
            return
        }
        sequence = sequence >= 250 ? 1 : sequence + 1
        // The device list request carries a start index.
        let payload: [UInt8] = request == .dualConnectionDevices ? [0] : []
        var bytes = Frame(type: request.rawValue, sequence: sequence, payload: payload).encoded()
        log.packet("TX \(request)", bytes)
        let status = channel.writeSync(&bytes, length: UInt16(bytes.count))
        if status != kIOReturnSuccess {
            log.note("Write failed, status \(hex(status))")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeSpacing) { [weak self] in
            self?.sendProbes(requests.dropFirst())
        }
    }
}

extension SpikeDelegate: IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        log.note("Channel open complete, status \(hex(error))")
        guard error == kIOReturnSuccess else {
            NSApp.terminate(nil)
            return
        }
        log.note("Listening. Use the controls on the headphones now. Quit: pkill Spike")
        if probe {
            if sony {
                // Init first; the reply length tells protocol V1 (4 bytes) from V2 (8 bytes).
                sonyQueue = [("init", SonyFrame.command1, [0x00, 0x00])]
                sendNextSonyProbe()
            } else {
                sendProbes(NothingRequest.allCases[...])
            }
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        log.packet("RX chunk", bytes)
        if sony {
            for decoded in sonyDecoder.append(bytes) {
                handleSony(decoded)
            }
            return
        }
        for decoded in decoder.append(bytes) {
            let frame = decoded.frame
            let crc = decoded.crcValid.map { $0 ? "ok" : "BAD" } ?? "none"
            log.note(String(format: "  frame type=%04X control=%04X seq=%d crc=%@ payload=%@",
                            frame.type, frame.control, frame.sequence, crc, frame.payload.hexString))
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        log.note("Channel closed")
        NSApp.terminate(nil)
    }
}

private func hex(_ status: IOReturn) -> String {
    String(format: "0x%08X", UInt32(bitPattern: status))
}

extension SpikeDelegate {
    private func handleSony(_ decoded: DecodedSonyFrame) {
        let frame = decoded.frame
        log.note(String(format: "  sony type=%02X seq=%d sum=%@ payload=%@",
                        frame.type, frame.sequence, decoded.checksumValid ? "ok" : "BAD", frame.payload.hexString))
        guard decoded.checksumValid else { return }

        if frame.type == SonyFrame.ack {
            sequence = frame.sequence
            sonyWaitingForAck = false
            sendNextSonyProbe()
            return
        }
        writeSony(SonyFrame.acknowledging(sequence: frame.sequence), label: "TX ack")

        // Init reply: queue the read-only requests Gadgetbridge sends for this protocol version.
        if probe, frame.type == SonyFrame.command1, frame.payload.first == 0x01 {
            switch frame.payload.count {
            case 8:
                log.note("Init reply has 8 bytes: protocol V2")
                sonyQueue += [
                    ("firmware", SonyFrame.command1, [0x04, 0x02]),
                    ("battery", SonyFrame.command1, [0x22, 0x00]),
                    // Gadgetbridge uses 66 15; the WH-CH720N answers only 66 17.
                    ("ambient sound", SonyFrame.command1, [0x66, 0x17]),
                ]
            case 4:
                log.note("Init reply has 4 bytes: protocol V1. Only firmware is probed; V1 request bytes are not known well enough.")
                sonyQueue += [("firmware", SonyFrame.command1, [0x04, 0x02])]
            default:
                log.note("Init reply has \(frame.payload.count) bytes: unknown protocol version")
            }
            sendNextSonyProbe()
        }
    }

    private func sendNextSonyProbe() {
        guard !sonyWaitingForAck else { return }
        guard !sonyQueue.isEmpty else {
            if probe {
                log.note("Probes done. Keep using the controls on the headphones.")
            }
            return
        }
        let request = sonyQueue.removeFirst()
        sonyWaitingForAck = true
        writeSony(SonyFrame(type: request.type, sequence: sequence, payload: request.payload), label: "TX \(request.label)")
    }

    private func writeSony(_ frame: SonyFrame, label: String) {
        var bytes = frame.encoded()
        log.packet(label, bytes)
        let status = channel?.writeSync(&bytes, length: UInt16(bytes.count)) ?? kIOReturnNotOpen
        if status != kIOReturnSuccess {
            log.note("Write failed, status \(hex(status))")
        }
    }
}
