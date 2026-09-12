import Cocoa

enum ProjectRestoreNotice {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private class NoticeButton: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private final class WindowButton: NoticeButton {
        override func resetCursorRects() {
            guard isEnabled else { return }
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    /// A result targets the original live object, never a replacement reusing its window ID.
    final class WindowTarget {
        private weak var window: Window?

        init(_ window: Window) { self.window = window }

        var liveWindow: Window? {
            ProjectMenuResolver.liveTarget(window, in: Windows.list) {
                !$0.isWindowlessApp && !$0.isPhantom && $0.cgWindowId != nil
            }
        }
    }

    struct Row {
        let title: String
        let detail: String
        var target: WindowTarget? = nil
    }

    private final class ContentView: NSVisualEffectView {
        private var hoverArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
            hoverArea = area
            addTrackingArea(area)
            refreshHover()
        }

        override func mouseEntered(with event: NSEvent) { setHovered(true, for: self) }
        override func mouseExited(with event: NSEvent) { setHovered(false, for: self) }

        func refreshHover() {
            guard let window, window.isVisible, window.contentView === self else { return }
            setHovered(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)), for: self)
        }
    }

    private typealias Assignment = (windowName: String, projectName: String, differentDesktop: Bool, target: WindowTarget)
    private typealias Summary = (title: String, rows: [Row])
    private static var pending = [String: Assignment]()
    private static var queued = [Assignment]()
    private static var summaries = [Summary]()
    private static var showWork: DispatchWorkItem?
    private static var hideWork: DispatchWorkItem?
    private static var panel: NSPanel?
    private static var isHovered = false

    static func record(window: Window, windowName: String, projectName: String, differentDesktop: Bool) {
        pending[window.tracked.id + "\u{0}" + projectName] = (windowName, projectName, differentDesktop, WindowTarget(window))
        guard showWork == nil else { return }
        let work = DispatchWorkItem { flush() }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    static func showSummary(title: String, rows: [Row]) {
        let pageCount = (rows.count + 4) / 5
        for start in stride(from: 0, to: rows.count, by: 5) {
            let heading = pageCount > 1
                ? String(format: NSLocalizedString("%@ (%d/%d)", comment: "Restoration notice page"), title, start / 5 + 1, pageCount)
                : title
            summaries.append((heading, Array(rows[start..<min(start + 5, rows.count)])))
        }
        showNext()
    }

    private static func flush() {
        showWork = nil
        guard !pending.isEmpty, Projects.isEnabled else { pending.removeAll(); return }
        let assignments = pending.values.sorted { ($0.projectName, $0.windowName) < ($1.projectName, $1.windowName) }
        pending.removeAll()
        queued.append(contentsOf: assignments)
        showNext()
        Logger.debug { "projects restoration notice assignments=\(assignments.count) differentDesktop=\(assignments.filter { $0.differentDesktop }.count)" }
    }

    private static func showNext() {
        guard panel?.isVisible != true else { return }
        guard Projects.isEnabled else { queued.removeAll(); summaries.removeAll(); return }
        if !summaries.isEmpty {
            let summary = summaries.removeFirst()
            show(title: summary.title, rows: summary.rows)
            return
        }
        guard !queued.isEmpty else { return }
        let assignments = Array(queued.prefix(5))
        queued.removeFirst(assignments.count)
        show(assignments)
    }

    private static func show(_ assignments: [Assignment]) {
        let rows = assignments.map { assignment in
            Row(title: assignment.windowName, detail: assignment.differentDesktop
                ? String(format: NSLocalizedString("→ %@ (different Desktop)", comment: "Restored window destination Project"), assignment.projectName)
                : "→ \(assignment.projectName)", target: assignment.target)
        }
        show(title: NSLocalizedString("Restored Project assignments", comment: "Project restoration notice"), rows: rows)
    }

    private static func show(title: String, rows: [Row]) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        hideWork?.cancel()
        let window = panel ?? Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel = window
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        let height = CGFloat(52 + rows.count * 48)
        let view = ContentView(frame: NSRect(x: 0, y: 0, width: 380, height: height))
        view.material = .hudWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        addLabel(title, y: height - 32, bold: true, in: view)
        addCloseButton(in: view)
        for (index, row) in rows.enumerated() {
            let y = height - 58 - CGFloat(index * 48)
            if let target = row.target {
                addWindowLink(row.title, target: target, y: y, in: view)
            } else {
                addLabel(row.title, y: y, bold: false, in: view)
            }
            addLabel(row.detail, y: y - 20, bold: false, in: view)
        }
        window.contentView = view
        window.setFrame(NSRect(x: screen.visibleFrame.maxX - 400, y: screen.visibleFrame.maxY - height - 20, width: 380, height: height), display: true)
        window.orderFrontRegardless()
        isHovered = false
        view.refreshHover()
        scheduleHide(after: 4)
    }

    private static func setHovered(_ hovered: Bool, for view: NSView) {
        guard panel?.isVisible == true, panel?.contentView === view else { return }
        guard isHovered != hovered else { return }
        isHovered = hovered
        scheduleHide(after: 2)
    }

    private static func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        hideWork = nil
        guard let window = panel, window.isVisible, !isHovered else { return }
        let work = DispatchWorkItem {
            guard window.isVisible, !isHovered else { return }
            window.orderOut(nil)
            hideWork = nil
            DispatchQueue.main.async { showNext() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func dismiss() {
        hideWork?.cancel()
        hideWork = nil
        showWork?.cancel()
        showWork = nil
        pending.removeAll()
        queued.removeAll()
        summaries.removeAll()
        panel?.orderOut(nil)
        isHovered = false
    }

    private static func addCloseButton(in view: NSView) {
        let button = NoticeButton(frame: NSRect(x: view.bounds.width - 36, y: view.bounds.height - 34, width: 24, height: 24))
        button.image = NSImage(named: NSImage.stopProgressTemplateName)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.toolTip = NSLocalizedString("Close notification", comment: "Dismiss the Project restoration notice")
        button.setAccessibilityLabel(button.toolTip)
        button.onAction = { _ in dismiss() }
        view.addSubview(button)
    }

    private static func addWindowLink(_ title: String, target: WindowTarget, y: CGFloat, in view: NSView) {
        let button = WindowButton(frame: NSRect(x: 16, y: y, width: 348, height: 20))
        button.isBordered = false
        button.alignment = .left
        button.cell?.lineBreakMode = .byTruncatingTail
        button.isEnabled = target.liveWindow != nil
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: button.isEnabled ? NSColor.linkColor : NSColor.secondaryLabelColor,
            .underlineStyle: button.isEnabled ? NSUnderlineStyle.single.rawValue : 0])
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(NSLocalizedString("Focus this window", comment: "Restoration result window link"))
        button.onAction = { sender in
            guard target.liveWindow != nil else { sender.isEnabled = false; return }
            dismiss()
            // Let the notice dismissal commit before the focus path can issue IPC.
            DispatchQueue.main.async { target.liveWindow?.focus() }
        }
        view.addSubview(button)
    }

    private static func addLabel(_ text: String, y: CGFloat, bold: Bool, in view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: bold ? 14 : 12, weight: bold ? .semibold : .regular)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = text
        label.frame = NSRect(x: 16, y: y, width: bold ? 320 : 348, height: 20)
        view.addSubview(label)
    }
}
