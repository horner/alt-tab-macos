import Cocoa

/// Main-thread coordinator. A durable snapshot precedes every close request; only observed destruction
/// advances the sequence, so an unsaved-document sheet cannot be mistaken for a successful close.
enum DesktopArchive {
    private final class Session: NSObject {
        let space: SpaceItem
        let mode: ProjectArchivePolicy.Mode
        let projects: [Project]
        let entries: [ProjectEntry]
        let windows: [Window]
        var snapshot: ProjectArchiveSnapshot
        var directories = [URL]()
        var remaining: ArraySlice<Window>
        var waiting: Window?
        var timer: DispatchWorkItem?
        var finishing = false
        let cancellation = ProjectArchiveCancellation()
        private let progress = NSPanel(contentRect: .zero, styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        private let detail = NSTextField(wrappingLabelWithString: "Saving the visual snapshot…")
        private let stop = NSButton(title: "Stop Closing", target: nil, action: nil)

        init(space: SpaceItem, projects: [Project], windows: [Window], mode: ProjectArchivePolicy.Mode) {
            self.space = space
            self.mode = mode
            self.projects = projects
            entries = projects.map { mode == .archiveAndClose ? Projects.archiveSnapshot($0) : Projects.entry(for: $0) }
            self.windows = windows
            remaining = (mode == .archiveAndClose ? windows.filter { $0.spaceIds == [space.spaceId] && !$0.isOnAllSpaces && !$0.isFullscreen } : [])[...]
            snapshot = ProjectArchiveSnapshot(capturedAt: Date(), desktopUuid: space.uuid, desktopNumber: space.desktopNumber,
                name: projects.map { $0.resolvedName }.joined(separator: " · "), windows: windows.map { window in
                    .init(id: window.tracked.id, windowId: window.cgWindowId!, app: window.application.localizedName ?? "Application",
                        bundleIdentifier: window.application.bundleIdentifier, title: window.title, position: window.position, size: window.size,
                        minimized: window.isMinimized, projectIds: projects.filter { $0.members.contains(window.tracked.id) }.map { $0.id },
                        reference: ProjectBrowserURLs.url(for: window))
                })
            super.init()
            progress.title = mode == .snapshotOnly ? "Snapshot Desktop \(space.desktopNumber)" : "Archive Desktop \(space.desktopNumber)"
            if mode == .snapshotOnly { stop.title = NSLocalizedString("Cancel Snapshot", comment: "Cancel a manual desktop snapshot") }
            progress.isReleasedWhenClosed = false
            progress.hidesOnDeactivate = false
            progress.level = .floating
            progress.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]
            progress.setAccessibilitySubrole(.floatingWindow)
            detail.frame = NSRect(x: 20, y: 60, width: 360, height: 68)
            stop.frame = NSRect(x: 260, y: 16, width: 120, height: 32)
            stop.bezelStyle = .rounded
            stop.target = self
            stop.action = #selector(cancel)
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 148))
            content.addSubview(detail)
            content.addSubview(stop)
            progress.contentView = content
            progress.center()
            progress.orderFrontRegardless()
        }

        func updateProgress(_ text: String, canStop: Bool = true) {
            detail.stringValue = text
            stop.isEnabled = canStop
        }

        func dismissProgress() { progress.orderOut(nil) }

        @objc private func cancel() {
            if mode == .snapshotOnly, !cancellation.cancel() {
                updateProgress("Finishing the saved snapshot…", canStop: false)
                return
            }
            let status = mode == .snapshotOnly ? "Snapshot cancelled. No windows were closed."
                : "Closing stopped by the user. A window already asked to close may still close; the Desktop remains open."
            DesktopArchive.finish(self, status: status)
        }
    }

    private static var session: Session?
    private static var promptOpen = false

    static func takeSnapshot(spaceUuid: String, from window: NSWindow?) {
        guard Projects.isEnabled, let space = Projects.spaces.first(where: { $0.uuid == spaceUuid }) else { return }
        guard session == nil, !promptOpen else {
            notice("A snapshot is already in progress", "Wait for the current snapshot to finish or cancel it before starting another.")
            return
        }
        let projects = Projects.linkedProjects(for: Projects.forSpace(uuid: spaceUuid))
        guard projects.isEmpty else {
            DispatchQueue.main.async { begin(space, projects: projects, name: "", expected: candidates(on: space), mode: .snapshotOnly) }
            return
        }
        promptOpen = true
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Name this snapshot’s Project", comment: "Manual snapshot without a linked Project")
        alert.informativeText = NSLocalizedString("The snapshot will be saved in a new folder inside your Projects folder. Your windows and Desktop stay open.", comment: "Manual snapshot naming explanation")
        let name = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        name.stringValue = Projects.availableProjectName(Projects.desktopDisplayName(spaceUuid) ?? "Desktop \(space.desktopNumber)")
        name.setAccessibilityLabel(NSLocalizedString("Project name", comment: "Manual snapshot Project name"))
        alert.accessoryView = name
        alert.addButton(withTitle: NSLocalizedString("Take Snapshot", comment: "Save a visual desktop snapshot"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        ProjectPrompt.present(alert, from: window) { response in
            promptOpen = false
            guard response == .alertFirstButtonReturn else { return }
            let proposed = name.stringValue
            DispatchQueue.main.async { begin(space, projects: [], name: proposed, expected: candidates(on: space), mode: .snapshotOnly) }
        }
    }

    static func prompt(spaceUuid: String, from window: NSWindow?, hide: @escaping () -> Void) {
        guard !promptOpen, session == nil, Projects.isEnabled,
              let space = Projects.spaces.first(where: { $0.uuid == spaceUuid }) else { return }
        guard space.desktopNumber > 0 else { hide(); return }
        promptOpen = true
        let projects = Projects.linkedProjects(for: Projects.forSpace(uuid: spaceUuid))
        let targets = candidates(on: space)
        let alert = NSAlert()
        alert.messageText = "Close Desktop \(space.desktopNumber)?"
        alert.informativeText = "Save a dated Markdown snapshot with screenshots and reopening details in each project’s folder, then close \(targets.count) windows and this Desktop. Projects move to the Attic.\n\nProject windows on other Desktops and windows shared with other Desktops stay open. Apps may ask you to save documents; cancelling or leaving a save prompt open keeps the Desktop open."
        let name = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        if projects.isEmpty {
            name.stringValue = Projects.availableProjectName(Projects.desktopDisplayName(spaceUuid) ?? "Desktop \(space.desktopNumber)")
            name.placeholderString = "Project name"
            name.setAccessibilityLabel("Project name for the archive folder")
            alert.accessoryView = name
            alert.informativeText += "\n\nCreate a project with the name below in your Projects folder."
        } else {
            alert.informativeText += "\n\nProjects: " + projects.map { $0.resolvedName }.joined(separator: ", ")
        }
        alert.addButton(withTitle: "Archive and Close Desktop").keyEquivalent = ""
        alert.addButton(withTitle: "Hide Label")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        ProjectPrompt.present(alert, from: window) { response in
            promptOpen = false
            if response == .alertSecondButtonReturn { DispatchQueue.main.async(execute: hide); return }
            guard response == .alertFirstButtonReturn else { return }
            let proposed = name.stringValue
            DispatchQueue.main.async { begin(space, projects: projects, name: proposed, expected: targets) }
        }
    }

    private static func begin(_ space: SpaceItem, projects: [Project], name: String, expected: [Window], mode: ProjectArchivePolicy.Mode = .archiveAndClose) {
        guard session == nil, Projects.isEnabled, Projects.spaces.contains(where: { $0.uuid == space.uuid && $0.spaceId == space.spaceId }),
              projects.allSatisfy({ Projects.byId[$0.id] === $0 && $0.homeSpaceUuid == space.uuid }),
              Set(Projects.linkedProjects(for: Projects.forSpace(uuid: space.uuid)).map { $0.id }) == Set(projects.map { $0.id }),
              Set(candidates(on: space).map { $0.tracked.id }) == Set(expected.map { $0.tracked.id }) else {
            notice("Desktop changed", "Review the Desktop and try again. No windows were closed.")
            return
        }
        var owners = projects
        if owners.isEmpty {
            guard ProjectNameResolver.validationError(name, existing: Projects.projectNames()) == nil,
                  let project = Projects.createCustom(homeSpaceUuid: space.uuid) else {
                notice("Choose a project name", "Use a nonempty, unique project name and try again.")
                return
            }
            project.name = name
            guard Projects.link(Projects.forSpace(uuid: space.uuid), to: project) else { Projects.delete(id: project.id); return }
            owners = [project]
        }
        let capturedWindows = Windows.list.filter { window in
            !window.isWindowlessApp && !window.isPhantom && !window.isTabbed && window.cgWindowId != nil
                && window.application.pid != AXUIElement.currentProcessPid
                && (window.spaceIds.contains(space.spaceId) || owners.contains { $0.members.contains(window.tracked.id) })
        }.sorted { $0.lastFocusOrder < $1.lastFocusOrder }
        let current = Session(space: space, projects: owners, windows: capturedWindows, mode: mode)
        for window in capturedWindows {
            if mode == .snapshotOnly { setOutcome(window, "Left open", current) }
            else if !expected.contains(where: { $0 === window }) { setOutcome(window, "Kept open: shared with or located on another Desktop", current) }
        }
        session = current
        ProjectPersistence.archiveDirectories(for: owners.map { $0.id }) { result in
            guard session === current else { return }
            switch result {
            case .failure(let error): finish(current, status: "Archive failed; no windows were closed.", error: error.localizedDescription)
            case .success(let directories):
                let elements = Dictionary(uniqueKeysWithValues: capturedWindows.compactMap { w in w.axUiElement.map { (w.tracked.id, $0) } })
                let capture = ProjectArchiveFiles.Capture(snapshot: current.snapshot, projects: current.entries, directories: directories, elements: elements, cancellation: mode == .snapshotOnly ? current.cancellation : nil)
                ProjectArchiveFiles.create(capture) { result in captured(result, current) }
            }
        }
    }

    private static func captured(_ result: Result<(ProjectArchiveSnapshot, [URL]), Error>, _ current: Session) {
        ProjectPersistence.refreshSnapshotHistory()
        guard session === current else { return }
        switch result {
        case .failure(let error): finish(current, status: "Archive failed; no windows were closed.", error: error.localizedDescription)
        case .success(let result):
            current.snapshot = result.0
            current.directories = result.1
            for window in current.windows where !Windows.list.contains(where: { $0 === window }) {
                setOutcome(window, "Closed during capture", current)
            }
            if current.mode == .snapshotOnly {
                let missing = current.snapshot.windows.filter { $0.screenshot == nil }.count
                let detail = missing == 0 ? nil : "\(missing) window screenshots were unavailable; the snapshot records which ones."
                finish(current, status: "Snapshot saved. No windows were closed.", error: detail)
                return
            }
            guard current.snapshot.windows.allSatisfy({ $0.screenshot != nil }) else {
                let alert = NSAlert()
                alert.messageText = "Some window screenshots are unavailable"
                alert.informativeText = "The snapshot records which images macOS or the app could not provide. Keep the snapshot without closing, or continue closing with those images missing."
                alert.addButton(withTitle: "Keep Desktop Open")
                alert.addButton(withTitle: "Continue Closing").keyEquivalent = ""
                ProjectPrompt.present(alert, from: nil) { response in
                    DispatchQueue.main.async {
                        if response == .alertSecondButtonReturn { closeNext(current) }
                        else { finish(current, status: "Snapshot saved; closing cancelled before any close requests.") }
                    }
                }
                return
            }
            closeNext(current)
        }
    }

    private static func closeNext(_ current: Session) {
        guard session === current, !current.finishing, current.mode == .archiveAndClose else { return }
        guard Projects.isEnabled, current.projects.allSatisfy({ Projects.byId[$0.id] === $0 && $0.homeSpaceUuid == current.space.uuid }),
              Projects.spaces.contains(where: { $0.uuid == current.space.uuid && $0.spaceId == current.space.spaceId }) else {
            finish(current, status: "Closing stopped because the Project or Desktop changed.")
            return
        }
        let live = Set(Windows.list.map { $0.tracked.id })
        let decision = ProjectArchivePolicy.next(mode: current.mode, saved: !current.directories.isEmpty, contextValid: true,
            pending: current.waiting?.tracked.id, remaining: current.remaining.map { $0.tracked.id },
            live: live, local: Set(candidates(on: current.space).map { $0.tracked.id }))
        if decision == .wait { return }
        current.timer?.cancel()
        current.waiting = nil
        if decision == .removeDesktop { removeDesktop(current); return }
        guard case .close(let id) = decision,
              let index = current.remaining.firstIndex(where: { $0.tracked.id == id }) else {
            finish(current, status: "Closing stopped because windows moved or new windows appeared. The Desktop remains open.")
            return
        }
        let next = current.remaining[index]
        current.remaining = current.remaining.suffix(from: current.remaining.index(after: index))
        guard next.axUiElement != nil else {
            finish(current, status: "Closing stopped because a captured window cannot be closed.")
            return
        }
        current.waiting = next
        current.updateProgress("Waiting for \(next.application.localizedName ?? "the app") to close \(next.title). Resolve any save prompt, or stop closing.")
        setOutcome(next, "Close requested; closure not yet confirmed", current)
        current.snapshot.status = "Closing in progress. Unconfirmed windows may still be open."
        ProjectArchiveFiles.update(current.snapshot, in: current.directories) { error in
            guard session === current, current.waiting === next, !current.finishing else { return }
            guard error == nil else { finish(current, status: "Closing stopped because the archive could not be updated.", error: error?.localizedDescription); return }
            guard Projects.isEnabled, candidates(on: current.space).contains(where: { $0 === next }),
                  current.projects.allSatisfy({ Projects.byId[$0.id] === $0 && $0.homeSpaceUuid == current.space.uuid }) else {
                finish(current, status: "Closing stopped because the window or Project changed while saving.")
                return
            }
            let work = DispatchWorkItem {
                guard session === current, current.waiting === next else { return }
                setOutcome(next, "Still open; close was cancelled, refused, or awaiting a save prompt", current)
                finish(current, status: "Closing stopped with windows still open. The Desktop and Projects remain open.")
            }
            current.timer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
            next.close()
        }
    }

    static func windowsRemoved(_ windows: [Window]) {
        guard let current = session, !current.finishing else { return }
        for window in windows where current.windows.contains(where: { $0 === window }) { setOutcome(window, "Closed", current) }
        guard let waiting = current.waiting, windows.contains(where: { $0 === waiting }) else { return }
        current.timer?.cancel()
        current.waiting = nil
        // Reducer removal must finish before checking the next window or whether the Desktop is empty.
        DispatchQueue.main.async { closeNext(current) }
    }

    static func canRemoveDesktop(_ uuid: String) -> Bool {
        guard let current = session, !current.finishing, current.mode == .archiveAndClose, current.space.uuid == uuid else { return false }
        return Projects.isEnabled && current.projects.allSatisfy { Projects.byId[$0.id] === $0 && $0.homeSpaceUuid == uuid }
            && candidates(on: current.space).isEmpty
    }

    private static func removeDesktop(_ current: Session) {
        guard canRemoveDesktop(current.space.uuid) else {
            finish(current, status: "Captured windows closed. New windows remain, so the Desktop and Projects stay open.")
            return
        }
        current.updateProgress("Removing the empty Desktop in Mission Control…", canStop: false)
        DesktopRemoval.remove(current.space) { success in
            guard session === current else { return }
            if success {
                for (project, entry) in zip(current.projects, current.entries) { Projects.close(project, snapshot: entry) }
                finish(current, status: "Archived and closed. Desktop removed; Projects saved in the Attic.")
            } else {
                finish(current, status: "Captured windows closed. Desktop removal was not confirmed; Projects remain open.",
                    error: "The last Desktop on a display cannot be removed. You can also remove an empty Desktop in Mission Control.")
            }
        }
    }

    private static func candidates(on space: SpaceItem) -> [Window] {
        Windows.list.filter {
            !$0.isWindowlessApp && !$0.isPhantom && !$0.isTabbed && !$0.isFullscreen && !$0.isOnAllSpaces
                && $0.application.pid != AXUIElement.currentProcessPid && $0.cgWindowId != nil
                && $0.spaceIds == [space.spaceId]
        }.sorted { $0.lastFocusOrder < $1.lastFocusOrder }
    }

    private static func setOutcome(_ window: Window, _ value: String, _ current: Session) {
        guard let index = current.snapshot.windows.firstIndex(where: { $0.id == window.tracked.id }) else { return }
        current.snapshot.windows[index].outcome = value
    }

    private static func finish(_ current: Session, status: String, error: String? = nil) {
        guard session === current, !current.finishing else { return }
        current.finishing = true
        current.dismissProgress()
        current.timer?.cancel()
        current.snapshot.status = status
        guard !current.directories.isEmpty else { session = nil; notice(status, error ?? ""); return }
        ProjectArchiveFiles.update(current.snapshot, in: current.directories) { writeError in
            ProjectPersistence.refreshSnapshotHistory()
            guard session === current else { return }
            session = nil
            let detail = [error, writeError?.localizedDescription, current.directories.first?.appendingPathComponent("README.md").path].compactMap { $0 }.joined(separator: "\n\n")
            notice(writeError == nil ? status : "Snapshot status could not be saved", detail)
        }
    }

    private static func notice(_ title: String, _ detail: String) {
        ProjectRestoreNotice.showSummary(title: title, rows: [.init(title: "Project archive", detail: detail)])
    }
}
