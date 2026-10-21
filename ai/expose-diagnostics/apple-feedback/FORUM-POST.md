# App Exposé swipe and Control–Down differ for accessory apps on macOS 27

On macOS 27.0 (26A428), Apple silicon, a physical four-finger App Exposé swipe does not expose my active AppKit accessory application's windows, including its Settings window. Control–Down does. Filed as `FB24919003`.

I narrowed the behavior down with a two-window AppKit probe and a main menu. In an automated comparison using the same synthetic system gesture sequence each time, `.accessory` selected the previously active regular application's windows, `.regular` selected the probe's windows, and switching back to `.accessory` restored the mismatch. A separately generated Control–Down selected the accessory probe correctly. I activated the other regular app and then reactivated the probe before each comparison.

The probe comparison did not test physical finger recognition. The macOS release that introduced this behavior is unconfirmed. The sample below uses only public AppKit APIs and is simplified from the tested probe; it compiles but has not yet been live-tested. It has no gesture recognizers, event taps, global shortcuts, custom window subclasses, or AltTab implementation.

Steps for a physical-trackpad comparison:

1. Enable the four-finger downward App Exposé gesture and Control–Down for Application windows in System Settings.
2. Launch the sample in accessory mode and leave both windows open.
3. Click another regular app's window, then click the sample's first window.
4. Swipe down. Record which app's windows appear, then press Escape.
5. Repeat the other-app → sample activation sequence, press Control–Down, record the result, then press Escape.
6. Choose **Use regular mode**, repeat the activation sequence, and test again.
7. Choose **Use accessory mode**, repeat the activation sequence, and test again.

Start each invocation with App Exposé closed. Reactivation after each mode change matters for the comparison.

Apple's [window-management guide](https://support.apple.com/en-ge/guide/mac-help/mh35798/mac) presents the swipe and Control–Down as ways to show the current app's windows. Is there a supported configuration that makes an accessory app participate in the gesture path while preserving `.accessory` and avoiding a Dock icon? Has anyone compared this on macOS 26 and 27?

The Feedback report contains the exact tested probe as well as this simplified source. Here is the complete simplified sample, using only public AppKit APIs. Save it as `AccessoryExposeSample.swift`:

```swift
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
```

To build a standalone app bundle with a matching Swift compiler and macOS SDK selected:

```sh
mkdir -p AccessoryExposeSample.app/Contents/MacOS
"$(xcrun --find swiftc)" -swift-version 5 -sdk "$(xcrun --sdk macosx --show-sdk-path)" AccessoryExposeSample.swift -o AccessoryExposeSample.app/Contents/MacOS/AccessoryExposeSample
cat > AccessoryExposeSample.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.apple-feedback.accessory-expose-sample</string>
<key>CFBundleExecutable</key><string>AccessoryExposeSample</string>
<key>CFBundleName</key><string>AccessoryExposeSample</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
open AccessoryExposeSample.app
```
