# ProjectScopeResolver

An active custom Project shows its members on every Desktop and screen, together with eligible windows
on the current Desktop. Local windows remain visible even when assigned to another Project or when
the selected Project owns a different Desktop. The union is defined by ProjectMembershipResolver.
Ordinary Space and screen filters cannot narrow this union, and no Project location preference is read.
Projects disabled or normal Desktop scope keep the ordinary shortcut filters. Exceptions, hidden and
minimized windows, tab grouping and all other window filters remain enforced. Project label controls
retain their independent Show/Hide preference and ordinary location filters.

## Test scenarios

- **testRemoteProjectMemberIgnoresSpaceAndScreenFilters** — remote and temporarily Space-less explicit members remain eligible.
- **testCurrentDesktopNonmemberAppearsRegardlessOfScreen** — local nonmembers pass without a preferred-screen constraint.
- **testRemoteNonmemberAndOtherDisplaysDesktopStayExcluded** — only the single current Desktop contributes nonmembers; a window on all Desktops includes it.
- **testProjectUnionHonorsOrdinaryWindowExclusions** — membership and local fallback both preserve hidden, minimized, phantom, tab and exception exclusion.
- **testNoActiveProjectPreservesNormalLocationFilters** — ordinary visible-Space/screen settings remain effective outside custom Projects.
- **testProjectOverridesNonVisibleSpaceSettingWithoutQueryingScreen** — Project scope also overrides non-visible-Spaces filtering without a screen-geometry query.
