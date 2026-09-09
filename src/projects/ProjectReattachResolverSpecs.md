# ProjectReattachResolver

History stores app identifiers, observed titles, available browser URLs, and stable Desktop UUIDs. Closing a tracked window preserves its latest cached title and Desktop, while saves retain earlier observed patterns.
Exact app/URL matches take priority, followed by app/title matches when either URL is unavailable, including on another Desktop. Desktop context separates identical titles; when no title matches, one Project in the same app/Desktop history can recover a changed title. Conflicting history stays unassigned automatically. Patterns without a Desktop remain compatible.
Explicit exclusions survive reboot and match a known URL even when the title changes. Known live identity membership takes priority over a broad title exclusion; an explicit identity exclusion always blocks restoration. Linked Desktop capture cannot override a unique saved owner or another live owner. A linked or explicitly active Project can resolve ambiguous saved history when it is one of the candidate owners; unrelated Projects cannot capture that ambiguity.
New windows can join the active Project only on the current Desktop, with no saved/live owner,
and at least 30 seconds after the owning app launches. This conservative startup grace also skips
manually created windows in those first 30 seconds; linked Desktop assignment still applies.
Opening the window switcher also repairs unassigned windows on the current Desktop into the active
custom Project after rendering. That explicit-use repair does not require a creation marker or the
startup grace; it waits for identity/URL restoration and follows the same ownership and exclusion rules as linked Desktop capture.
Restored assignments produce a non-activating notice, grouped over one second; it reports Projects/counts and recaptures on a different Desktop. It does not move windows between Desktops.

## Test scenarios

- **testExactAppAndTitleRestoreOwner** — exact app and title resolve to the saved Project.
- **testDifferentAppOrChangedTitleDoesNotGuess** — bundle prefixes and title substrings are insufficient.
- **testConflictingProjectsRemainDetectablyAmbiguous** — multiple owners are reported so the caller can decline automatic assignment.
- **testEmptyTitlesCannotClaimWindows** — blank titles cannot create a match.
- **testAppStartupWindowsDoNotJoinActiveProject** — restoration bursts during the startup grace do not contaminate the active Project.
- **testOrdinaryNewWindowJoinsActiveProject** — a new unassigned window on the current Desktop joins after the grace period.
- **testSavedOwnerOtherDesktopAndRediscoveryBlockActiveAssignment** — restoration priority and Desktop scope prevent active-Project capture.
- **testDesktopProjectResolvesAmbiguousSavedOwners** — the linked or explicitly active Project breaks a historical tie only when it is a candidate owner.
- **testAutomaticAssignmentPreservesLiveAndUniqueSavedOwners** — contextual capture cannot steal a live window or override a unique saved owner elsewhere.
- **testAutomaticAssignmentAcceptsUnownedAndSameProjectWindows** — unowned windows can join and the same Project can retain its members.
- **testPatternsSurviveEncodingWithoutRunningApp** — durable assignments encode independently of process identity.

- **testMovingOneOfTwoIdenticallyTitledWindowsPreservesTheirSeparateAssignments** — live identity membership outranks a broad title exclusion, while an explicit identity exclusion always blocks restoration, including stale membership.
- **testNewIdentityRequiresUniqueUnexcludedPattern** — a newly launched window needs one unexcluded pattern owner.

- **testChangedTitleRestoresFromUniqueAppDesktopHistory** — a login/error title can rejoin its original Project on the same Desktop.
- **testExactTitleRestoresEvenOnAnotherDesktop** — an exact match recaptures a window on a different Desktop.
- **testDesktopSeparatesIdenticalTitlesInDifferentProjects** — Desktop UUID selects the correct Project among identical title matches.
- **testUnknownDesktopAndConflictingDesktopHistoryDoNotGuess** — ambiguous or unrelated Desktop history cannot claim a window.
- **testLegacyPatternWithoutDesktopStillDecodes** — old persisted patterns remain readable.

- **testLastSeenDoesNotChangeMatchingIdentity** — updating observation time does not duplicate an assignment or break matching.
- **testLastSeenTimestampSurvivesEncoding** — history observation times persist across restarts.

- **testURLRestoresProjectDespiteSignInTitleChange** — the observed URL outranks a conflicting title-only match.
- **testDifferentKnownURLsDoNotMatchOnlyByTitle** — identical sign-in titles cannot override differing known URLs.
- **testSharedURLUsesDesktopToResolveProject** — Desktop context disambiguates a common login URL.
- **testURLSurvivesEncodingAndOlderHistoryStillLoads** — URLs persist and older history without them remains readable.

- **testObservationMatchesChangedTitleByURLWithoutConflatingDifferentURLs** — removal/exclusion matching follows a known URL through title changes and keeps different known URLs separate.
