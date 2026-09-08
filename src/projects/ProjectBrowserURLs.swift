import Cocoa

enum ProjectBrowserURLs {
    private static var finished = Set<String>()
    private static var urls = [String: String]()
    private static var dirty = Set<String>()
    private static var waiting = [String: [() -> Void]]()

    static func url(for window: Window) -> String? { urls[window.tracked.id] }

    static func isReady(_ window: Window) -> Bool {
        !ProjectBrowserURLResolver.supports(window.application.bundleIdentifier) || finished.contains(window.tracked.id)
    }

    static func refresh(wid: CGWindowID) {
        DispatchQueue.main.async {
            guard let window = Windows.byWindowId[wid] else { return }
            refresh(window)
        }
    }

    static func forget(_ windows: [Window]) {
        for window in windows { urls.removeValue(forKey: window.tracked.id); finished.remove(window.tracked.id) }
    }

    static func refresh(_ window: Window, then completion: (() -> Void)? = nil) {
        guard Projects.isEnabled, ProjectBrowserURLResolver.supports(window.application.bundleIdentifier), let element = window.axUiElement else { completion?(); return }
        let id = window.tracked.id
        if waiting[id] != nil {
            dirty.insert(id)
            if let completion { waiting[id]?.append(completion) }
            return
        }
        waiting[id] = completion.map { [$0] } ?? []
        AXCallScheduler.shared.schedule(key: "project-url-\(id)", pid: window.application.pid) { [weak window] in
            let url = read(element)
            DispatchQueue.main.async {
                let callbacks = waiting.removeValue(forKey: id) ?? []
                let needsRefresh = dirty.remove(id) != nil
                guard let window, Windows.list.contains(where: { $0 === window }) else { return }
                finished.insert(id)
                let changed = urls[id] != url
                urls[id] = url
                if changed {
                    Logger.debug { "projects browser URL window=\(id) available=\(url != nil)" }
                    Projects.browserURLUpdated(window, restoreIfUnassigned: callbacks.isEmpty)
                }
                callbacks.forEach { $0() }
                if needsRefresh { refresh(window) }
            }
        }
    }

    // Read document metadata only. Do not inspect address-bar text (it may be an unsubmitted edit)
    // or traverse inside web content, where links and frames have unrelated URLs.
    private static func read(_ window: AXUIElement) -> String? {
        if let url = documentURL(window) { return url }
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var index = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        while index < queue.count && index < 80 && ProcessInfo.processInfo.systemUptime < deadline {
            let (element, depth) = queue[index]
            index += 1
            let role = value(element, kAXRoleAttribute) as? String
            if role == "AXWebArea" { return documentURL(element) }
            guard depth < 8, ![kAXButtonRole, kAXTextFieldRole, kAXStaticTextRole, "AXLink"].contains(role ?? "") else { continue }
            if let children = value(element, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(max(0, 80 - queue.count)).map { ($0, depth + 1) })
            }
        }
        return nil
    }

    private static func documentURL(_ element: AXUIElement) -> String? {
        for key in [kAXDocumentAttribute, kAXURLAttribute] {
            let raw = value(element, key)
            if let url = raw as? URL, let normalized = ProjectBrowserURLResolver.normalized(url.absoluteString) { return normalized }
            if let text = raw as? String, let normalized = ProjectBrowserURLResolver.normalized(text) { return normalized }
        }
        return nil
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
}
