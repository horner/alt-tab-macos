import Foundation

/// Decides switcher visibility from window facts, preferences, and the current search scope.
/// `isOnPreferredScreen` stays lazy because `Window.isOnScreen` reads display/Space geometry.
enum WindowFilterResolver {
    /// All-windows search keeps exclusions and tab/windowless preferences; normal scope applies every filter.
    static func shouldShow(_ s: WindowState, _ app: ApplicationState,
                           searchAllWindows: Bool = false,
                           onlyFrontmostApp: Bool = false,       // appsToShow == .active
                           excludeFrontmostApp: Bool = false,    // appsToShow == .nonActive
                           hideHidden: Bool = false,             // showHiddenWindows == .hide
                           hideWindowless: Bool = false,         // showWindowlessApps == .hide
                           hideFullscreen: Bool = false,         // showFullscreenWindows == .hide
                           hideMinimized: Bool = false,          // showMinimizedWindows == .hide
                           onlyVisibleSpaces: Bool = false,      // spacesToShow == .visible
                           onlyNonVisibleSpaces: Bool = false,   // spacesToShow == .nonVisible
                           onlyPreferredScreen: Bool = false,    // screensToShow == .showingAltTab
                           separateTabs: Bool = false,           // groupTabs == .separateWindows
                           frontmostPid: pid_t? = nil,
                           visibleSpaceIds: [UInt64] = [],       // CGSSpaceID === UInt64
                           exceptions: [ExceptionEntry] = [],
                           activeProjectMembers: Set<String>? = nil,
                           isOnPreferredScreen: @autoclosure () -> Bool) -> Bool {
        guard !s.isPhantom,
              !ExceptionMatcher.hidesWindow(s, app, exceptions: exceptions,
                activeAppOverride: !searchAllWindows && onlyFrontmostApp && frontmostPid == app.pid) else { return false }
        if searchAllWindows {
            return s.isWindowlessApp ? !hideWindowless : separateTabs || !s.isTabbed
        }
        return (activeProjectMembers?.contains(s.id) ?? true) &&
            !(onlyFrontmostApp && !(frontmostPid == app.pid)) &&
            !(excludeFrontmostApp && frontmostPid == app.pid) &&
            !(hideHidden && app.isHidden) &&
            ((!hideWindowless && s.isWindowlessApp) ||
                !s.isWindowlessApp &&
                !(hideFullscreen && s.isFullscreen) &&
                !(hideMinimized && s.isMinimized) &&
                // A held tab just backgrounded on the current Space but has already lost its Space IDs
                // (live capture 2026-07-24). Treat it as visible and on-screen until discovery finishes;
                // see testOnlyVisibleSpacesShowsSpacelessHeldTab and testOnlyPreferredScreenShowsHeldTab.
                !(onlyVisibleSpaces && !s.isHeldVisibleForTab && !inAnyVisibleSpace(s, visibleSpaceIds)) &&
                !(onlyNonVisibleSpaces && (s.isHeldVisibleForTab || inAnyVisibleSpace(s, visibleSpaceIds))) &&
                !(onlyPreferredScreen && !s.isHeldVisibleForTab && !isOnPreferredScreen()) &&
                (separateTabs || !s.isTabbed))
    }

    private static func inAnyVisibleSpace(_ s: WindowState, _ visibleSpaceIds: [UInt64]) -> Bool {
        visibleSpaceIds.contains { visibleSpace in s.spaceIds.contains { $0 == visibleSpace } }
    }
}
