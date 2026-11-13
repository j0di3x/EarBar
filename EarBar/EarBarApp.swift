import SwiftUI

@main
struct EarBarApp: App {
    private let store = HeadsetStore(transport: RFCOMMTransport())

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
