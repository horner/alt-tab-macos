# Project Desktop ownership

A Project owns at most one Desktop, and each Desktop has at most one owner. The Project's
`homeSpaceUuid` is the only saved assignment; an empty value means explicitly unassigned.
Desktop objects are runtime adapters for the current macOS topology. Their linked Project IDs
are computed from the owner, and their names are never a separate authority.

An explicit ownership change clears the displaced Project's assignment without deleting the
Project or changing its window membership, history, exclusions, name, or identity. Selecting
no owner clears the prior owner's home assignment. Assigning a Project to another Desktop
moves that assignment; it cannot leave a second reverse link behind. Cancelable creation
creates an unassigned Project first and assigns it only when the user accepts.

Removing or disconnecting a Desktop does not transfer its ownership to any neighboring Desktop.
The Project retains its missing Desktop UUID, history, windows, and identity, remains available
without a Desktop number, and can be reassigned explicitly. If the exact Desktop returns, its
owner is derived again from the saved assignment. Reopening an archived Project on an occupied
Desktop keeps it unassigned until an explicit ownership change.

Every Desktop label, title, menu name, and Project number derives from the same owner and current
Desktop UUID. A Project label uses the Project ID as its window identity. An unowned Desktop is
named `Desktop N`. Refreshes update existing labels after name or assignment changes. WindowServer
placement is reconciled to ownership; dragging or stale placement cannot edit saved ownership.

Desktop arrival selects its owner when Desktop following is enabled. An ordinary topology or
name refresh preserves an explicitly selected Project, including an unassigned one. Explicit Back
navigation retains its saved Project selection. Disabling Desktop following keeps the explicitly
selected Project. Unassigned application windows may join the Desktop owner under the normal
membership rules. Selecting a Project without the current Desktop never captures that Desktop's
windows; explicit and shared window memberships remain available.

## Tests

- `testAssigningOwnerClearsDisplacedAssignmentAndPreservesOtherProjects`
- `testUnassigningDesktopClearsOwnerHome`
- `testExplicitAssignmentRepairsAllConflictingOwners`
- `testInvalidAssignmentsDoNotUnassignExistingOwner`
- `testReassigningCurrentOwnerIsIdempotent`
- `testDesktopArrivalSelectsOwnerEvenWhenAnotherProjectWasSelected`
- `testRoutineRefreshPreservesAnExplicitProjectChoice`
- `testDesktopFollowingCanStillBeDisabled`
- `testStartupAndDeletedSelectionUseOwnerOrDesktop`
