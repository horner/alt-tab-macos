import Cocoa

/// Alt-tab, but for macOS Spaces: hold a modifier, tap a key to walk the list of Desktops, release to go
/// there. Deliberately independent of `SwitcherSession` and the window switcher's pipeline — filters,
/// search, thumbnails and drag & drop have no meaning for a Space — so the two can never be active at
/// once and this feature stays contained to `src/spaces/`.
enum SpacesSwitcher {
    static let holdShortcutId = "holdSpacesShortcut"
    static let nextShortcutId = "nextSpaceShortcut"
    static let previousShortcutId = "previousSpaceShortcut"
    static private(set) var isActive = false

    static func owns(_ id: String) -> Bool { id == holdShortcutId || id == nextShortcutId || id == previousShortcutId }

    /// `ATShortcut.shouldTrigger` gates every global `.up` on a live `SwitcherSession`, which a Spaces
    /// summon never creates, so our shortcuts need their own gate.
    static func shouldTrigger(_ id: String, _ triggerPhase: ShortcutTriggerPhase) -> Bool {
        guard triggerPhase == .down else {
            return isActive && Preferences.spacesShortcutStyle == .focusOnRelease
        }
        // never summon on top of the window switcher: both panels would fight for key focus
        guard !SwitcherSession.isActive else { return false }
        // stepping backwards only means something once the panel is up; a bare ⇧ must not summon it
        return id != previousShortcutId || isActive
    }

    static func showOrCycle() {
        guard !SwitcherSession.isActive else { return }
        guard !isActive else {
            cycle(1)
            return
        }
        SpacesList.refresh()
        // a single Space has nothing to switch to; showing an empty-looking panel would just be noise
        guard SpacesList.list.count > 1 else { return }
        NSScreen.updatePreferred()
        Appearance.update()
        isActive = true
        SpacesPanel.shared.show(SpacesList.list, SpacesList.selectedIndex)
    }

    static func cycle(_ step: Int) {
        guard isActive else { return }
        SpacesList.cycle(step)
        SpacesPanel.shared.refreshHighlight(SpacesList.list, SpacesList.selectedIndex)
    }

    static func focusSelected() {
        guard isActive else { return }
        let space = SpacesList.selected
        hide()
        // after the panel is ordered out, so the Space transition doesn't animate with it still on screen
        space?.activate()
    }

    static func hide() {
        guard isActive else { return }
        isActive = false
        SpacesPanel.shared.orderOut(nil)
    }
}
