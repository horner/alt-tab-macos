import Cocoa

enum ProjectRestoreNotice {
    private typealias Assignment = (windowName: String, projectName: String, differentDesktop: Bool)
    private static var pending = [String: Assignment]()
    private static var queued = [Assignment]()
    private static var showWork: DispatchWorkItem?
    private static var hideWork: DispatchWorkItem?
    private static var panel: NSPanel?

    static func record(windowId: String, windowName: String, projectName: String, differentDesktop: Bool) {
        pending[windowId + "\u{0}" + projectName] = (windowName, projectName, differentDesktop)
        guard showWork == nil else { return }
        let work = DispatchWorkItem { flush() }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private static func flush() {
        showWork = nil
        guard !pending.isEmpty, Projects.isEnabled else { pending.removeAll(); return }
        let assignments = pending.values.sorted { ($0.projectName, $0.windowName) < ($1.projectName, $1.windowName) }
        pending.removeAll()
        queued.append(contentsOf: assignments)
        if hideWork == nil { showNext() }
        Logger.debug { "projects restoration notice assignments=\(assignments.count) differentDesktop=\(assignments.filter { $0.differentDesktop }.count)" }
    }

    private static func showNext() {
        guard !queued.isEmpty, Projects.isEnabled else { queued.removeAll(); return }
        let assignments = Array(queued.prefix(5))
        queued.removeFirst(assignments.count)
        show(assignments)
    }

    private static func show(_ assignments: [Assignment]) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        hideWork?.cancel()
        let window = panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel = window
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        let height = CGFloat(52 + assignments.count * 48)
        let view = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 380, height: height))
        view.material = .hudWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        addLabel(NSLocalizedString("Restored Project assignments", comment: "Project restoration notice"), y: height - 32, bold: true, in: view)
        for (index, assignment) in assignments.enumerated() {
            let y = height - 58 - CGFloat(index * 48)
            addLabel(assignment.windowName, y: y, bold: false, in: view)
            let destination = assignment.differentDesktop
                ? String(format: NSLocalizedString("→ %@ (different Desktop)", comment: "Restored window destination Project"), assignment.projectName)
                : "→ \(assignment.projectName)"
            addLabel(destination, y: y - 20, bold: false, in: view)
        }
        window.contentView = view
        window.setFrame(NSRect(x: screen.visibleFrame.maxX - 400, y: screen.visibleFrame.maxY - height - 20, width: 380, height: height), display: true)
        window.orderFrontRegardless()
        let work = DispatchWorkItem {
            window.orderOut(nil)
            hideWork = nil
            DispatchQueue.main.async { showNext() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private static func addLabel(_ text: String, y: CGFloat, bold: Bool, in view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: bold ? 14 : 12, weight: bold ? .semibold : .regular)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 16, y: y, width: 348, height: 20)
        view.addSubview(label)
    }
}
