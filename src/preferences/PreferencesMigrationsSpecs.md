# PreferencesMigrations — Specs

## Summary

`PreferencesMigrations` upgrades a user's stored `UserDefaults` from an older AltTab schema. It runs once per launch (`migratePreferences()`), comparing the stored `preferencesVersion` to the explicit upstream schema version `11.6.1`, independently of the bundle's product version. Each registered migration applies when the stored schema is at or below its threshold. Successful initialization stores the current schema marker; a newer stored marker is never lowered. Most migrations are small, self-contained `UserDefaults` transforms (rename a key, remap an index, split one key into two, convert a Bool string to an enum index).

**Why this is the highest-value safety net:** these run on every upgrade against real users' data. A mistake silently corrupts settings for the entire installed base — and there's no UI signal when it goes wrong. The tests pin each transform's exact input→output.

## Behavior & edge cases

- **Version gating (`shouldRun`)** uses `String.compare(_, options: .numeric)`. A migration with threshold `T` runs iff the stored version is **≤ T** (i.e. compare is *not* `.orderedDescending`). The `.numeric` option is load-bearing: lexically `"9" > "10"`, but numerically `9 < 10`, so a user on `9.x` still gets a `10.x` migration.
- **Fork release numbering:** only the `com.horner.alt-tab-projects` bundle treats historical numeric `0.1.x` markers as upstream schema `11.6.1`. Those releases already store modern settings; rerunning upstream `6.x–10.x` transforms would remap current language, window and shortcut choices. This fixed baseline still admits future schema migrations. Other bundle IDs retain upstream version gating. No preferences are imported across bundle domains.
- **Fresh installs and relaunches:** missing and `#VERSION#` markers initialize at the current schema without running legacy transforms. Settings chosen after the first launch remain unchanged on subsequent launches. Updating a migration requires advancing `currentSchemaVersion` past its threshold.
- **Order matters**: `updateToNewPreferences` runs migrations newest-threshold-first; some depend on keys earlier ones leave behind. The per-migration tests isolate each, but the registration list in `updateToNewPreferences` is the integration contract.
- **Idempotency**: `migrateExceptionsTitleArray` must be safe to re-run — already-migrated (array-form) data fails to decode into the legacy (`String?`) shape, triggering an early return that leaves data untouched.
- **A quirk worth knowing** (pinned by a test): the global→per-shortcut grouping migration copies the global value into the indexed keys, but because index 0's key *is* the old global key, that key is removed at the end — so slot 0 ends up unset while slots 2…10 hold the value.
- **Testability**: production reads/writes `UserDefaults.standard`; the tests inject an isolated suite via `PreferencesMigrations.defaults` (reset in `tearDown`) so they never touch the dev machine's real prefs.
- **Not covered** (documented gaps): `migrateShortcutPreferencesToSecureCoding` (needs the real NSKeyedArchiver/ShortcutRecorder codec, stubbed compile-only) and `migrateLoginItem` (mutates real Login Items via deprecated LaunchServices APIs). Startup-path tests use upstream markers newer than that Login Items threshold.

---

## Test scenarios

Mirrors `PreferencesMigrationsTests.swift` 1:1.

### A. Version gating (`shouldRun`)
- **testVersionGatingRunsForOlderStoredVersion** — stored `6.0.0` ≤ threshold `10.13.0` → runs.
- **testVersionGatingRunsForEqualVersion** — stored == threshold → runs.
- **testVersionGatingSkipsForNewerStoredVersion** — stored `11.0.0` > `10.13.0` → skipped.
- **testVersionGatingUsesNumericCompareNotLexical** — stored `9.0.0` < `10.0.0` numerically → runs (guards the `.numeric` option).
- **testProjectsReleaseVersionsPreserveCurrentSettingsAcrossLaunches** — fork `0.1.0` and `0.1.4` markers initialize the upstream schema without changing modern choices, including a second launch.
- **testFreshInstallPreservesSettingsChosenBeforeRelaunch** — choices saved after the first launch survive subsequent launches.
- **testCurrentUpstreamSchemaPreservesSettingsInProjectsBuild** — an upstream `11.6.1` marker remains valid in the fork.
- **testLegacyUpstreamMigrationsRunOnlyOnce** — upstream `6.43.1`, `7.26.0` and `10.12.0` markers apply their language/window transforms once, then retain those results.
- **testNewerSchemaMarkerSurvivesOlderBuildLaunches** — an older build neither transforms newer settings nor lowers their marker.
- **testPlaceholderVersionStartsAtCurrentSchema** — an unversioned development placeholder skips historical transforms.

