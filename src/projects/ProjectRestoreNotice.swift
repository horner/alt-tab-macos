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
    private struct Question {
        let id: String
        let target: WindowTarget
        let pattern: ProjectWindowPattern
        let projectIds: Set<String>
    }
    private static var pending = [String: Assignment]()
    private static var queued = [Assignment]()
    private static var summaries = [Summary]()
    private static var showWork: DispatchWorkItem?
    private static var hideWork: DispatchWorkItem?
    private static var panel: NSPanel?
    private static var isHovered = false
    private static var questions = [String: Question]()
    private static var reviewStarted = false
    private static var reviewing = false

    static func ask(window: Window, pattern: ProjectWindowPattern, projectIds: Set<String>) {
        let id = window.tracked.id
        if let existing = questions[id], existing.target.liveWindow === window,
           ProjectReattachResolver.sameEvidence(existing.pattern, pattern), existing.projectIds == projectIds { return }
        questions[id] = Question(id: id, target: WindowTarget(window), pattern: pattern, projectIds: projectIds)
        if reviewing { refreshReview(); return }
        scheduleShow()
    }

    static func forgetQuestions(for ids: Set<String>) {
        let changed = ids.reduce(false) { (questions.removeValue(forKey: $1) != nil) || $0 }
        if changed && reviewing { refreshReview() }
    }

    private static func refreshReview() {
        DispatchQueue.main.async {
            guard reviewing else { return }
            panel?.orderOut(nil)
            reviewing = false
            DispatchQueue.main.async { showNext() }
        }
    }

    private static func scheduleShow() {
        guard showWork == nil else { return }
        let work = DispatchWorkItem { flush() }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    static func record(window: Window, windowName: String, projectName: String, differentDesktop: Bool) {
        pending[window.tracked.id + "\u{0}" + projectName] = (windowName, projectName, differentDesktop, WindowTarget(window))
        scheduleShow()
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
        guard Projects.isEnabled else { dismiss(); return }
        let assignments = pending.values.sorted { ($0.projectName, $0.windowName) < ($1.projectName, $1.windowName) }
        pending.removeAll()
        queued.append(contentsOf: assignments)
        showNext()
        Logger.debug { "projects restoration notice assignments=\(assignments.count) differentDesktop=\(assignments.filter { $0.differentDesktop }.count)" }
    }

    private static func showNext() {
        guard panel?.isVisible != true else { return }
        guard Projects.isEnabled else { queued.removeAll(); summaries.removeAll(); return }
        questions = questions.filter { $0.value.target.liveWindow != nil }
        if !questions.isEmpty { showQuestions(); return }
        reviewStarted = false
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

    @discardableResult
    private static func show(title: String, rows: [Row], actionHeight: CGFloat = 0) -> NSView? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        reviewing = actionHeight > 0
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
        let height = CGFloat(52 + rows.count * 48) + actionHeight
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
        return view
    }

    private static func showQuestions() {
        let ordered = questions.values.sorted { $0.id < $1.id }
        guard let question = ordered.first else { return }
        if ordered.count > 1 && !reviewStarted {
            let detail = String(format: NSLocalizedString("%d windows match more than one Project.", comment: "Ambiguous restoration count"), ordered.count)
            guard let view = show(title: NSLocalizedString("Review Project assignments", comment: "Ambiguous restoration heading"),
                rows: [Row(title: detail, detail: NSLocalizedString("Choose where each window belongs.", comment: "Ambiguous restoration explanation"))], actionHeight: 40) else { return }
            addAction(NSLocalizedString("Review windows…", comment: "Review ambiguous windows"), y: 14, in: view) {
                reviewStarted = true
                refreshReview()
            }
            return
        }
        let candidates = question.projectIds.compactMap { Projects.byId[$0] }.filter { $0.isCustom }.sorted { $0.resolvedName < $1.resolvedName }
        let displayed = Array(candidates.prefix(3))
        let app = question.target.liveWindow?.application.localizedName ?? question.pattern.bundleIdentifier
        let title = question.target.liveWindow?.title ?? question.pattern.title
        let heading = NSLocalizedString("Which Project for this window?", comment: "Ambiguous restoration question")
        guard let view = show(title: heading, rows: [Row(title: "\(app) — \(title)", detail: question.pattern.url ?? question.pattern.title, target: question.target)],
            actionHeight: CGFloat(92 + displayed.count * 30)) else { return }
        let move = NoticeButton(checkboxWithTitle: NSLocalizedString("Also move to the Project’s Desktop", comment: "Optional desktop move when resolving restoration"), target: nil, action: nil)
        move.frame = NSRect(x: 16, y: 75, width: 348, height: 22)
        move.font = .systemFont(ofSize: 12)
        view.addSubview(move)
        for (index, project) in displayed.enumerated() {
            addAction(project.resolvedName, y: CGFloat(106 + (displayed.count - index - 1) * 30), in: view) {
                finishQuestion(question, project: project, move: move.state == .on)
            }
        }
        let other = NSPopUpButton(frame: NSRect(x: 16, y: 43, width: 348, height: 26), pullsDown: true)
        other.addItem(withTitle: NSLocalizedString("Other Project…", comment: "Choose another Project for a restored window"))
        for project in Projects.list.filter({ $0.isCustom }).sorted(by: { $0.resolvedName < $1.resolvedName }) {
            let item = NSMenuItem(title: project.resolvedName, action: nil, keyEquivalent: "")
            item.representedObject = project
            other.menu?.addItem(item)
        }
        other.onAction = { sender in
            guard let project = (sender as? NSPopUpButton)?.selectedItem?.representedObject as? Project else { return }
            finishQuestion(question, project: project, move: move.state == .on)
        }
        view.addSubview(other)
        addAction(NSLocalizedString("Leave unassigned", comment: "Decline restoration for this window"), y: 13, in: view) {
            finishQuestion(question, project: nil, move: false)
        }
    }

    private static func finishQuestion(_ question: Question, project: Project?, move: Bool) {
        questions.removeValue(forKey: question.id)
        panel?.orderOut(nil)
        reviewing = false
        DispatchQueue.main.async {
            if let window = question.target.liveWindow {
                if let project {
                    Projects.resolveRestoration(window, expected: question.pattern, candidates: question.projectIds, project: project, move: move)
                } else {
                    Projects.declineRestoration(window)
                }
            }
            showNext()
        }
    }

    private static func addAction(_ title: String, y: CGFloat, in view: NSView, action: @escaping () -> Void) {
        let button = NoticeButton(frame: NSRect(x: 16, y: y, width: 348, height: 26))
        button.title = title
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12)
        button.cell?.lineBreakMode = .byTruncatingTail
        button.toolTip = title
        button.onAction = { _ in action() }
        view.addSubview(button)
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
        guard let window = panel, window.isVisible, !isHovered, !reviewing else { return }
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
        for question in questions.values {
            if let window = question.target.liveWindow { Projects.declineRestoration(window) }
        }
        questions.removeAll()
        reviewing = false
        reviewStarted = false
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
