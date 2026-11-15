import Cocoa

final class Delegate: NSObject, NSApplicationDelegate {
    var windows = [NSWindow]()
    var helpers = [NSWindow]()
    let modeLabel = NSTextField(labelWithString: "")
    let log: FileHandle = {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alttab-expose-investigation")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("mode-probe-\(ProcessInfo.processInfo.processIdentifier).jsonl").path
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        let file = FileHandle(forWritingAtPath: path)!
        file.seekToEndOfFile()
        return file
    }()
    func record(_ name: String) {
        let value: [String: Any] = ["time": ISO8601DateFormatter().string(from: Date()), "event": name,
            "policy": NSApp.activationPolicy().rawValue, "active": NSApp.isActive,
            "key": NSApp.keyWindow?.windowNumber ?? -1, "main": NSApp.mainWindow?.windowNumber ?? -1,
            "windows": NSApp.windows.map { ["number": $0.windowNumber, "behavior": $0.collectionBehavior.rawValue, "visible": $0.isVisible] as [String: Any] }]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        log.write(data)
        log.write(Data([10]))
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        let submenu = NSMenu(title: "ExposeProbe")
        submenu.addItem(withTitle: "Quit ExposeProbe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        for index in 0..<2 {
            let window = NSWindow(contentRect: NSRect(x: 160 + index * 440, y: 240, width: 420, height: 240), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Exposé Probe \(index + 1)"
            window.isReleasedWhenClosed = false
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.spacing = 16
            stack.frame = NSRect(x: 20, y: 20, width: 380, height: 200)
            if index == 0 {
                stack.addArrangedSubview(modeLabel)
                for (title, action) in [("Use accessory mode", #selector(accessory)), ("Use normal mode", #selector(regular)), ("Add managed helpers", #selector(addHelpers)), ("Exclude helpers from Exposé", #selector(excludeHelpers))] {
                    stack.addArrangedSubview(NSButton(title: title, target: self, action: action))
                }
            } else { stack.addArrangedSubview(NSTextField(labelWithString: "Second ordinary titled window")) }
            window.contentView?.addSubview(stack)
            windows.append(window)
            window.orderFront(nil)
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in self?.record(note.name.rawValue) }
        }
        modeLabel.stringValue = "Accessory app — no AltTab gesture handler"
        windows[0].makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        record("launch")
    }
    @objc func accessory() { setPolicy(.accessory) }
    @objc func regular() { setPolicy(.regular) }
    func setPolicy(_ policy: NSApplication.ActivationPolicy) {
        let success = NSApp.setActivationPolicy(policy)
        modeLabel.stringValue = policy == .accessory ? "Accessory app — no AltTab gesture handler" : "Normal app — no AltTab gesture handler"
        windows[0].makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        record("set-policy-\(success)")
    }
    @objc func addHelpers() {
        guard helpers.isEmpty else { return }
        for _ in 0..<3 {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 2, height: 2), styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.managed, .ignoresCycle]
            window.isExcludedFromWindowsMenu = true
            window.setAccessibilitySubrole(.floatingWindow)
            window.orderBack(nil)
            helpers.append(window)
        }
        record("managed-helpers")
    }
    @objc func excludeHelpers() {
        helpers.forEach { $0.collectionBehavior = [.stationary, .ignoresCycle] }
        record("stationary-helpers")
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Delegate()
app.delegate = delegate
app.run()
