# ProjectReattachResolver

Saved assignments use exact bundle identifiers and literal window titles. Tracking removal retains patterns.
A unique owning Project restores a reopened window; conflicting Projects remain unassigned automatically.
Explicit exclusions survive reboot. Linked Desktop capture cannot override a saved or live owner.
Titles that change do not match an earlier pattern; membership saves remember titles of live members.
No app polling or title-substring guessing is used. Discovery supplies the current cached title.
New windows can join the active Project only on the current Desktop, with no saved/live owner,
and at least 30 seconds after the owning app launches. This conservative startup grace also skips
manually created windows in those first 30 seconds; linked Desktop assignment still applies.

## Test scenarios

- **testExactAppAndTitleRestoreOwner** — exact app and title resolve to the saved Project.
- **testDifferentAppOrChangedTitleDoesNotGuess** — bundle prefixes and title substrings are insufficient.
- **testConflictingProjectsRemainDetectablyAmbiguous** — multiple owners are reported so the caller can decline automatic assignment.
- **testEmptyTitlesCannotClaimWindows** — blank titles cannot create a match.
- **testAppStartupWindowsDoNotJoinActiveProject** — restoration bursts during the startup grace do not contaminate the active Project.
- **testOrdinaryNewWindowJoinsActiveProject** — a new unassigned window on the current Desktop joins after the grace period.
- **testSavedOwnerOtherDesktopAndRediscoveryBlockActiveAssignment** — restoration priority and Desktop scope prevent active-Project capture.
- **testPatternsSurviveEncodingWithoutRunningApp** — durable assignments encode independently of process identity.
