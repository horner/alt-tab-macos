# Installed app catalog

An on-demand background scan covers standard Applications directories and their ordinary subdirectories. App bundles are terminal entries: embedded helpers are not scanned. Canonical paths deduplicate overlapping roots and symlinks; separate installations remain selectable. Only executable APPL bundles that are not background-only are admitted.

The picker reuses an in-memory snapshot while refreshing. Search uses the existing fuzzy matcher for names, filenames, action labels, and Messages aliases. Matching apps sort by adaptive frequency, then most recent use, match quality, name, and installation path. Empty search uses the same order, with an alphabetical fallback for apps without usage history. An app that does not match the query is excluded regardless of usage.

Usage is keyed by canonical installation path. App-activation notifications update recency; successful picker actions also update frequency. Dates, lifetime counts, and decaying frequency weights persist in UserDefaults across app restarts; see `AppUsageScoreSpecs.md`. The switcher's existing window focus history seeds the first picker, including its initial MRU order for apps without recorded dates. Usage is frozen while a picker is open, so activating another app cannot reshuffle a selection. Defaults and canonical-path work run on a serial background queue.

Scan and search completions update only their current picker/request. Refreshing the initial list selects the highest-ranked result unless the user has explicitly selected another one. Return waits for the initial usage snapshot and filter before choosing, so cached recency-only ordering cannot launch the wrong app. App icons load only for displayed rows, off the main thread, and remain in a bounded in-memory cache. Late icon callbacks update a row only if it still represents that installation.

Tests:
- `testScanFindsAppsInSubfoldersWithoutEmbeddedHelpers`
- `testScanDeduplicatesRootsAndLinksButKeepsSeparateInstallations`
- `testScanSkipsBackgroundAndInvalidApps`
- `testScanIncludesHiddenFlagAppsButSkipsDotDirectories` — Safari's Applications entry can carry the Finder hidden flag; dot directories remain excluded.
- `testNamesFallBackToFilenameAndUseDisplayName`
- `testMessageAliasesAndAppNamesSelectTheirActions`
- `testEmptySearchSortsAndUnmatchedSearchIsEmpty`
- `testRecentlyUsedAppsLeadEmptySearchWithAlphabeticalFallback`
- `testRecentChromeLeadsCSearchAheadOfAlphabeticalPrefixMatches`
- `testRecencyBelongsToTheSelectedInstallation`
- `testTrendingFrequencyRanksMatchingAppsAheadOfRecency`
