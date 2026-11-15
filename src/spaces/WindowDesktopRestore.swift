import Cocoa

/// Snapshot a finite batch on main; yield between windows and revalidate each destination before its move.
enum WindowDesktopRestore {
    typealias Summary = WindowDesktopRestoreResolver.Summary
    private typealias Decision = WindowDesktopRestoreResolver.Decision

    private final class Candidate {
        weak var window: Window?
        let destination: WindowDesktopMove.Destination
        let source: [UInt64]
        let name: String
        let id: String

        init(_ window: Window, _ destination: WindowDesktopMove.Destination) {
            self.window = window
            self.destination = destination
            source = window.spaceIds
            name = windowName(window)
            id = window.tracked.id
        }
    }

    private final class Batch {
        var candidates = [Candidate]()
        var nextIndex = 0
        var summary = Summary()
        var targets = [String: ProjectRestoreNotice.WindowTarget]()
        let completion: (Summary) -> Void

        init(_ completion: @escaping (Summary) -> Void) { self.completion = completion }
    }

    private static var batch: Batch?
    private static var lastSummary: Summary?
    private static var lastTargets = [String: ProjectRestoreNotice.WindowTarget]()
    static var isRunning: Bool { batch != nil }
    static var isAvailable: Bool { Projects.isEnabled && WindowDesktopMoveBridge.isAvailable && !isRunning }
    static var hasLastResults: Bool { lastSummary != nil }

    static func restoreAll() {
        restore(Windows.list) { _ in showLastResults() }
    }

    static func showLastResults() {
        guard Projects.isEnabled, let summary = lastSummary else { return }
        ProjectRestoreNotice.showSummary(title: NSLocalizedString("Desktop restore finished", comment: "Desktop restoration summary"),
            rows: summaryRows(summary))
    }

    static func restore(_ windows: [Window], completion: @escaping (Summary) -> Void) {
        guard isAvailable else { return }
        let batch = Batch(completion)
        self.batch = batch
        let desktops = normalDesktops()
        var owners = [String: [Project]]()
        for project in Projects.list where project.isCustom {
            for id in project.members { owners[id, default: []].append(project) }
        }
        for window in windows where !window.isWindowlessApp && window.application.pid != AXUIElement.currentProcessPid {
            let projects = owners[window.tracked.id] ?? []
            let decision = WindowDesktopRestoreResolver.decision(isEligible: WindowDesktopMove.isEligible(window),
                spaces: window.spaceIds, projectHomes: projects.map { $0.homeSpaceUuid }, desktops: desktops)
            if case .move(let destination) = decision {
                batch.candidates.append(Candidate(window, destination))
                batch.targets[window.tracked.id] = ProjectRestoreNotice.WindowTarget(window)
            } else {
                record(decision, window: window, projects: projects, batch: batch)
            }
        }
        advance(batch)
    }

    private static func normalDesktops() -> [UInt64: String] {
        Dictionary(uniqueKeysWithValues: Projects.spaces.filter { $0.desktopNumber > 0 }.map { ($0.spaceId, $0.uuid) })
    }

    private static func advance(_ batch: Batch) {
        DispatchQueue.main.async {
            guard self.batch === batch else { return }
            guard Projects.isEnabled else {
                for candidate in batch.candidates.dropFirst(batch.nextIndex) {
                    batch.summary.fail(windowName: candidate.name, reason: NSLocalizedString("Projects were disabled", comment: "Desktop restore failure"), windowId: candidate.id)
                }
                finish(batch)
                return
            }
            guard batch.nextIndex < batch.candidates.count else { finish(batch); return }
            let candidate = batch.candidates[batch.nextIndex]
            batch.nextIndex += 1
            guard let window = candidate.window, Windows.list.contains(where: { $0 === window }) else {
                batch.summary.fail(windowName: candidate.name, reason: NSLocalizedString("Window closed", comment: "Desktop restore failure"), windowId: candidate.id)
                advance(batch)
                return
            }
            let projects = Projects.list.filter { $0.isCustom && $0.members.contains(window.tracked.id) }
            let decision = WindowDesktopRestoreResolver.decision(isEligible: WindowDesktopMove.isEligible(window),
                spaces: window.spaceIds, projectHomes: projects.map { $0.homeSpaceUuid }, desktops: normalDesktops())
            guard decision == .move(candidate.destination), window.spaceIds == candidate.source else {
                if case .move = decision {
                    batch.summary.fail(windowName: candidate.name, reason: NSLocalizedString("Project or Desktop changed during restore", comment: "Desktop restore failure"), windowId: candidate.id)
                } else {
                    record(decision, window: window, projects: projects, batch: batch)
                }
                advance(batch)
                return
            }
            WindowDesktopMove.restore(window, to: candidate.destination) { succeeded in
                if succeeded {
                    batch.summary.moved += 1
                } else {
                    batch.summary.fail(windowName: candidate.name, reason: NSLocalizedString("Move could not be confirmed", comment: "Desktop restore failure"), windowId: candidate.id)
                }
                advance(batch)
            }
        }
    }

