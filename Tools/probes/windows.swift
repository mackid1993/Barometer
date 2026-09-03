import Cocoa
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    let layer = w[kCGWindowLayer as String] as? Int ?? -1
    guard layer == 25 || layer == 24 else { continue }
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
    let name = w[kCGWindowName as String] as? String ?? "<nil>"
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print("layer=\(layer) pid=\(pid) owner=\(owner) name=\(name) x=\(b["X"] ?? 0) w=\(b["Width"] ?? 0)")
}
