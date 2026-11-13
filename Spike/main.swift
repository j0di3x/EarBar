import AppKit

// Phase 0 spike. Run with: open Spike.app --args [--sony] [--probe] [--channel N]
let app = NSApplication.shared
let spike = SpikeDelegate(arguments: CommandLine.arguments)
app.delegate = spike
app.run()
