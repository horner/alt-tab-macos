# ProjectScopeResolver

An active custom Project overrides only the Space and screen filters. All Spaces/Screens is the default.
Current Space/Screen uses the current Space (not every visible Space across displays) and main screen.
Projects disabled or normal Desktop scope keep the ordinary shortcut filters. Only the Project
owning the current Desktop includes its unassigned windows, as defined by ProjectMembershipResolver.
Other Projects show their explicit members, including shared and remote windows. Membership and all
other filters, including exceptions, hidden/minimized windows and tabs, remain enforced.

## Test scenarios

- **testAllLocationsIncludesOffSpaceAndOffScreenMember** — ordinary visible-Space/screen filters cannot hide a Project member in All mode.
- **testAllLocationsStillExcludesNonmembersAndOtherHiddenWindows** — location overrides do not bypass membership, minimized or phantom exclusion.
- **testCurrentLocationRequiresCurrentSpaceAndScreen** — current mode requires both the current Space and screen, excluding another display’s visible Space.
- **testNoActiveProjectPreservesNormalLocationFilters** — ordinary visible-Space/screen settings remain effective outside custom Projects.
- **testProjectOverridesNonVisibleSpaceSetting** — an ordinary non-visible-Spaces filter is also overridden by the Project scope.
- **testUnassignedCurrentDesktopWindowPassesProjectFilter** — unassigned local windows pass while remote unassigned windows and another Project's members stay excluded.
- **testNonownerScopeDoesNotIncludeUnassignedDesktopWindows** — both Project scopes exclude fallback windows for a nonowner while retaining explicit local and remote members.
- **testUnassignedFallbackStillHonorsOrdinaryFilters** — the fallback preserves minimized, phantom and current-screen restrictions.
