import SwiftUI
import AppKit

@main
struct EarBarApp: App {
    private let store = HeadsetStore(transport: RFCOMMTransport())

    init() {
        UpdateChecker.shared.start(repo: "j0di3x/EarBar", appName: "EarBar")
        // `-previewWindow` also shows the panel in a normal window (for README screenshots).
        guard CommandLine.arguments.contains("-previewWindow") else { return }
        let store = self.store
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "EarBar"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PopoverView(store: store).background(.regularMaterial))
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(b)?.isHidden = true }
            if CommandLine.arguments.contains("-light") { window.appearance = NSAppearance(named: .aqua) }
            if CommandLine.arguments.contains("-dark") { window.appearance = NSAppearance(named: .darkAqua) }
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            MenuBarIcon(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarIcon: View {
    let store: HeadsetStore

    var body: some View {
        if store.model == .sonyWHCH720N {
            Image(systemName: "headphones")
        } else {
            Image("nothing-ear-1")
        }
    }
}