    private static func finish(_ batch: Batch) {
        guard self.batch === batch else { return }
        self.batch = nil
        lastSummary = batch.summary
        lastTargets = batch.targets
        Logger.debug { "desktop restore moved=\(batch.summary.moved) home=\(batch.summary.alreadyHome) skipped=\(batch.summary.skipped) failed=\(batch.summary.failed)" }
        for detail in batch.summary.details { Logger.debug { "desktop restore window=\(detail.windowName) reason=\(detail.reason)" } }
        batch.completion(batch.summary)
    }

    private static func windowName(_ window: Window) -> String {
        let app = window.application.localizedName ?? NSLocalizedString("Unknown app", comment: "Desktop restore window app")
        guard let title = ProjectNameResolver.normalized(window.title), title != app else { return app }
        return "\(app) — \(title)"
    }

    private static func record(_ decision: Decision, window: Window, projects: [Project], batch: Batch) {
        guard let reason = reason(decision, window: window, projects: projects) else { batch.summary.record(decision); return }
        batch.targets[window.tracked.id] = ProjectRestoreNotice.WindowTarget(window)
        batch.summary.record(decision, detail: .init(windowName: windowName(window), reason: reason, windowId: window.tracked.id))
    }

    private static func reason(_ decision: Decision, window: Window, projects: [Project]) -> String? {
        switch decision {
        case .move, .alreadyHome: return nil
        case .unassigned: return NSLocalizedString("No Project assigned", comment: "Desktop restore skip reason")
        case .conflictingProjects:
            let homes = projects.map { project -> String in
                guard let space = Projects.spaces.first(where: { $0.uuid == project.homeSpaceUuid && $0.desktopNumber > 0 }) else { return project.resolvedName }
                return String(format: NSLocalizedString("%@ (D%d)", comment: "Project name and home Desktop number"), project.resolvedName, space.desktopNumber)
            }
            return String(format: NSLocalizedString("Conflict: %@", comment: "Conflicting Project homes"), homes.joined(separator: " / "))
        case .missingDesktop:
            return String(format: NSLocalizedString("Home Desktop unavailable: %@", comment: "Desktop restore skip reason"), projects.map { $0.resolvedName }.joined(separator: " / "))
        case .unsupported:
            if window.isFullscreen || window.isFullscreenMirrored { return NSLocalizedString("Fullscreen window", comment: "Desktop restore skip reason") }
            if window.isTabbed || window.tabbedSiblingWids != nil { return NSLocalizedString("Window belongs to a tab group", comment: "Desktop restore skip reason") }
            if window.isPhantom || window.cgWindowId == nil { return NSLocalizedString("Window unavailable", comment: "Desktop restore skip reason") }
            if window.spaceIds.count > 1 { return NSLocalizedString("Window is on multiple Desktops", comment: "Desktop restore skip reason") }
            return NSLocalizedString("Desktop location not confirmed", comment: "Desktop restore skip reason")
        }
    }

    private static func summaryRows(_ summary: Summary) -> [ProjectRestoreNotice.Row] {
        var rows = [ProjectRestoreNotice.Row(
            title: String(format: NSLocalizedString("%d moved · %d already home", comment: "Desktop restoration counts"), summary.moved, summary.alreadyHome),
            detail: String(format: NSLocalizedString("%d skipped · %d could not be moved", comment: "Desktop restoration counts"), summary.skipped, summary.failed))]
        for detail in summary.details {
            rows.append(ProjectRestoreNotice.Row(title: detail.windowName, detail: detail.reason,
                target: detail.windowId.flatMap { lastTargets[$0] }))
        }
        return rows
    }
}
