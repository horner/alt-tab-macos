import Cocoa
import ApplicationServices
let pids = Set(CommandLine.arguments.dropFirst().compactMap(Int32.init))
let apps = NSWorkspace.shared.runningApplications.filter { pids.contains($0.processIdentifier) }
for app in apps {
    print("APP \(app.processIdentifier) \(app.localizedName ?? "") policy=\(app.activationPolicy.rawValue) active=\(app.isActive)")
    let root = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 1)
    func walk(_ e: AXUIElement, _ depth: Int) {
        guard depth < 5 else { return }
        var attrs = [String]()
        for key in [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(e, key as CFString, &value) == .success, let value { attrs.append("\(key)=\(value)") }
        }
        print(String(repeating:" ",count:depth)+attrs.joined(separator:" "))
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &children) == .success, let list = children as? [AXUIElement] else { return }
        for child in list.prefix(60) { walk(child, depth+1) }
    }
    walk(root, 0)
}
let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
for row in rows where pids.contains(row[kCGWindowOwnerPID as String] as? Int32 ?? 0) {
    print(row.filter { [kCGWindowOwnerPID,kCGWindowNumber,kCGWindowLayer,kCGWindowBounds,kCGWindowName].map { $0 as String }.contains($0.key) })
}
