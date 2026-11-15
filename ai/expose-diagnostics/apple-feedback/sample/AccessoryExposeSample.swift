import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows = [NSWindow]()
    private let modeLabel = NSTextField(labelWithString: "Activation policy: accessory")
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        for index in 0..<2 { addWindow(index) }
        windows[0].makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func installMenu() {
        let menu = NSMenu()
        let item = NSMenuItem()
        let submenu = NSMenu(title: "AccessoryExposeSample")
        submenu.addItem(withTitle: "Quit AccessoryExposeSample", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu
        menu.addItem(item)
        NSApp.mainMenu = menu
    }
    private func addWindow(_ index: Int) {
        let window = NSWindow(contentRect: NSRect(x: 100 + index * 480, y: 240, width: 460, height: 280), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Accessory Exposé Sample \(index + 1)"
        window.isReleasedWhenClosed = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 16
        stack.frame = NSRect(x: 20, y: 20, width: 420, height: 240)
        if index == 0 {
            stack.addArrangedSubview(modeLabel)
            stack.addArrangedSubview(NSButton(title: "Use accessory mode", target: self, action: #selector(useAccessoryMode)))
            stack.addArrangedSubview(NSButton(title: "Use regular mode", target: self, action: #selector(useRegularMode)))
        } else {
            stack.addArrangedSubview(NSTextField(labelWithString: "Second ordinary titled window"))
        }
        let reminder = NSTextField(wrappingLabelWithString: "Before each test, click another regular app, then click this window. After changing modes, repeat that activation sequence. Compare a downward App Exposé swipe with Control–Down.")
        reminder.preferredMaxLayoutWidth = 400
        stack.addArrangedSubview(reminder)
        window.contentView?.addSubview(stack)
        windows.append(window)
        window.orderFront(nil)
    }
    @objc private func useAccessoryMode() { setPolicy(.accessory) }
    @objc private func useRegularMode() { setPolicy(.regular) }
    private func setPolicy(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.setActivationPolicy(policy) else {
            modeLabel.stringValue = "Activation policy change failed"
            return
        }
        modeLabel.stringValue = policy == .accessory ? "Activation policy: accessory" : "Activation policy: regular"
        windows[0].makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