### B. Grouping moved global → per-shortcut
- **testGroupingCopiesGlobalShowAppsOrWindowsToPerShortcutKeysAndRemovesGlobal** — global value lands in `showAppsOrWindows2…10`; the global key is removed (slot 0 ends nil — the documented quirk).
- **testGroupingDoesNotOverwriteExistingPerShortcutValue** — a pre-set per-shortcut key is left untouched.
- **testGroupingConvertsShowTabsAsWindowsBoolGlobalToEnumIndex** — `"false"` → `"0"` across indexed keys; global removed.
- **testGroupingConvertsPreExistingPerShortcutBoolString** — a leftover `"true"` per-shortcut Bool string → `"1"`.

### C. Language index remap (59 → 21 cases)
- **testLanguageRemapsKnownIndex** — `5` → `2` via the remap table.
- **testLanguageRemapsLastKnownIndex** — `58` → `21` (table boundary).
- **testLanguageRemovedLanguageFallsBackToSystemDefault** — an index no longer valid → `0`.
- **testLanguageNoStoredValueIsNoOp** — no stored language → key stays absent.

### D. Blacklist → exceptions (key rename)
- **testBlacklistCopiedToExceptionsAndRemoved** — `blacklist` value copied to `exceptions`; `blacklist` removed.
- **testBlacklistDoesNotOverwriteExistingExceptions** — existing `exceptions` preserved; `blacklist` still removed.

### E. Legacy blacklists → structured exceptions (faithful JSON)
- **testExceptionsFromDontShowBlacklistBecomesHideAlways** — `dontShowBlacklist` entry → `ExceptionEntry(hide: .always, ignore: .none)`; old key removed.
- **testExceptionsFromDisableShortcutsOnlyFullscreenBecomesIgnoreWhenFullscreen** — `disableShortcutsBlacklist` + `…OnlyFullscreen` → `ignore: .whenFullscreen`.

### F. `windowTitleContains` String → [String]
- **testTitleArrayWrapsLegacyStringIntoArray** — legacy string `"abc"` → `["abc"]`.
- **testTitleArrayEmptyLegacyStringBecomesNil** — legacy empty string → `nil`.
- **testTitleArrayIsIdempotentOnAlreadyMigratedData** — already array-form → unchanged (early return).

### G. `showWindowlessApps` value remap
- **testShowWindowlessAppsOldShowAtEndBecomesTwo** — old `"0"` (showAtTheEnd) → `"2"`.
- **testShowWindowlessAppsOtherValueBecomesOne** — any other value → `"1"`.

### H. Show-windows checkbox → dropdown
- **testShowWindowsCheckboxTrueBecomesShow** — `"true"` → `"0"` (.show).
- **testShowWindowsCheckboxFalseBecomesHide** — `"false"` → `"1"` (.hide).

### I. Gestures split
- **testGesturesFourFingerRemapsToHorizontal** — `"2"` (4-finger) → `"3"` (4-finger-horizontal).
- **testGesturesOtherValueUnchanged** — other values untouched.

### J. cursorFollowFocus toggle → dropdown
- **testCursorFollowFocusTrueBecomesAlways** — `"true"` → `1`.
- **testCursorFollowFocusFalseBecomesNever** — `"false"` → `0`.

### K. Menubar icon hidden-value → shown toggle
- **testMenubarIconHiddenValueSplitsIntoShownToggle** — `menubarIcon == "3"` → `menubarIcon "0"` + `menubarIconShown "false"`.

### L/M. Width / size splits
- **testMinMaxWidthZeroBecomesOne** — `windowMinWidthInRow "0"` → `"1"`.
- **testMaxSizeOnScreenSplitsIntoWidthAndHeight** — `maxScreenUsage` → both `maxWidthOnScreen` + `maxHeightOnScreen`.

### N. Shortcut key cleanup + index move
- **testNextWindowShortcutStripsHoldModifierChars** — hold-modifier chars removed from `nextWindowShortcut` (`"⌥⇥"` → `"⇥"`).
- **testShortcutIndexesMoveSuffix4To10AndSetCount** — suffix `4` → `10`; `shortcutCount` set to `3` when a 3rd shortcut exists.

### P. Dropdowns: English text → indexes
- **testDropdownTextValuesBecomeIndexes** — `appsToShow "Active app"` → `"1"`; `theme "❖ Windows 10"` → `"1"`.
