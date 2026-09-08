# ProjectScopeResolver

An active custom Project overrides only the Space and screen filters. All Spaces/Screens is the default.
Current Space/Screen uses the current Space (not every visible Space across displays) and main screen.
Projects disabled or normal Desktop scope keep the ordinary shortcut filters. Membership and all other
filters, including exceptions, hidden/minimized windows and tabs, remain enforced.

## Test scenarios

- **testAllLocationsIncludesOffSpaceAndOffScreenMember** — ordinary visible-Space/screen filters cannot hide a Project member in All mode.
- **testAllLocationsStillExcludesNonmembersAndOtherHiddenWindows** — location overrides do not bypass membership, minimized or phantom exclusion.
- **testCurrentLocationRequiresCurrentSpaceAndScreen** — current mode requires both the current Space and screen, excluding another display’s visible Space.
- **testNoActiveProjectPreservesNormalLocationFilters** — ordinary visible-Space/screen settings remain effective outside custom Projects.
- **testProjectOverridesNonVisibleSpaceSetting** — an ordinary non-visible-Spaces filter is also overridden by the Project scope.
