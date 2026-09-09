import Cocoa

enum DesktopNavigation {
    private static var history = DesktopNavigationResolver.History()
    static var isReturnSelected: Bool { SwitcherSession.current?.desktopReturnTarget != nil }

    static var returnTarget: DesktopNavigationResolver.Destination? {
        history.target(currentSpaceUuid: Projects.spaces.first { $0.isCurrent }?.uuid,
            availableSpaceUuids: Set(Projects.spaces.map { $0.uuid }))
    }

    static func destination(for window: Window) -> SpaceItem? {
        let id = DesktopNavigationResolver.destinationSpace(windowSpaces: window.spaceIds,
            currentSpace: Spaces.currentSpaceId, visibleSpaces: Spaces.visibleSpaces,
            availableSpaces: Projects.spaces.map { $0.spaceId }, isWindowlessApp: window.isWindowlessApp)
        return id.flatMap { id in Projects.spaces.first { $0.spaceId == id } }
    }

    static func leaving(_ space: SpaceItem?) -> DesktopNavigationResolver.Destination? {
        guard let space else { return nil }
        let window = Windows.list.filter { eligible($0, on: space) }.min { $0.lastFocusOrder < $1.lastFocusOrder }
        return .init(spaceUuid: space.uuid, projectId: Projects.active?.id, windowId: window?.id)
    }

    static func entered(_ space: SpaceItem?, leaving origin: DesktopNavigationResolver.Destination?) -> DesktopNavigationResolver.Destination? {
        guard let space else { return nil }
        if origin?.spaceUuid != space.uuid { clearSelection() }
        return history.entered(space.uuid, leaving: origin, now: ProcessInfo.processInfo.systemUptime)
    }

    static func cycle(_ step: Int, allowWrap: Bool) -> Bool {
        guard let session = SwitcherSession.current else { return false }
        let decision = DesktopNavigationResolver.cycle(step: step,
            visibleIndices: Windows.list.indices.filter { Windows.shouldDisplay(Windows.list[$0]) },
            selectedIndex: session.selectedIndex, returnSelected: isReturnSelected,
            hasDestination: returnTarget != nil, isSearching: TilesView.isSearchModeOn,
            allowWrap: allowWrap, isRepeating: ATShortcut.lastEventIsARepeat || !KeyRepeatTimer.timerIsSuspended)
        switch decision {
        case .windows:
            clearSelection()
            return false
        case .stay:
            return true
        case .back:
            return selectReturn()
        case .window(let index):
            clearSelection()
            session.userPickedSelection = true
            Windows.updateSelectedAndHoveredWindowIndex(index)
            return true
        }
    }

    static func handleUndoKey(_ event: NSEvent?) -> Bool {
        guard let event, event.type == .keyDown, let session = SwitcherSession.current,
              TilesPanel.shared.isKeyWindow, returnTarget != nil else { return false }
        let holdModifiers = ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", session.shortcutIndex)]?.shortcut.modifierFlags ?? []
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard DesktopNavigationResolver.isUndoShortcut(characters: event.charactersIgnoringModifiers,
            hasCommand: modifiers.contains(.command), hasOtherModifiers: !modifiers.subtracting(holdModifiers.union(.command)).isEmpty,
            isSearchEditing: TilesView.isSearchEditing) else { return false }
        if !event.isARepeat { returnToPrevious() }
        return true
    }

    private static func selectReturn() -> Bool {
        guard let session = SwitcherSession.current, let target = returnTarget else { return false }
        session.desktopReturnTarget = target
        session.userPickedSelection = true
        let hoveredIndex = session.hoveredIndex
        session.hoveredIndex = nil
        session.hoveredTarget = nil
        if let hoveredIndex { TilesView.highlight(hoveredIndex) }
        TilesView.highlight(session.selectedIndex)
        ProjectContextHeader.refreshReturnSelection()
        DispatchQueue.main.async { if isReturnSelected { PreviewPanel.hide() } }
        ProjectContextHeader.voiceOverReturn()
        return true
    }

    @discardableResult
    static func clearSelection() -> Bool {
        guard let session = SwitcherSession.current, session.desktopReturnTarget != nil else { return false }
        session.desktopReturnTarget = nil
        TilesView.highlight(session.selectedIndex)
        ProjectContextHeader.refreshReturnSelection()
        return true
    }

    static func returnToPrevious() {
        guard SwitcherSession.isActive else { return }
        guard let target = SwitcherSession.current?.desktopReturnTarget ?? returnTarget, target == returnTarget else {
            App.hideUi()
            return
        }
        App.hideUi()
        // Commit the switcher dismissal before focus can block on another process.
        DispatchQueue.main.async {
            guard !SwitcherSession.isActive, target == returnTarget,
                  let space = Projects.spaces.first(where: { $0.uuid == target.spaceUuid }) else { return }
            history.beginReturn(target, now: ProcessInfo.processInfo.systemUptime)
            Logger.debug { "desktop return space=\(space.uuid) project=\(target.projectId ?? "none")" }
            if let window = Windows.list.first(where: { $0.id == target.windowId && eligible($0, on: space) }) {
                window.focus()
            } else {
                space.activate()
            }
        }
    }

    static func name(of space: SpaceItem, includeName: Bool = true) -> String {
        let desktop = space.isFullscreen ? NSLocalizedString("Fullscreen", comment: "Desktop navigation destination")
            : String(format: NSLocalizedString("Desktop %d", comment: ""), space.desktopNumber)
        let name = includeName ? Projects.byId["desktop-\(space.uuid)"]?.preferredName : nil
        return name.map { "\(desktop) · \($0)" } ?? desktop
    }

    static var returnTitle: String? {
        guard let target = returnTarget, let space = Projects.spaces.first(where: { $0.uuid == target.spaceUuid }) else { return nil }
        let project = target.projectId.flatMap { Projects.byId[$0] }
        let destination = Projects.isEnabled && project?.isCustom == true
            ? "\(project!.resolvedName) · \(name(of: space, includeName: false))" : name(of: space)
        return String(format: NSLocalizedString("↩ Back to %@", comment: "Return to the previous Desktop and Project"), destination)
    }

    private static func eligible(_ window: Window, on space: SpaceItem) -> Bool {
        !window.isWindowlessApp && !window.isPhantom && !window.isTabbed && !window.isMinimized && !window.isHidden
            && window.spaceIds.contains(space.spaceId)
    }
}
