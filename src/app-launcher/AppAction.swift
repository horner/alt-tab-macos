import Cocoa
import ApplicationServices

final class AppAction {
    private let item: AppCatalogItem
    private let completion: (String?) -> Void
    private var launchObservation: NSKeyValueObservation?
    private var submitted = false
    private var finished = false

    private init(_ item: AppCatalogItem, completion: @escaping (String?) -> Void) {
        self.item = item
        self.completion = completion
    }

    static func perform(_ item: AppCatalogItem, completion: @escaping (String?) -> Void) {
        let action = AppAction(item, completion: completion)
        action.start()
    }

    private func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [self] in
            finish(NSLocalizedString("The application did not respond. Check whether it completed the action before trying again.", comment: "App picker timeout"))
        }
        AXCallScheduler.shared.submit { [self] in
            guard FileManager.default.fileExists(atPath: item.url.path) else {
                DispatchQueue.main.async { self.finish(NSLocalizedString("The application is no longer available.", comment: "App picker error")) }
                return
            }
            if #available(macOS 10.15, *) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: item.url, configuration: configuration) { app, error in
                    DispatchQueue.main.async { self.opened(app, error: error) }
                }
            } else {
                do {
                    let app = try NSWorkspace.shared.launchApplication(at: item.url, options: [], configuration: [:])
                    DispatchQueue.main.async { self.opened(app, error: nil) }
                } catch {
                    DispatchQueue.main.async { self.opened(nil, error: error) }
                }
            }
        }
    }

    private func opened(_ application: NSRunningApplication?, error: Error?) {
        guard !finished else { return }
        guard let application else {
            finish(error?.localizedDescription ?? NSLocalizedString("The application could not be opened.", comment: "App picker error"))
            return
        }
        guard item.action != .open else { finish(nil); return }
        launchObservation = application.observe(\.isFinishedLaunching, options: [.initial, .new]) { [weak self] app, _ in
            DispatchQueue.main.async { self?.createWhenReady(app) }
        }
    }

    private func createWhenReady(_ application: NSRunningApplication) {
        guard !finished, !submitted, application.isFinishedLaunching else { return }
        submitted = true
        launchObservation = nil
        // Creation is non-idempotent: schedule() retries timed-out AX calls, while submit() runs once.
        AXCallScheduler.shared.submit { [self] in
            let result = pressCreationMenu(application.processIdentifier)
            DispatchQueue.main.async { self.finish(result) }
        }
    }

    private func pressCreationMenu(_ pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let menu: AXUIElement = attribute(app, kAXMenuBarAttribute) else { return unavailableCommand }
        let topLevel: [AXUIElement] = attribute(menu, kAXChildrenAttribute) ?? []
        for item in topLevel {
            let menus: [AXUIElement] = attribute(item, kAXChildrenAttribute) ?? []
            for submenu in menus {
                if let command = creationCommand(in: submenu) {
                    let result = AXUIElementPerformAction(command, kAXPressAction as CFString)
                    guard result == .success else {
                        return result == .cannotComplete
                            ? NSLocalizedString("The application did not confirm the action. Check it before trying again.", comment: "App picker error")
                            : unavailableCommand
                    }
                    return nil
                }
            }
        }
        return unavailableCommand
    }

    private func creationCommand(in menu: AXUIElement) -> AXUIElement? {
        let children: [AXUIElement] = attribute(menu, kAXChildrenAttribute) ?? []
        return children.first { child in
            let identifier: String = attribute(child, kAXIdentifierAttribute) ?? ""
            let title: String = attribute(child, kAXTitleAttribute) ?? ""
            let enabled: Bool = attribute(child, kAXEnabledAttribute) ?? false
            return enabled && AppPickerResolver.isCreationMenu(item.action, identifier: identifier, title: title)
        }
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private var unavailableCommand: String {
        String(format: NSLocalizedString("%@ could not perform %@. Its menu command may be unavailable.", comment: "App picker error"), item.name, item.action.title)
    }

    private func finish(_ error: String?) {
        guard !finished else { return }
        finished = true
        launchObservation = nil
        completion(error)
    }
}
