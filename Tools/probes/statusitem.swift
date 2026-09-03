import Cocoa
setbuf(stdout, nil); let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
item.autosaveName = "MBSProbeAutosave"
func dump(_ tag: String) {
    let win = item.button?.window
    print("[\(tag)] window.title='\(win?.title ?? "nil")' num=\(win?.windowNumber ?? -1) button.title='\(item.button?.title ?? "")' axLabel='\(item.button?.accessibilityLabel() ?? "nil")' axTitle='\(item.button?.accessibilityTitle() ?? "nil")'")
    let me = Int(getpid())
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list where (w[kCGWindowOwnerPID as String] as? Int) == me {
        print("      CG id=\(w[kCGWindowNumber as String] ?? "?") name='\(w[kCGWindowName as String] ?? "nil")' layer=\(w[kCGWindowLayer as String] ?? "?") bounds=\(w[kCGWindowBounds as String] ?? "?")")
    }
}
let steps: [(String, () -> Void)] = [
    ("0 autosave only, no title", {}),
    ("A title CPU 42%", { item.button?.title = "CPU 42%" }),
    ("B title CPU 77%", { item.button?.title = "CPU 77%" }),
    ("C set AX label", { item.button?.setAccessibilityLabel("Probe AX Label") }),
    ("D image only, empty title", { item.button?.title = ""; item.button?.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "CPU icon desc") }),
    ("E change autosaveName", { item.autosaveName = "MBSProbeRenamed" }),
]
var i = 0
func next() {
    guard i < steps.count else { app.terminate(nil); return }
    let (tag, action) = steps[i]; i += 1
    action()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { dump(tag); next() }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { next() }
app.run()
