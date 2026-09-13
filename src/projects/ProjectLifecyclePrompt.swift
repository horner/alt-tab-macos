import Cocoa

final class ProjectLifecyclePrompt: NSObject, NSWindowDelegate {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private static let shared = ProjectLifecyclePrompt()
    private var observer: NSObjectProtocol?
    private var queued = false
    private var panel: NSPanel?
    private var project: Project?
    private var desktopUuid: String?
    private var targets = [Project]()
    private var destination: NSPopUpButton?
    private var presentationKey = [String]()

    static func start() {
        guard shared.observer == nil else { return }
        shared.observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in refresh() }
    }

    static func refresh() {
        guard !shared.queued else { return }
        shared.queued = true
        DispatchQueue.main.async {
            shared.queued = false
            shared.update()
        }
    }

    static func close(_ project: Project, from window: NSWindow?) {
        guard Projects.isEnabled, Projects.byId[project.id] === project else { return }
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Close %@?", comment: "Close Project confirmation"), project.resolvedName)
        alert.informativeText = NSLocalizedString("The Project will move to the Project Attic. Its name, history and list of open windows are saved for restoring later. Application windows and the Desktop stay open.", comment: "Close Project explanation")
        alert.addButton(withTitle: NSLocalizedString("Close Project", comment: "Archive a Project")).keyEquivalent = ""
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        ProjectPrompt.present(alert, from: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            DispatchQueue.main.async { Projects.close(project) }
        }
    }

    private func update() {
        guard Projects.isEnabled else { panel?.orderOut(nil); return }
        let candidate = Projects.list.first { item in
            item.isCustom && item.pendingDesktopRemoval && Projects.spaces.contains { $0.uuid == item.homeSpaceUuid && $0.desktopNumber > 0 }
        }
        guard let candidate else { dismiss(); return }
        guard MissionControl.state() == .inactive else { panel?.orderOut(nil); return }
        let key = [candidate.resolvedName, String(Projects.spaces.first { $0.uuid == candidate.homeSpaceUuid }?.desktopNumber ?? 0)]
            + combineTargets(for: candidate).flatMap { [$0.id, $0.resolvedName] }
        if project === candidate, desktopUuid == candidate.homeSpaceUuid, presentationKey == key, let panel {
            if !panel.isVisible { panel.orderFrontRegardless() }
            return
        }
        dismiss()
        project = candidate
        desktopUuid = candidate.homeSpaceUuid
        presentationKey = key
        present(candidate)
    }

    private func combineTargets(for project: Project) -> [Project] {
        Projects.list.filter { $0.isCustom && $0 !== project && $0.homeSpaceUuid == project.homeSpaceUuid && !$0.pendingDesktopRemoval }
    }

    private func present(_ project: Project) {
        let number = Projects.spaces.first { $0.uuid == project.homeSpaceUuid }?.desktopNumber ?? 0
        let panel = Panel(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = NSLocalizedString("Project Desktop Closed", comment: "Desktop removal choice window")
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.delegate = self
        let title = NSTextField(wrappingLabelWithString: String(format: NSLocalizedString("%@’s Desktop was closed.", comment: "Desktop removal question"), project.resolvedName))
        title.font = .boldSystemFont(ofSize: 16)
        let detail = NSTextField(wrappingLabelWithString: String(format: NSLocalizedString("%@ is temporarily on Desktop %d. Keep it as a separate Project, close it with its history saved, or combine it with another Project there. Application windows stay open.", comment: "Desktop removal choices"), project.resolvedName, number))
        let keep = NSButton(title: String(format: NSLocalizedString("Keep on Desktop %d", comment: "Keep relocated Project"), number), target: self, action: #selector(keep))
        keep.keyEquivalent = "\r"
        let close = NSButton(title: NSLocalizedString("Close Project…", comment: "Archive a Project with confirmation"), target: self, action: #selector(closeCurrent))
        targets = combineTargets(for: project)
        let choices = NSPopUpButton()
        choices.addItems(withTitles: targets.map { $0.resolvedName })
        choices.setAccessibilityLabel(NSLocalizedString("Combine with Project", comment: "Combine target picker"))
        choices.isEnabled = !targets.isEmpty
        destination = choices
        let combine = NSButton(title: NSLocalizedString("Combine…", comment: "Preview combining Projects"), target: self, action: #selector(combineCurrent))
        combine.isEnabled = !targets.isEmpty
        let label = NSTextField(labelWithString: NSLocalizedString("Combine with", comment: "Combine target label"))
        let targetRow = NSStackView(views: [label, choices, combine])
        targetRow.orientation = .horizontal
        targetRow.spacing = 8
        let buttons = NSStackView(views: [close, keep])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        let content = NSStackView(views: [title, detail, targetRow, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        content.widthAnchor.constraint(equalToConstant: 500).isActive = true
        title.widthAnchor.constraint(equalToConstant: 460).isActive = true
        detail.widthAnchor.constraint(equalToConstant: 460).isActive = true
        panel.contentView = content
        panel.center()
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private var liveProject: Project? {
        guard Projects.isEnabled, let project, Projects.byId[project.id] === project,
              project.pendingDesktopRemoval, project.homeSpaceUuid == desktopUuid,
              Projects.spaces.contains(where: { $0.uuid == desktopUuid && $0.desktopNumber > 0 }) else { return nil }
        return project
    }

    @objc private func keep() {
        guard let project = liveProject else { Self.refresh(); return }
        dismiss()
        DispatchQueue.main.async { Projects.keepAfterDesktopRemoval(project) }
    }

    @objc private func closeCurrent() {
        guard let project = liveProject else { Self.refresh(); return }
        Self.close(project, from: panel)
    }

    @objc private func combineCurrent() {
        guard let project = liveProject, let index = destination?.indexOfSelectedItem, targets.indices.contains(index) else { Self.refresh(); return }
        let target = targets[index]
        guard Projects.byId[target.id] === target, ProjectLifecycleResolver.canCombine(Projects.entry(for: project), into: Projects.entry(for: target)) else { dismiss(); Self.refresh(); return }
        Self.combine(project, into: target, from: panel)
    }

    static func combine(_ project: Project, into target: Project, from window: NSWindow?) {
        guard Projects.isEnabled, Projects.byId[project.id] === project, Projects.byId[target.id] === target,
              ProjectLifecycleResolver.canCombine(Projects.entry(for: project), into: Projects.entry(for: target)) else { return }
        let sourceEntry = Projects.entry(for: project)
        let targetEntry = Projects.entry(for: target)
        let sourceMembers = project.members
        let targetMembers = target.members
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Combine %@ with %@?", comment: "Project combine confirmation"), project.resolvedName, target.resolvedName)
        alert.informativeText = String(format: NSLocalizedString("Open windows: %d. Saved history entries: %d.\n\nCombine %@ into %@, skipping duplicates. %@ will move to the Project Attic with its original history saved. Application windows stay open and remain on their current Desktops.", comment: "Project combine preview"), sourceMembers.count, sourceEntry.windowHistory.count, project.resolvedName, target.resolvedName, project.resolvedName)
        alert.addButton(withTitle: NSLocalizedString("Combine Projects", comment: "Confirm combining Projects")).keyEquivalent = ""
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        ProjectPrompt.present(alert, from: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            DispatchQueue.main.async {
                guard Projects.isEnabled, Projects.byId[project.id] === project, Projects.byId[target.id] === target else { return }
                guard Projects.entry(for: project) == sourceEntry, Projects.entry(for: target) == targetEntry,
                      project.members == sourceMembers, target.members == targetMembers else {
                    combine(project, into: target, from: window)
                    return
                }
                Projects.combine(project, into: target)
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        keep()
        return false
    }

    private func dismiss() {
        if let sheet = panel?.attachedSheet { panel?.endSheet(sheet, returnCode: .abort) }
        panel?.orderOut(nil)
        panel = nil
        project = nil
        desktopUuid = nil
        presentationKey.removeAll()
        targets.removeAll()
        destination = nil
    }
}
