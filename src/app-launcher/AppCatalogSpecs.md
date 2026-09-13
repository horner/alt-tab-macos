# Installed app catalog

An on-demand background scan covers standard Applications directories and their ordinary subdirectories. App bundles are terminal entries: embedded helpers are not scanned. Canonical paths deduplicate overlapping roots and symlinks; separate installations remain selectable. Only executable APPL bundles that are not background-only are admitted.

The picker reuses an in-memory snapshot while refreshing. Search uses the existing fuzzy matcher for names, filenames, action labels, and Messages aliases. Matching apps sort by most recent use first, then match quality, name, and installation path. Empty search uses the same recency order, with an alphabetical fallback for apps without usage history. A more recent app that does not match the query is excluded.

Usage is keyed by canonical installation path, observed through the existing application-activation notification, and recorded after successful picker actions. Dates persist in UserDefaults across app restarts. The switcher's existing window focus history seeds the first picker, including its initial MRU order for apps without recorded dates. Usage is frozen while a picker is open, so activating another app cannot reshuffle a selection. Defaults and canonical-path work run on a serial background queue.

Scan and search completions update only their current picker/request. Refreshing the initial list selects the most recent result unless the user has explicitly selected another one. App icons load only for displayed rows, off the main thread, and remain in a bounded in-memory cache. Late icon callbacks update a row only if it still represents that installation.

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
