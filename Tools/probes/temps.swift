import Foundation
import IOKit

@_silgen_name("IOHIDEventSystemClientCreate") func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventSystemClientSetMatching") func IOHIDEventSystemClientSetMatching(_ client: CFTypeRef, _ matching: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") func IOHIDEventSystemClientCopyServices(_ client: CFTypeRef) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty") func IOHIDServiceClientCopyProperty(_ service: CFTypeRef, _ key: CFString) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDServiceClientCopyEvent") func IOHIDServiceClientCopyEvent(_ service: CFTypeRef, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetFloatValue") func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

let kIOHIDEventTypeTemperature: Int64 = 15
let kIOHIDEventTypePower: Int64 = 25
func field(_ t: Int64) -> Int32 { Int32(t << 16) }

func dump(usage: Int, type: Int64, label: String) {
    guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { print("no client"); return }
    let matching: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": usage]
    _ = IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
    guard let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [CFTypeRef] else { print("\(label): no services"); return }
    print("=== \(label): \(services.count) services ===")
    for s in services {
        let name = IOHIDServiceClientCopyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String ?? "?"
        if let ev = IOHIDServiceClientCopyEvent(s, type, 0, 0)?.takeRetainedValue() {
            let v = IOHIDEventGetFloatValue(ev, field(type))
            print(String(format: "%-40@ %8.2f", name as NSString, v))
        }
    }
}
dump(usage: 5, type: kIOHIDEventTypeTemperature, label: "temperature")
