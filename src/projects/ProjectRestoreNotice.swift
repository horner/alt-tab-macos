import Cocoa

enum ProjectRestoreNotice {
    private static var pending = [String: (String, Bool)]()
    private static var showWork: DispatchWorkItem?
    private static var hideWork: DispatchWorkItem?
    private static var panel: NSPanel?

    static func record(windowId: String, projectName: String, differentDesktop: Bool) {
        pending[windowId] = (projectName, differentDesktop)
        guard showWork == nil else { return }
        let work = DispatchWorkItem { flush() }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private static func flush() {
        showWork = nil
        guard !pending.isEmpty, Projects.isEnabled else { pending.removeAll(); return }
        let assignments = pending
        pending.removeAll()
        let grouped = Dictionary(grouping: assignments.values, by: { $0.0 })
        let summary = grouped.keys.sorted().map { "\($0) (\(grouped[$0]!.count))" }.joined(separator: ", ")
        let different = assignments.values.filter { $0.1 }.count
        let detail = different > 0 ? String(format: NSLocalizedString("%d restored on a different Desktop", comment: "Project restoration notice"), different) : ""
        show(summary, detail: detail)
        Logger.debug { "projects restoration notice windows=\(assignments.count) projects=\(summary) differentDesktop=\(different)" }
    }

    private static func show(_ summary: String, detail: String) {
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
        let height: CGFloat = detail.isEmpty ? 84 : 106
        let view = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 380, height: height))
        view.material = .hudWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        addLabel(NSLocalizedString("Restored Project assignments", comment: "Project restoration notice"), y: height - 32, bold: true, in: view)
        addLabel(summary, y: height - 56, bold: false, in: view)
        if !detail.isEmpty { addLabel(detail, y: 14, bold: false, in: view) }
        window.contentView = view
        window.setFrame(NSRect(x: screen.visibleFrame.maxX - 400, y: screen.visibleFrame.maxY - height - 20, width: 380, height: height), display: true)
        window.orderFrontRegardless()
        let work = DispatchWorkItem { window.orderOut(nil) }
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
