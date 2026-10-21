# Project window assignment

The window switcher includes the active custom Project's members plus unassigned windows on the
current Desktop. The fallback is immediate; eligible windows are assigned after the first frame.
Windows on another Desktop and windows already belonging to another Project are not added by the
fallback. Ordinary shortcut filters and the Project-label Show/Hide preference still apply.

## AltTabDebug regression

Three conditions combined to leave the Settings window outside its Desktop's linked Project:

1. Discovery supplied an empty Space list for AltTab's own windows, skipping the WindowServer lookup.
2. Assignment ran during discovery, but did not retry when a subsequent Space update supplied the real
   Desktop. The active-Project creation rule also intentionally skips the app's startup grace period.
3. Saved history from older Project-label windows named more than one potential owner for the same
   app and Desktop. Automatic capture rejected that ambiguity even when the linked Project was one
   of the candidates.

Ordinary AltTab windows now receive the same off-main Space lookup as other windows. Space changes
retry identity restoration and linked-Desktop assignment. A linked or explicitly active Project can
resolve ambiguous history when it is one of the candidates; a unique saved owner elsewhere, another
live owner, and explicit removals still prevent automatic reassignment. Local explicitly removed
windows remain reachable through the fallback.

The QA snapshot had a separate copy of filtering that omitted Projects, so its `shown` value could
disagree with the switcher. It now calls the same filtering function and also reports each window's
live `projectIds`. QA reads never trigger assignment.

## Verification

- 171 focused tests passed across membership, scope, restoration, labels, admission, Space updates,
  and ordinary window filtering.
- A production Projects adapter check exercised immediate fallback, deferred persistence, identity
  readiness, late Space updates, ambiguous history, exclusions, other live owners, stale active
  Projects, closed windows, and label exclusion.
- After restarting the Debug build, the AltTabDebug Settings window automatically joined the linked
  Project. Both live membership and the persisted process/window identity were verified.
- Opening the actual switcher and reading its rendered tiles confirmed the AltTabDebug tile was
  present. The switcher was then dismissed without changing focus to another destination.
