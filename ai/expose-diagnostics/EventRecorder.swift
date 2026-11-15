import Cocoa
import ApplicationServices
import ObjectiveC
import Darwin

let output = FileHandle.standardOutput
func record(_ event: String, _ fields: [String: Any] = [:]) {
    var row = fields
    row["event"] = event
    row["time"] = ISO8601DateFormatter().string(from: Date())
    guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
    output.write(data)
    output.write(Data([10]))
}
let targetPid = Int32(CommandLine.arguments.dropFirst().first ?? "0") ?? 0
func snapshot(_ reason: String) {
    let front = NSWorkspace.shared.frontmostApplication
    let rows = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []).filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == targetPid
    }.map { row in
        Dictionary(uniqueKeysWithValues: [kCGWindowNumber, kCGWindowLayer, kCGWindowAlpha, kCGWindowIsOnscreen, kCGWindowBounds].compactMap { key -> (String, Any)? in
            guard let value = row[key as String] else { return nil }
            return (key as String, value)
        })
    }
    let app = NSRunningApplication(processIdentifier: targetPid)
    record("snapshot", ["reason": reason, "frontPid": front?.processIdentifier ?? 0,
        "frontBundle": front?.bundleIdentifier ?? "", "targetPolicy": app?.activationPolicy.rawValue ?? -1,
        "targetActive": app?.isActive ?? false, "windows": rows])
}
let workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
    record("activation", ["pid": app.processIdentifier, "bundle": app.bundleIdentifier ?? "", "policy": app.activationPolicy.rawValue])
}
var dockObserver: AXObserver?
if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
    let result = AXObserverCreate(dock.processIdentifier, { _, _, name, _ in
        snapshot(name as String)
    }, &dockObserver)
    record("dockObserver", ["result": result.rawValue])
    if let observer = dockObserver {
        for name in ["AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeShowDesktop", "AXExposeExit"] {
            let result = AXObserverAddNotification(observer, AXUIElementCreateApplication(dock.processIdentifier), name as CFString, nil)
            record("subscribe", ["name": name, "result": result.rawValue])
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
}
let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW | RTLD_LOCAL)!
let copyHID = unsafeBitCast(dlsym(sky, "SLEventCopyIOHIDEvent")!, to: (@convention(c) (CGEvent) -> Unmanaged<AnyObject>?).self)
var lastPhases = [String: UInt32]()
func dockSwipe(_ stage: String, _ event: CGEvent) {
    guard let object = copyHID(event)?.takeRetainedValue() as? NSObject else { return }
    let optionsSelector = NSSelectorFromString("options")
    let typeSelector = NSSelectorFromString("type")
    let integerSelector = NSSelectorFromString("integerValueForField:")
    let doubleSelector = NSSelectorFromString("doubleValueForField:")
    guard [optionsSelector, typeSelector, integerSelector, doubleSelector].allSatisfy({ object.responds(to: $0) }) else { return }
    let getType = unsafeBitCast(object.method(for: typeSelector), to: (@convention(c) (AnyObject, Selector) -> UInt32).self)
    guard getType(object, typeSelector) == 23 else { return }
    let getOptions = unsafeBitCast(object.method(for: optionsSelector), to: (@convention(c) (AnyObject, Selector) -> UInt32).self)
    let phase = (getOptions(object, optionsSelector) >> 24) & 0xff
    guard lastPhases[stage] != phase else { return }
    lastPhases[stage] = phase
    let getInteger = unsafeBitCast(object.method(for: integerSelector), to: (@convention(c) (AnyObject, Selector, UInt32) -> Int).self)
    let getDouble = unsafeBitCast(object.method(for: doubleSelector), to: (@convention(c) (AnyObject, Selector, UInt32) -> Double).self)
    record("dockSwipe", ["stage": stage, "phase": phase, "motion": getInteger(object, integerSelector, (23 << 16) | 1), "progress": getDouble(object, doubleSelector, (23 << 16) | 2)])
    if stage == "session", phase == 1 { snapshot("before-swipe") }
}
var counts = [String: Int]()
var lastTouches = [String: Int]()
var finish: DispatchWorkItem?
var taps = [CFMachPort]()
func handle(_ stage: String, _ type: CGEventType, _ event: CGEvent) {
    if type == .keyDown {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard (key == 125 && event.flags.contains(.maskControl)) || key == 53 else { return }
        record("control", ["stage": stage, "key": key == 125 ? "control-down" : "escape"])
        if stage == "hid" { snapshot("before-key") }
        return
    }
    if type.rawValue == 30 { dockSwipe(stage, event); return }
    guard type.rawValue == 29 else { return }
    counts[stage, default: 0] += 1
    if let ns = NSEvent(cgEvent: event) {
        let touches = ns.allTouches()
        let down = touches.filter { $0.phase == .began || $0.phase == .moved || $0.phase == .stationary }.count
        if lastTouches[stage] != down {
            lastTouches[stage] = down
            record("fingers", ["stage": stage, "down": down])
        }
    }
    finish?.cancel()
    let work = DispatchWorkItem {
        record("gestureBatch", ["counts": counts])
        counts.removeAll()
        lastTouches.removeAll()
    }
    finish = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
}
let mask = (CGEventMask(1) << 30) | (CGEventMask(1) << 29) | (CGEventMask(1) << CGEventType.keyDown.rawValue)
for (stage, location) in [("hid", CGEventTapLocation.cghidEventTap), ("session", .cgAnnotatedSessionEventTap)] {
    let context = Unmanaged.passRetained(stage as NSString).toOpaque()
    if let tap = CGEvent.tapCreate(tap: location, place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
        let stage = Unmanaged<NSString>.fromOpaque(context!).takeUnretainedValue() as String
        handle(stage, type, event)
        return Unmanaged.passUnretained(event)
    }, userInfo: context) {
        taps.append(tap)
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        record("tap", ["stage": stage, "created": true])
    } else { record("tap", ["stage": stage, "created": false]) }
}
record("ready", ["trusted": AXIsProcessTrusted(), "targetPid": targetPid])
snapshot("startup")
RunLoop.main.run()
