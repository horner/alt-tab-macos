import Cocoa
import ShortcutRecorder

/// `SpacesOrderPreference` itself is declared in `SpacesOrderResolver.swift`, which is in the unit-tests
/// target; `MacroPreference` is not, so the conformance lives here.
extension SpacesOrderPreference: MacroPreference {
    var localizedString: LocalizedString {
        switch self {
            case .recentlyFocused: return NSLocalizedString("Recently visited first", comment: "")
            case .desktopOrder: return NSLocalizedString("Desktop order", comment: "")
        }
    }
}

/// Preferences owned by the Spaces switcher. Kept out of `Preferences.swift` so the feature stays
/// contained; only its five entries in `Preferences.defaultValues` live upstream.
extension Preferences {
    static var holdSpacesShortcut: Shortcut? { CachedUserDefaults.shortcut(SpacesSwitcher.holdShortcutId) }
    static var nextSpaceShortcut: Shortcut? { CachedUserDefaults.shortcut(SpacesSwitcher.nextShortcutId) }
    static var previousSpaceShortcut: Shortcut? { CachedUserDefaults.shortcut(SpacesSwitcher.previousShortcutId) }
    static var spacesOrder: SpacesOrderPreference { CachedUserDefaults.macroPref("spacesOrder", SpacesOrderPreference.allCases) }
    static var showFullscreenSpaces: Bool { CachedUserDefaults.bool("showFullscreenSpaces") }
    static var spacesShortcutStyle: ShortcutStylePreference { CachedUserDefaults.macroPref("spacesShortcutStyle", ShortcutStylePreference.allCases) }

    static var spacesDefaultValues: [String: Any] {
        [
            // ⌃ rather than ⌥: both default window-switcher shortcuts hold ⌥, so sharing it would make
            // `RegisterEventHotKey` fail with `eventHotKeyExistsErr` (-9878) the moment a next-space key is
            // bound. ⌃ is also where macOS already puts Space navigation (⌃← / ⌃→).
            SpacesSwitcher.holdShortcutId: defaultShortcut("⌃"),
            SpacesSwitcher.nextShortcutId: defaultShortcut(""),            SpacesSwitcher.previousShortcutId: defaultShortcut("⇧"),            "spacesOrder": SpacesOrderPreference.recentlyFocused.indexAsString,
            "showFullscreenSpaces": "false",
            "spacesShortcutStyle": ShortcutStylePreference.focusOnRelease.indexAsString,
        ]
    }
}
