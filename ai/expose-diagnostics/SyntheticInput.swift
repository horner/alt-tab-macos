import Cocoa
import ObjectiveC
import Darwin

func fail(_ text: String) -> Never {
    fputs(text + "\n", stderr)
    exit(1)
}
let args = Array(CommandLine.arguments.dropFirst())
guard let mode = args.first, ["swipe", "key", "check", "activate"].contains(mode) else { fail("Usage: input check | activate <pid> | key down/escape | swipe <signed-progress> [3|4]") }
let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
guard session["CGSSessionScreenIsLocked"] as? Bool != true else { fail("Screen is locked; no input posted") }
guard AXIsProcessTrusted() else { fail("Accessibility unavailable; no input posted") }
if mode == "check" { print("unlocked; accessibility available"); exit(0) }
if mode == "activate" {
    guard args.count == 2, let pid = Int32(args[1]), pid > 0, let app = NSRunningApplication(processIdentifier: pid) else { fail("Unknown PID") }
    print("activation-request=\(app.activate(options: [.activateIgnoringOtherApps])) pid=\(pid)")
    exit(0)
}
if mode == "key" {
    guard args.count == 2, ["down", "escape"].contains(args[1]) else { fail("Specify down or escape") }
    let down = args[1] == "down"
    let code: CGKeyCode = down ? 125 : 53
    let source = CGEventSource(stateID: .hidSystemState)
    if down, let control = CGEvent(keyboardEventSource: source, virtualKey: 59, keyDown: true) {
        control.type = .flagsChanged
        control.flags = .maskControl
        control.post(tap: .cghidEventTap)
        usleep(30000)
    }
    for pressed in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: pressed) else { fail("Could not create keyboard event") }
        event.flags = down ? [.maskControl, .maskSecondaryFn, .maskNumericPad] : []
        event.post(tap: .cghidEventTap)
        usleep(30000)
    }
    if down, let control = CGEvent(keyboardEventSource: source, virtualKey: 59, keyDown: false) {
        control.type = .flagsChanged
        control.flags = []
        control.post(tap: .cghidEventTap)
    }
    print("posted \(args[1])")
    exit(0)
}
guard (2...3).contains(args.count), let progress = Double(args[1]), progress.isFinite, abs(progress) <= 3, progress != 0 else { fail("Swipe progress must be nonzero within -3...3") }
guard args.count == 2 || ["3", "4"].contains(args[2]) else { fail("Gesture flavor must be 3 or 4") }
guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW | RTLD_LOCAL),
      let pointer = dlsym(handle, "SLEventSetIOHIDEvent"), let hidClass = NSClassFromString("HIDEvent") else { fail("HID event API unavailable") }
let setHID = unsafeBitCast(pointer, to: (@convention(c) (CGEvent, AnyObject) -> Void).self)
func method(_ object: AnyObject, _ name: String) -> IMP {
    guard let cls = object_getClass(object), let method = class_getInstanceMethod(cls, NSSelectorFromString(name)) else { fail("Missing method \(name)") }
    return method_getImplementation(method)
}
func makeHID(_ type: UInt32) -> AnyObject {
    let selector = NSSelectorFromString("alloc")
    guard let m = class_getClassMethod(hidClass, selector) else { fail("Missing alloc") }
    let alloc = unsafeBitCast(method_getImplementation(m), to: (@convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>).self)
    let object = alloc(hidClass, selector).takeUnretainedValue()
    let name = "initWithType:timestamp:senderID:"
    let initialize = unsafeBitCast(method(object, name), to: (@convention(c) (AnyObject, Selector, UInt32, UInt64, UInt64) -> Unmanaged<AnyObject>?).self)
    guard let result = initialize(object, NSSelectorFromString(name), type, 0, 0) else { fail("HID initialization failed") }
    return result.takeRetainedValue()
}
func integer(_ object: AnyObject, _ value: Int, _ field: UInt32) {
    let name = "setIntegerValue:forField:"
    let fn = unsafeBitCast(method(object, name), to: (@convention(c) (AnyObject, Selector, Int, UInt32) -> Void).self)
    fn(object, NSSelectorFromString(name), value, field)
}
func double(_ object: AnyObject, _ value: Double, _ field: UInt32) {
    let name = "setDoubleValue:forField:"
    let fn = unsafeBitCast(method(object, name), to: (@convention(c) (AnyObject, Selector, Double, UInt32) -> Void).self)
    fn(object, NSSelectorFromString(name), value, field)
}
func post(_ phase: UInt32, _ value: Double) {
    let hid = makeHID(23)
    let name = "setOptions:"
    let options = unsafeBitCast(method(hid, name), to: (@convention(c) (AnyObject, Selector, UInt32) -> Void).self)
    options(hid, NSSelectorFromString(name), phase << 24)
    integer(hid, 2, (23 << 16) | 1)
    integer(hid, args.count == 3 ? (Int(args[2]) ?? 3) : 3, (23 << 16) | 5)
    double(hid, value, (23 << 16) | 2)
    if phase == 4 {
        let velocity = makeHID(9)
        double(velocity, 0, 9 << 16)
        double(velocity, progress / 0.3, (9 << 16) | 1)
        double(velocity, 0, (9 << 16) | 2)
        let append = "appendEvent:"
        let fn = unsafeBitCast(method(hid, append), to: (@convention(c) (AnyObject, Selector, AnyObject) -> Void).self)
        fn(hid, NSSelectorFromString(append), velocity)
    }
    guard let event = CGEvent(source: nil) else { fail("CGEvent allocation failed") }
    event.type = CGEventType(rawValue: 30)!
    setHID(event, hid)
    event.post(tap: .cgSessionEventTap)
}
post(1, progress / 30)
for step in 2...30 {
    usleep(10000)
    post(2, progress * Double(step) / 30)
}
post(4, progress)
print("posted vertical Dock swipe progress=\(progress)")
