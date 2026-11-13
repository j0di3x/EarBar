import SwiftUI
import NothingProtocol

struct PopoverView: View {
    let store: HeadsetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let mode = store.noiseMode {
                NoiseControlRow(mode: mode, store: store)
                if mode == .transparency, let level = store.ambientLevel, let voiceFocus = store.voiceFocus {
                    AmbientSoundCard(level: level, voiceFocus: voiceFocus, store: store)
                }
            }
            settings
            HStack {
                Spacer()
                Button("Quit EarBar") { NSApplication.shared.terminate(nil) }
                    .glassButton()
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            store.refresh()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.model?.name ?? "Headphones")
                    .font(.headline)
                Text(status)
                    .foregroundStyle(.secondary)
                if !batteryText.isEmpty {
                    Text(batteryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.model == .sonyWHCH720N, store.battery[.single] != nil {
                Image(systemName: "headphones")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Headphones connected")
            } else {
                connectedBuds
            }
        }
        .padding(.horizontal, 4)
    }

    /// Laid out as in the photo: facing the wearer, so the right bud is on the left.
    private var connectedBuds: some View {
        HStack(spacing: 6) {
            if store.battery[.right] != nil {
                budImage("bud-right", label: "Right earbud connected")
            }
            if store.battery[.left] != nil {
                budImage("bud-left", label: "Left earbud connected")
            }
        }
    }

    private func budImage(_ name: String, label: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(height: 72)
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private var settings: some View {
        if store.lowLatency != nil || store.dualConnection != nil || store.spatialAudio != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let lowLatency = store.lowLatency {
                    Toggle("Low lag mode", isOn: Binding(get: { lowLatency }, set: { store.setLowLatency($0) }))
                }
                if let dualConnection = store.dualConnection {
                    Toggle("Multi device", isOn: Binding(get: { dualConnection }, set: { store.setDualConnection($0) }))
                    ForEach(store.devices.filter(\.isConnected), id: \.address) { device in
                        Label(device.name, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let spatialAudio = store.spatialAudio {
                    Toggle("Spatial audio", isOn: Binding(get: { spatialAudio }, set: { store.setSpatialAudio($0) }))
                }
            }
            .toggleStyle(.switch)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private var batteryText: String {
        let parts: [(BatteryPart, String)] = [(.single, "Battery"), (.left, "L"), (.right, "R"), (.case, "Case")]
        return parts.compactMap { part, label in
            store.battery[part].map { "\(label) \($0)%" }
        }.joined(separator: "  ")
    }

    private var status: String {
        switch store.connection {
        case .searching: return "Waiting for headphones"
        case .connecting: return "Connecting"
        case .disconnected: return "Disconnected"
        case .connected: return store.isSupportedModel ? "Connected" : "Unsupported headphones"
        }
    }
}

private struct NoiseControlRow: View {
    private enum Choice: CaseIterable {
        case noiseCancellation, transparency, off
    }

    private static let trackHeight: CGFloat = 38
    private static let inset: CGFloat = 3
    /// Thumb grows while held, like the system Liquid Glass controls.
    private static let liftScale: CGFloat = 1.18

    let mode: NoiseMode
    let store: HeadsetStore

    /// Thumb position while dragging, measured from the track's leading edge.
    @State private var dragX: CGFloat?
    /// Shown until the headphones report the new mode, so the thumb stays put.
    @State private var pending: Choice?

    var body: some View {
        GeometryReader { geometry in
            let segment = (geometry.size.width - Self.inset * 2) / CGFloat(Choice.allCases.count)
            let shown = pending ?? current
            let thumbX = dragX ?? Self.inset + CGFloat(index(of: shown)) * segment
            let thumbHeight = Self.trackHeight - Self.inset * 2
            let liftAnimation = Animation.spring(duration: 0.25, bounce: 0.35)

            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)

                Color.clear
                    .frame(width: segment, height: thumbHeight)
                    .glassThumb()
                    .scaleEffect(dragX == nil ? 1 : Self.liftScale)
                    .shadow(color: .black.opacity(dragX == nil ? 0 : 0.3), radius: 6, y: 3)
                    .offset(x: thumbX)
                    .animation(liftAnimation, value: dragX == nil)

                HStack(spacing: 0) {
                    ForEach(Choice.allCases, id: \.self) { choice in
                        Text(label(for: choice))
                            .font(.callout.weight(choice == highlighted(segment: segment, shown: shown) ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(width: segment)
                            .accessibilityAddTraits(choice == shown ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Self.inset)
                .allowsHitTesting(false)
            }
            .contentShape(Capsule())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let maxX = Self.inset + segment * CGFloat(Choice.allCases.count - 1)
                        dragX = min(max(value.location.x - segment / 2, Self.inset), maxX)
                    }
                    .onEnded { value in
                        let choice = choice(at: value.location.x, segment: segment)
                        withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                            dragX = nil
                            pending = choice == current ? nil : choice
                        }
                        if choice != current {
                            select(choice)
                        }
                    }
            )
            .animation(.spring(duration: 0.35, bounce: 0.25), value: shown)
        }
        .frame(height: Self.trackHeight)
        .onChange(of: mode) { pending = nil }
        .accessibilityLabel("Noise control")
    }

    private var current: Choice {
        switch mode {
        case .noiseCancellation: return .noiseCancellation
        case .transparency: return .transparency
        case .off: return .off
        }
    }

    private func label(for choice: Choice) -> String {
        switch choice {
        case .noiseCancellation: return "ANC"
        // Sony calls it ambient sound.
        case .transparency: return store.model == .sonyWHCH720N ? "Ambient" : "Transparency"
        case .off: return "Off"
        }
    }

    private func index(of choice: Choice) -> Int {
        Choice.allCases.firstIndex(of: choice) ?? 0
    }

    private func choice(at x: CGFloat, segment: CGFloat) -> Choice {
        let index = Int((x - Self.inset) / segment)
        return Choice.allCases[min(max(index, 0), Choice.allCases.count - 1)]
    }

    private func highlighted(segment: CGFloat, shown: Choice) -> Choice {
        dragX.map { choice(at: $0 + segment / 2, segment: segment) } ?? shown
    }

    private func select(_ choice: Choice) {
        switch choice {
        case .noiseCancellation: store.selectNoiseCancellation()
        case .transparency: store.setNoiseMode(.transparency)
        case .off: store.setNoiseMode(.off)
        }
    }
}

/// Ambient sound level and voice focus, shown while ambient sound is on.
private struct AmbientSoundCard: View {
    /// The range the Sony app offers.
    private static let levels: ClosedRange<Double> = 1...20

    let level: Int
    let voiceFocus: Bool
    let store: HeadsetStore

    /// Slider value while dragging; sent once the drag ends, so the
    /// headphones get one command instead of a stream.
    @State private var draft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ambient level")
                Spacer()
                Text("\(Int(draft ?? Double(level)))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(get: { draft ?? Double(level) }, set: { draft = $0 }),
                in: Self.levels,
                step: 1
            ) { editing in
                guard !editing, let draft else { return }
                store.setAmbientLevel(Int(draft))
            }
            .accessibilityLabel("Ambient level")
            Toggle("Focus on voice", isOn: Binding(get: { voiceFocus }, set: { store.setVoiceFocus($0) }))
                .toggleStyle(.switch)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onChange(of: level) { draft = nil }
    }
}
