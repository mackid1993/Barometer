import AppKit

// LSUIElement in the helper's Info.plist is the source of the agent activation policy.
// Setting the accessory policy before the AppKit run loop produces zero-height status item
// frames on macOS 27; see docs/AGENTS.md.
let helper = StatusItemHelper()
let application = NSApplication.shared
application.delegate = helper
application.run()
