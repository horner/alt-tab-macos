# AltTab Projects

**Objective:** Add **Projects** to AltTab: isolated collections of windows that Alt-Tab cycles within, so unrelated work stays apart. The existing Spaces switcher stays as it is — it moves between macOS Desktops, and people need that. Projects are a separate, **opt-in** feature (a single `projectsEnabled` preference, off by default) with their own shortcut and panel, in a new `src/projects/` folder. Every macOS Space gets an automatic Project record, so the first app opened on a Desktop gives it a sticky name; a user can also create *custom* Projects that gather windows from any Space. While a custom Project is active, Alt-Tab lists only its members, and windows opened during that time join it. Both panels' tiles grow a thumbnail, and a user can choose any window as the icon of a Project or a Desktop, optionally pinning that picture permanently. The work is meant to become an upstream PR, so it touches upstream code in as few, small, listed places as possible: `WindowFilterResolver.shouldShow()` is a pure predicate that takes one more defaulted parameter, and everything else lives in new folders or in the Spaces-switcher files this fork already owns.

**Status:** 1 of 9 milestones complete

## Working agreement

Read this before touching code. It governs how this plan is executed.

- Work the tasks in order, top to bottom. Do not skip ahead or reorder.
- **Commit granularity** is set per milestone in its `Commit:` field. `per task` means one commit per checkbox; `per milestone` means one commit when the whole milestone is verified.
- **Every commit must also tick the boxes it completes.** The plan changes in the same commit as the code, so the diff shows which files belong to which step. A code commit that leaves the plan untouched is an incomplete commit.
- **Commit messages:** Conventional Commits, enforced by `commitlint.config.js` (`@commitlint/config-conventional`) via a git hook. Type from `feat|fix|refactor|perf|chore|docs|style|test|build`, then a lowercase imperative subject with no trailing period. Write the subject **for a changelog reader, not for a reviewer of this plan** — the house style is `feat: switch between Spaces with a dedicated shortcut`, `fix: a closed window may linger in the switcher`, `perf: fewer scans for windows an app does not list`. Never mention milestone or task numbers in a commit subject.
- **Upstream touch budget.** Files outside `src/projects/`, `src/spaces/`, `src/grid-panel/` and `plan/` may only be edited where this plan names them (see "Upstream touch budget" in Context). If a task seems to need another file, stop and ask — do not widen the PR.
- Tick `[x]` only when the task is done *and* the milestone's verification still passes. Use `[~]` for in progress and `[!]` for blocked.
- Update the milestone `Status:` line and the top-level `Status:` count as you go.
- **STOP and ask the dispatcher** when: a step is blocked; the instructions don't match the code you actually find; verification fails twice on the same task; the task needs a decision that isn't written here; or finishing it would require touching a file not listed in the milestone.
- Never delete or reword a task to make it fit reality. Append a `> Note:` under it and raise the discrepancy.
- Answer open questions by asking, not by picking. Record the answer in the Decisions section.

## Context

### Branch and PR shape

- Fork: `origin` = `github.com/horner/alt-tab-macos`; upstream = `github.com/lwouis/alt-tab-macos`, `upstream/master` at `2f3c6773` (v11.6.0). `origin/master` (`c67c8089`) adds one Sparkle build fix on top.
- Branch `horner` (`237c1600`, "feat: switch between Spaces with a dedicated shortcut") holds the Spaces switcher. **Everything in [src/spaces/](src/spaces/) is this fork's code, not upstream's**, and so are the seams that commit already edited. Projects build on top of that commit.
- The PR diff to keep small is `git diff upstream/master`. Its file list is the thing to verify at the end of every milestone.

### Repo conventions that this work will be held to

From [AGENTS.md](AGENTS.md):

- Swift 5.8, AppKit only. No Interface Builder, no SwiftUI.
- Compact code. No blank-line-separated statement groups inside a method — split into sub-methods instead. Guard clauses first, happy path underneath.
- **Triad pattern** for any pure logic: `Foo.swift` + `FooSpecs.md` + `FooTests.swift`, co-located. Every XCTest method must have a matching scenario line in the spec. The `.claude/skills/audit-specs-tests` skill checks this; run it after adding a triad.
- Comments state only what the code cannot show — OS/API behaviour, measured timings, private-API notes, invariants. No history, no narration. Re-read comments next to code you change.
- Latency: nothing that can stall may run before the visible work on the summon/keystroke path. `NSResponder`/`NSCell` subclasses are main-thread-only; `NSWorkspace` and `NSRunningApplication` are documented thread-safe. See [src/main-thread-ipc.md](src/main-thread-ipc.md).
- Build with the command in [ai/build.sh](ai/build.sh), never Xcode.

### Upstream touch budget

The complete list of upstream files this plan may edit, and how. Anything not here is off-limits without asking.

| File | Allowed edit | Task |
|---|---|---|
| [src/switcher/state/WindowFilterResolver.swift](src/switcher/state/WindowFilterResolver.swift) | one defaulted parameter `activeProjectMembers: Set<String>? = nil` and one clause | 1.4 |
| [src/switcher/state/Windows.swift](src/switcher/state/Windows.swift) | pass that argument at line 154; one call in `appendWindow()`; one call in `removeWindows()` | 1.5, 2.5, 4.4, 8.3 |
| [src/preferences/Preferences.swift](src/preferences/Preferences.swift) | merge `projectsDefaultValues` immediately after the Spaces defaults; generalise the `key == "exceptions"` JSON branch in `set()`; extend `spacesShortcutKeys` (already this fork's line) | 1.6, 2.1, 3.5 |
| [src/Menubar.swift](src/Menubar.swift) | one "Projects" submenu block in `initialize()` and one refresh call in `menuWillOpen` | 2.7, 6.5 |
| [src/switcher/ATShortcut.swift](src/switcher/ATShortcut.swift), [src/switcher/ShortcutAction.swift](src/switcher/ShortcutAction.swift), [src/preferences/settings-window/tabs/controls/ControlsTab.swift](src/preferences/settings-window/tabs/controls/ControlsTab.swift), [src/preferences/settings-window/SettingsSearchIndex.swift](src/preferences/settings-window/SettingsSearchIndex.swift), [src/events/KeyboardEventsTestable.swift](src/events/KeyboardEventsTestable.swift), [src/_test-support/Mocks.swift](src/_test-support/Mocks.swift), [src/App.swift](src/App.swift) | **only the lines the Spaces commit already touches**: generalise each `SpacesSwitcher` special case into a list lookup, add the Projects sheet next to the Spaces sheet, add startup calls next to the Spaces ones | 3.2, 3.5 |
| [alt-tab-macos.xcodeproj/project.pbxproj](alt-tab-macos.xcodeproj/project.pbxproj) | register new files | many |
| [resources/l10n/Localizable.strings](resources/l10n/Localizable.strings) | regenerated by script | many |

### The window filtering pipeline (the insertion point for Projects)

- [src/switcher/state/WindowFilterResolver.swift](src/switcher/state/WindowFilterResolver.swift) lines 10–52 — `WindowFilterResolver.shouldShow()`, a pure static predicate taking `WindowState`, `ApplicationState` and a long list of defaulted `Bool` flags. Every existing filter (`appsToShow`, `spacesToShow`, `screensToShow`, hidden/minimised/fullscreen/windowless, exceptions, tabs) is one clause here. **This is where the Project clause goes.**
- [src/switcher/state/Windows.swift](src/switcher/state/Windows.swift) line 154 — the single call site, inside `refreshIfWindowShouldBeShownToTheUser()`, which maps a preference snapshot onto those flags and assigns `window.shouldShowTheUser`.
- [src/switcher/state/Window.swift](src/switcher/state/Window.swift) line 42 — `var shouldShowTheUser = true`, a plain stored flag.
- [src/switcher/state/Windows.swift](src/switcher/state/Windows.swift) line 51 — `Windows.shouldDisplay()` combines `shouldShowTheUser` with the search query; [src/switcher/main-window/TilesView.swift](src/switcher/main-window/TilesView.swift) line 535 `layoutTileViews()` walks `Windows.list` through it.
- Ordering: `Windows.sort()` (line 504) → pure `WindowOrderResolver.isOrderedBefore()` ([src/switcher/state/WindowOrderResolver.swift](src/switcher/state/WindowOrderResolver.swift) lines 30–100). Focus recency is `lastFocusOrder`, `0` = most recent.

### Window identity — the constraint that shapes membership

`TrackedWindow.id` is a string, `"wid-N"` for real windows and `"pid-N"` for windowless app placeholders, assigned once at construction ([src/switcher/state/TrackedWindowState.swift](src/switcher/state/TrackedWindowState.swift) line 20). It is the right in-session key for Project membership.

Nothing about a window is durable across processes. `cgWindowId`, `axUiElement`, `application.pid` and `tracked.id` are all lost when the owning app quits or when AltTab restarts; the wid is even **reused** by a different window. Only `bundleIdentifier` survives. That is why durable membership is deferred to Milestone 8 and modelled on the exceptions matcher rather than on ids.

- Window creation: `kAXWindowCreatedNotification` → `AxObserverRegistry.windowCreated()` ([src/window-tracking/AxObserverRegistry.swift](src/window-tracking/AxObserverRegistry.swift) line 453) → `Applications.applyObservedWindowCreated()` ([src/switcher/state/Applications.swift](src/switcher/state/Applications.swift) line 652) → `Applications.addDiscoveredWindow()` (line 328, on `BackgroundWork.axSemanticsQueue`, off-main) → `Windows.findOrCreate()` ([src/switcher/state/Windows.swift](src/switcher/state/Windows.swift) line 590) → `Windows.appendWindow()` (line 626).
- Window removal: `Windows.removeWindows()` ([src/switcher/state/Windows.swift](src/switcher/state/Windows.swift) line 800).
- Relaunch continuity is best-effort only: `retireSurfaceForReplacement()` / `restoreSurfaceContinuity()` (line 706), two seconds, same `AXUIElement`.

### Prior art to copy

- **Stored user rules matched against windows:** `ExceptionEntry` ([src/preferences/Preferences.swift](src/preferences/Preferences.swift) line 543) plus `ExceptionMatcher.hidesWindow()` / `hideMatches()` ([src/switcher/state/ExceptionMatcher.swift](src/switcher/state/ExceptionMatcher.swift) lines 30–60). Bundle-id **prefix** plus literal title **substring**, never regex. Permissive `Codable` decoder so a shape change cannot wipe user data.
- **Persisting a structured collection:** `CachedUserDefaults.json(key, Type.self)` ([src/preferences/Preferences.swift](src/preferences/Preferences.swift) line 126) to read; `Preferences.set()` (line 216) to write — which today **hardcodes `key == "exceptions"`** as the only key that gets `jsonEncode`. A second JSON preference must generalise that branch or it is stored as a non-string and silently reset on the next read.
- **A modal text prompt:** `UpgradeTab.presentActivationSheet` ([src/preferences/settings-window/tabs/UpgradeTab.swift](src/preferences/settings-window/tabs/UpgradeTab.swift) lines 278–305) — `NSAlert` + `NSTextField` accessory, `initialFirstResponder`, Escape via a cancel button's key equivalent.
- **Menu-bar items:** [src/Menubar.swift](src/Menubar.swift) `initialize()` lines 27–63, helper `addMenuItem(_ title:_ action:_ keyEquivalent:_ symbolName:_ color:_ target:)`. Built once; per-open updates in `MenubarMenuDelegate.menuWillOpen` (line 416).
- **A pure kernel with a triad:** `SpacesOrderResolver` ([src/spaces/SpacesOrderResolver.swift](src/spaces/SpacesOrderResolver.swift)) + `Specs.md` + `Tests.swift`. Copy its shape for every resolver below.
- **Thumbnails:** `Window.thumbnail: CALayerContents?` ([src/switcher/state/Window.swift](src/switcher/state/Window.swift) line 40), rendered by `LightImageLayer` ([src/switcher/main-window/TileView.swift](src/switcher/main-window/TileView.swift) lines 9–10), sized by `TileView.thumbnailSize()` line 704. `CALayerContents` carries a `CGImage` or a `CVPixelBuffer` (`.cgImage(...)` / `.pixelBuffer(...)` in [src/events/WindowCaptureEvents.swift](src/events/WindowCaptureEvents.swift) `deliver()` ~line 154). **No new capture API is introduced by this plan** — bursts wedged `replayd` machine-wide in #5861. A single fresh thumbnail goes through the existing throttled per-window request.

### The Spaces switcher, which this plan shares but keeps

- Space identity: `SpacesList.enumerate()` ([src/spaces/SpacesList.swift](src/spaces/SpacesList.swift) lines 109–134) reads only `"id64"` and `"type"` from each `CGSCopyManagedDisplaySpaces` dictionary. The same dictionary carries a `"uuid"` string — what macOS itself persists in `com.apple.spaces`; `id64` is session-scoped. Desktop records must key on the uuid to survive a reboot. **Verify at runtime first** (task 1.1).
- `SpaceItem`: `spaceId`, `desktopNumber` (0 = fullscreen), `isCurrent`, `label`; `activate()` (lines 21–30), `mostRecentlyFocusedWindow()` (44–49). `SpacesList`: `list`, `selectedIndex`, `mru`, `noteVisited()`, `startObservingSpaceChanges()` (79–89, `NSWorkspace.activeSpaceDidChangeNotification`), `refresh()`, `cycle()`, `label()` (136–143).
- Panel: `SpaceTileView` ([src/spaces/SpacesPanel.swift](src/spaces/SpacesPanel.swift) lines 4–92: `iconView`, `labelView`, static `sizingLabel`, `tileSize(for:)`, `update()`, `layout()`) and `SpacesPanel` (77–193: `show()`, `refreshHighlight()`, `layoutTiles()`, static `maxColumns()`). Grid balancing is `SpacesOrderResolver.gridColumns()`; `cycle()` and `initialSelection()` are generic over counts.
- Shortcut plumbing has **Spaces-specific `if`s at every seam** (all lines this fork already owns): [src/switcher/ATShortcut.swift](src/switcher/ATShortcut.swift) 47–48, 58–60, 69; [src/switcher/ShortcutAction.swift](src/switcher/ShortcutAction.swift) 39–41; [src/preferences/settings-window/tabs/controls/ControlsTab.swift](src/preferences/settings-window/tabs/controls/ControlsTab.swift) 782–783 (sheet), 791–807 (registration — note `.local` scope and bare binding for the previous-shortcut), 844, 967; `Preferences.spacesShortcutKeys` ([src/preferences/Preferences.swift](src/preferences/Preferences.swift) line 92); [src/events/KeyboardEventsTestable.swift](src/events/KeyboardEventsTestable.swift) 9–10; [src/_test-support/Mocks.swift](src/_test-support/Mocks.swift) 156–159. A second auxiliary switcher goes through the same seams — generalise each to a small list rather than adding a parallel `if`.
- Settings: `SpacesSheet` ([src/preferences/settings-window/tabs/controls/SpacesSheet.swift](src/preferences/settings-window/tabs/controls/SpacesSheet.swift)) with `searchableStrings`, presented via `ControlsTab.showSpacesSettings`, indexed at [src/preferences/settings-window/SettingsSearchIndex.swift](src/preferences/settings-window/SettingsSearchIndex.swift) line 83. `ProjectsSheet` copies this shape.

### Writing an image to disk

No precedent in the codebase; grep for `applicationSupportDirectory` first and follow it if one has appeared. Otherwise `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` + `Bundle.main.bundleIdentifier` + `project-icons/`. Encode a `CGImage` with ImageIO (`CGImageDestinationCreateWithURL`, PNG); turn a `CVPixelBuffer` into a `CGImage` with `CIImage(cvPixelBuffer:)` + `CIContext.createCGImage`. Off-main. Pinned pictures are files, not `UserDefaults` values.

### What must not change

- **The Spaces switcher keeps its behaviour, shortcuts, preference keys, sheet and strings.** Edits under [src/spaces/](src/spaces/) are limited to: reading the Space uuid (1.1), exposing enumeration with a defaulted fullscreen-inclusion flag for registry seeding (1.6), moving grid/tile rendering into a shared panel (3.1), richer tile content (5.3).
- **With `projectsEnabled` off, the app is indistinguishable from the Spaces commit alone** — no Project shortcuts registered, no filter, no menu items, no registry seeding beyond what Desktop naming/icons need. This is verified in every milestone.
- **macOS Space topology is not the feature and is never renamed:** [src/switcher/state/Spaces.swift](src/switcher/state/Spaces.swift) (`visibleSpaces`, `currentSpaceId`, `idsAndIndexes`, `refresh()`, `query()`, `applyTopology()`); `CGSSpaceID`; `Window.spaceIds` / `spaceIndexes` / `isOnAllSpaces`; `spacesToShow` / `SpacesToShowPreference` ([src/preferences/MacroPreferences.swift](src/preferences/MacroPreferences.swift) line 166); `WindowFilterResolver`'s `onlyVisibleSpaces` / `onlyNonVisibleSpaces` / `visibleSpaceIds`; `.spaceChangeSettled`.

### Vocabulary used below

- **Desktop Project** — the automatic per-Space record, keyed by Space uuid. Carries the Desktop's sticky name and chosen icon. Never filters Alt-Tab. Exists whether or not Projects are enabled; the user never sees the word "Project" for it — tiles say "Desktop N".
- **Custom Project** — user-created, has members (window ids), filters Alt-Tab while active, has a *home Space* (the Space current at creation). Only exists when Projects are enabled.
- **Active Project** — the one Alt-Tab is cycling within. Defaults to the current Desktop Project.
- **Icon source** — where a tile's picture comes from: most-recently-focused window, a user-chosen window, or a permanently pinned picture on disk.

### Key layout

Three switchers, three hold modifiers. Shipped defaults must stay upstream-compatible (the window switcher keeps ⌥); the layout the dispatcher actually wants — ⌘ windows, ⌥ Projects, ⌃ Spaces — is offered as a one-click preset, not forced. AltTab is designed to take priority over system shortcuts such as ⌘⇥ ([docs/contributing.md](docs/contributing.md) line 139), so ⌘ as the window-switcher hold is supported. Two switchers may **not** share a hold modifier: `RegisterEventHotKey` fails with `eventHotKeyExistsErr` (-9878) for the second one, which is why the Spaces switcher chose ⌃ (see the comment in [src/spaces/SpacesPreferences.swift](src/spaces/SpacesPreferences.swift)).

| Switcher | Key | Shipped default | Recommended preset | Where defined |
|---|---|---|---|---|
| Windows (upstream) | hold, shortcut 1 / 2 / 3 | ⌥ / ⌥ / ⌥ | ⌘ / ⌘ / unchanged | `Preferences.defaultValues` `holdShortcut{0,1,2}` — **not edited**; the preset writes the user's values via `Preferences.setShortcut` |
| Windows | next | ⇥ / ` / — | unchanged | upstream |
| Windows | previous, focus, cancel, close, minimise, fullscreen, quit, hide, search | ⇧, ↩, ⎋, W, M, F, Q, H, — | unchanged | upstream |
| Windows | **toggle membership in active Project** (new, M7) | P, registered only when Projects are enabled | P | `ProjectsPreferences` `toggleProjectMembershipShortcut` |
| Spaces (fork) | hold / next / previous / cancel | ⌃ / ⇥ / ⇧ / ⎋ | unchanged | `SpacesPreferences.spacesDefaultValues` |
| Spaces | on release | focus selected | unchanged | `spacesShortcutStyle` |
| Projects (new) | hold | **unbound** — ⌥ would collide with the window switcher's default | ⌥ | `ProjectsPreferences` `holdProjectsShortcut` |
| Projects | next / previous / cancel | ⇥ / ⇧ (bare, `.local`) / ⎋ | unchanged | `nextProjectShortcut`, `previousProjectShortcut`; Escape in `ProjectsPanel.keyDown` |
| Projects | on release | activate selected | unchanged | `projectsShortcutStyle` |
| Name prompt | confirm / cancel | ↩ / ⎋ | — | `ProjectNamePrompt` (NSAlert buttons) |
| Menu-bar items | none | — | — | no key equivalents; the menu is reached by mouse |

Dependency worth knowing: with an empty Desktop, `SpaceItem.activateViaSystemShortcut()` posts ⌃+digit and relies on the macOS "Switch to Desktop N" shortcuts being enabled in System Settings → Keyboard → Mission Control. The Project switcher never needs this: a custom Project with members focuses a member; one without members only becomes active.

## Milestones

### Milestone 1 — Project model, Space identity, master switch, and the membership filter

**Objective:** A Project is a first-class object; every Space has a Desktop Project; `WindowFilterResolver` can narrow the switcher to a custom Project's members; `projectsEnabled` exists and is off. Nothing is visible to the user — correctness is proven by unit tests and the Space uuid probe.
**Commit:** per task
**Status:** complete

- [x] 1.1 — Read `"uuid"` from each `CGSCopyManagedDisplaySpaces` dictionary in `SpacesList.enumerate()` into a new `SpaceItem.uuid: String`, with a temporary debug log of every Space's uuid. Relaunch, then log out and back in, and confirm each Desktop keeps its uuid. Record the result as a `> Note:` here. If absent, stop and ask — the fallback (`"ManagedSpaceID"`) changes the persistence story. Files: `src/spaces/SpacesList.swift`

> Note: 2026-09-07 runtime probe found a nonempty `uuid` string on all 13 Desktops (`spaces=13 missingUuid=0`). The same 13 id64/uuid pairs were observed before launch, after launch, and after quitting/relaunching AltTabDebug. Debug build passed; all 1,178 existing tests passed without edits. Logout/login verification is deferred with the dispatcher’s explicit approval; it remains pending. `plan/space-plan.md` was already absent and untracked at the start of this work; no deletion is needed.

- [x] 1.2 — Create `Project` and the `Projects` registry, *depends on 1.1*. `Project`: `id: String`, `kind` (desktop carrying the Space uuid, or custom), `homeSpaceUuid`, `name: String?` (user-set), `autoName: String?` (sticky derived), `members: Set<String>` of `TrackedWindow.id`, `iconSource` (most-recent only for now). `Projects`: `list`, `active`, `byId`, `forSpace(uuid:)` creating a Desktop Project on first sight, `createCustom(homeSpaceUuid:)`, `delete(id:)`, `add(windowId:to:)`, `remove(windowId:from:)`, and `static var isEnabled` reading the preference. Files: `src/projects/Projects.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`

> Note: Debug build passed. The existing test target and window/Spaces behavior are unchanged; the registry has no callers yet.
- [x] 1.3 — Add `ProjectMembershipResolver` as a pure kernel with its triad, *depends on 1.2*: given `isEnabled`, the active Project's kind and members, return the ids to filter by, or nil when no filtering applies. Disabled → nil; Desktop Project → nil (the `spacesToShow` clause already expresses it). Scenarios: disabled filters nothing; desktop filters nothing; custom keeps only members; an id whose window is gone is ignored; an empty custom Project yields an empty set, not everything; a window may sit in several Projects. Files: `src/projects/ProjectMembershipResolver.swift`, `src/projects/ProjectMembershipResolverSpecs.md`, `src/projects/ProjectMembershipResolverTests.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`

> Note: Debug build and all 1,184 tests passed. audit-specs-tests: 6 tests and 6 matching scenarios, no orphans or description drift. Existing WindowFilterResolver and SpacesOrderResolver tests remain byte-for-byte unchanged.
- [x] 1.4 — Add one clause to `WindowFilterResolver.shouldShow()`: a defaulted `activeProjectMembers: Set<String>? = nil` parameter that, when non-nil, requires the window's tracked id to be in it. The nil default keeps every existing call and test at its current result. Files: `src/switcher/state/WindowFilterResolver.swift`

> Note: Debug build and all 1,184 tests passed with the pre-existing WindowFilterResolver tests unmodified. The upstream change is the defaulted parameter, one membership clause, and its adjacent predicate description.
- [x] 1.5 — Pass the resolver's result at the line-154 call site, *depends on 1.3 and 1.4*, and add one `Projects.windowsRemoved(_:)` call in `Windows.removeWindows()` that purges ids from every custom Project. Files: `src/switcher/state/Windows.swift`, `src/projects/Projects.swift`

> Note: Debug build passed; the unchanged test target remains at 1,184 passing tests from 1.4. A standalone smoke check of the actual registry and resolver passed desktop identity, disabled creation/filtering, overlapping memberships, removal from both Projects, empty filtering, and deletion. Windows.swift gained only the filter argument and one removal hook.
- [x] 1.6 — Add the `projectsEnabled` preference (default `false`) in a new `ProjectsPreferences` extension, and seed the registry at launch from `SpacesList.enumerate()` plus a `Projects`-owned `activeSpaceDidChangeNotification` observer (do not edit `SpacesList.startObservingSpaceChanges()`), so every Space has its Desktop Project and `Projects.active` tracks the current Space. Files: `src/projects/ProjectsPreferences.swift`, `src/projects/Projects.swift`, `src/App.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`

> Note: Debug build and all 1,184 tests passed; both protected test files are unchanged. Defaults remain off. The registry seeds from all enumerated Spaces and owns its main-queue Space-change observer. Diff reviewed against the two approved budget additions; no further upstream seams were added. UUID relaunch evidence is recorded in 1.1; logout/login remains explicitly deferred.

> Note: 2026-09-07: the dispatcher approved two narrow budget additions: merge `projectsDefaultValues` beside the existing Spaces defaults in `Preferences.swift`, and expose `SpacesList.enumerate(includeFullscreen: Bool = false)` so only registry seeding includes hidden fullscreen Spaces. Task 1.6 may additionally edit those two files; the Spaces switcher keeps the default enumeration behavior.


**Verification:**
1. `bash ai/build.sh > /tmp/at-build.log 2>&1` then `grep -E "error:|BUILD (SUCCEEDED|FAILED)" /tmp/at-build.log | grep -v iOSSimulator | sort -u` → `** BUILD SUCCEEDED **`, no `error:`.
2. Full test suite passes with the pre-existing `WindowFilterResolver` tests **unmodified** — if any needed editing, the default is wrong; stop and raise it. New `ProjectMembershipResolverTests` pass.
3. `.claude/skills/audit-specs-tests`: no orphan tests or scenarios.
4. The debug log shows one stable uuid per Desktop across a relaunch.
5. `git diff --stat upstream/master -- . ':!src/spaces' ':!src/projects' ':!plan'` lists only the files in the upstream touch budget.
6. Alt-Tab and the Spaces switcher behave identically to before — this milestone is invisible.

### Milestone 2 — Persist Projects; name Desktops and Projects from the menu bar

**Objective:** Projects and their names survive a relaunch. A user can always name the current Desktop; when Projects are enabled they can also create a custom Project from the focused window, add the focused window to one, rename and delete — all from the menu bar. Desktops pick up a sticky name from the first app opened on them.
**Commit:** per task
**Status:** not started

- [ ] 2.1 — Generalise the JSON branch in `Preferences.set()` so it is not hardcoded to `key == "exceptions"`. Files: `src/preferences/Preferences.swift`
- [ ] 2.2 — Define `ProjectEntry: Codable` (id, kind, space uuid, home Space uuid, name, auto name, icon file name) with a permissive `init(from:)` in the style of `ExceptionEntry`, a `projects` preference read through `CachedUserDefaults.json`, and its empty-array default, *depends on 2.1*. Member patterns come in Milestone 8. Files: `src/projects/ProjectsPreferences.swift`
- [ ] 2.3 — Load the registry from the preference at launch and save on every name, icon or lifecycle change, *depends on 2.2*. Desktop entries whose uuid no longer exists are kept (the Desktop may come back) but not shown. Files: `src/projects/Projects.swift`
- [ ] 2.4 — Add `ProjectNameResolver` as a pure kernel with its triad: precedence user-set → sticky auto → "Desktop N" for a Desktop Project → "Project N". `claim` sets the auto name only when both are empty and **never re-derives while a name stands**; `forget` drops an auto name, never a user name, when the Project has no live windows; whitespace-only input clears to automatic. Files: `src/projects/ProjectNameResolver.swift`, `src/projects/ProjectNameResolverSpecs.md`, `src/projects/ProjectNameResolverTests.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`
- [ ] 2.5 — Claim on discovery, *depends on 2.4*: one `Projects.windowAdded(_:)` call in `Windows.appendWindow()`; inside it, offer the app's `localizedName` to the Desktop Project of the window's Space and, if enabled and a custom Project is active, to that Project. `addDiscoveredWindow` runs on `BackgroundWork.axSemanticsQueue`; follow the main-thread hand-off the surrounding code already uses. Files: `src/switcher/state/Windows.swift`, `src/projects/Projects.swift`
- [ ] 2.6 — Build the name prompt as an `NSAlert` with an `NSTextField` accessory view modelled on `UpgradeTab.presentActivationSheet`, prefilled with the current resolved name. Files: `src/projects/ProjectNamePrompt.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`
- [ ] 2.7 — Menu bar, *depends on 2.6*: one block in `Menubar.initialize()` adding "Name this Desktop…" (always) and, **only when enabled**, a "Projects" submenu with "New Project from this Window…", "Add this Window to Project ▸", "Rename Project ▸", "Delete Project ▸". One call in `menuWillOpen` delegates to `ProjectsMenu.refresh(_:)`, which lives in the projects folder and owns the dynamic submenus and hidden state. Files: `src/Menubar.swift`, `src/projects/ProjectsMenu.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`
- [ ] 2.8 — Regenerate the source strings. Files: `resources/l10n/Localizable.strings`

**Verification:**
1. Build and tests pass; `audit-specs-tests` clean for `ProjectNameResolver`; `ensure_generated_files_are_up_to_date.sh` exits 0.
2. Disabled: the menu bar shows "Name this Desktop…" and nothing else new. On an empty Desktop open iTerm2 — the prompt prefills "iTerm2"; open Safari too — still "iTerm2"; rename to "Work", relaunch — still "Work".
3. Enabled (`defaults write com.lwouis.alt-tab-macos.debug projectsEnabled -bool true`, relaunch): focus Safari, "New Project from this Window…", name "Research"; from another Desktop, "Add this Window to Project ▸ Research". Relaunch: Research is still listed (its members are not — Milestone 8).
4. Alt-Tab and the Spaces switcher are unchanged in both states; nothing can activate a Project yet.
5. Upstream touch-budget diff check as in Milestone 1.

### Milestone 3 — The Project switcher

**Objective:** With Projects enabled, a dedicated shortcut opens a panel listing the custom Projects plus the current Desktop; releasing on one makes it active and Alt-Tab then lists only its members. Disabled, no shortcut is registered. The Spaces switcher is visually and behaviourally unchanged but now draws through a panel it shares with the Project switcher.
**Commit:** per task
**Status:** not started

- [ ] 3.1 — Extract the grid rendering from `SpacesPanel` into a reusable `GridPanel` + `GridTileView` driven by a small `GridTileItem` protocol (label, icon, isCurrent); make `SpacesPanel` a thin user. No visual change — screenshot before and after. Files: `src/spaces/SpacesPanel.swift`, `src/grid-panel/GridPanel.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`
- [ ] 3.2 — Generalise the auxiliary-switcher seams: an `AuxiliarySwitcher` protocol (`owns`, `shouldTrigger`, `holdShortcutId`, `isActive`) and a static list of switchers; replace each `SpacesSwitcher.owns(...)` special case at the seams named in Context with a lookup over that list, **editing only those lines**. `SpacesSwitcher` conforms; behaviour unchanged. Update the `Mocks.swift` stub. Files: `src/switcher/ATShortcut.swift`, `src/switcher/ShortcutAction.swift`, `src/preferences/settings-window/tabs/controls/ControlsTab.swift`, `src/preferences/Preferences.swift`, `src/events/KeyboardEventsTestable.swift`, `src/spaces/SpacesSwitcher.swift`, `src/_test-support/Mocks.swift`
- [ ] 3.3 — Add `ProjectsOrderResolver` as a pure kernel with its triad: the current Desktop first, then custom Projects most-recently-activated first, never-activated by creation order. Reuse `SpacesOrderResolver.cycle`, `initialSelection` and `gridColumns`. Files: `src/projects/ProjectsOrderResolver.swift`, `src/projects/ProjectsOrderResolverSpecs.md`, `src/projects/ProjectsOrderResolverTests.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`
- [ ] 3.4 — Add `ProjectSwitcher` (ids `holdProjectsShortcut`, `nextProjectShortcut`, `previousProjectShortcut`; `showOrCycle`, `cycle`, `focusSelected`, `hide`) conforming to `AuxiliarySwitcher`, and `ProjectsPanel` on `GridPanel`, *depends on 3.1–3.3*. `shouldTrigger` returns false when disabled. Selecting sets `Projects.active`; a custom Project with members also focuses its most-recently-focused member. Files: `src/projects/ProjectSwitcher.swift`, `src/projects/ProjectsPanel.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`
- [ ] 3.5 — Preferences and registration, *depends on 3.4*: defaults in `ProjectsPreferences` per the Key layout table (hold **unbound**; next ⇥; previous ⇧ bound bare with `.local` scope exactly as Spaces does), `projectsShortcutStyle`; registration in `ControlsTab` **guarded by `Projects.isEnabled`**, placed beside the Spaces block; a `ProjectsSheet` with an "Enable Projects" switch on top, then hold / next / previous / on-release rows and `searchableStrings`; a `showProjectsSettings` selector indexed in `SettingsSearchIndex` beside the Spaces one. Toggling the switch registers or unregisters the shortcuts immediately. Files: `src/projects/ProjectsPreferences.swift`, `src/preferences/settings-window/tabs/controls/ControlsTab.swift`, `src/projects/ProjectsSheet.swift`, `src/preferences/settings-window/SettingsSearchIndex.swift`, `src/preferences/Preferences.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`
- [ ] 3.6 — Layout preset and conflict warning in `ProjectsSheet`, *depends on 3.5*: a "Use ⌘ / ⌥ / ⌃ layout" button that, after an `NSAlert` confirmation naming the four keys it will change, writes via `Preferences.setShortcut`: `holdShortcut0` = ⌘, `holdShortcut1` = ⌘, `holdProjectsShortcut` = ⌥, `holdSpacesShortcut` = ⌃ (shortcut 3 and every next/previous key untouched). Below the hold recorder, a red note appears whenever the Project hold equals any window-switcher or Spaces hold, naming the clash, because that registration fails silently with -9878. Files: `src/projects/ProjectsSheet.swift`
- [ ] 3.7 — Regenerate the source strings. Files: `resources/l10n/Localizable.strings`

**Verification:**
1. Build and tests pass (existing `SpacesOrderResolverTests` untouched); `audit-specs-tests` clean for `ProjectsOrderResolver`; `ensure_generated_files_are_up_to_date.sh` exits 0.
2. The Spaces switcher: same tiles, size and behaviour as before 3.1 — compare screenshots.
3. Disabled: the debug log's shortcut registration lists no `*Project*` ids; the Projects sheet shows only the switch.
4. Enabled: bind the hold key; the panel lists "Desktop N" (current) and "Research"; release on Research — Alt-Tab lists only its members across Spaces; release on the Desktop entry — Alt-Tab is back to normal.
5. Preset: click "Use ⌘ / ⌥ / ⌃ layout", confirm — ⌘⇥ now opens the window switcher (the macOS app switcher no longer appears), ⌥⇥ the Project switcher, ⌃⇥ the Spaces switcher; the debug log shows no -9878. Set the Project hold back to ⌥ while windows are still on ⌥ — the red clash note appears.
6. Upstream touch-budget diff check.

### Milestone 4 — Active-Project lifecycle: pinning and auto-capture

**Objective:** The active custom Project survives a Space change AltTab itself caused by focusing a member, but resets when the user changes Space by any other means, including the Spaces switcher. Windows opened while a custom Project is active join it.
**Commit:** per task
**Status:** not started

- [ ] 4.1 — Add an "activation in flight" timestamp to `Projects`, set immediately before `ProjectSwitcher.focusSelected()` or an Alt-Tab focus of a member changes focus. A timestamp with a short expiry, **not a boolean**: focusing a window does not always change Space, so a bool would never clear and would pin the Project forever. Files: `src/projects/Projects.swift`, `src/projects/ProjectSwitcher.swift`
- [ ] 4.2 — Make the decision a pure function with its triad: given whether a self-activation is in flight, the previously active Project and the new current Space, return the Project that should be active. Scenarios: self-caused keeps the custom Project; user-caused resets to the Desktop; a Space change while a Desktop Project was active always follows the Space; an expired timestamp counts as user-caused; disabled always follows the Space. Files: `src/projects/ProjectActivationResolver.swift`, `src/projects/ProjectActivationResolverSpecs.md`, `src/projects/ProjectActivationResolverTests.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`
- [ ] 4.3 — Apply it in the `Projects` Space-change observer from 1.6, clearing the timestamp either way, *depends on 4.1 and 4.2*. `SpaceItem.activate()` does **not** set the timestamp — moving Desktops with the Spaces switcher is a user action. Files: `src/projects/Projects.swift`
- [ ] 4.4 — Auto-capture inside `Projects.windowAdded(_:)` (already called from `appendWindow()`, no new upstream edit): when enabled and a custom Project is active, add the new window's id to it. The window is **not** moved. Files: `src/projects/Projects.swift`
- [ ] 4.5 — Escape in the Project panel dismisses without changing the active Project. Files: `src/projects/ProjectsPanel.swift`

**Verification:**
1. Build and tests pass; `audit-specs-tests` clean for `ProjectActivationResolver`.
2. Enabled, Research active and spanning Spaces: Alt-Tab to a member on another Space — macOS switches Space, the Project switcher still shows Research active, Alt-Tab still lists only its windows.
3. Change Desktop with Ctrl+→, then with the Spaces switcher — each time the active Project becomes that Desktop and Alt-Tab lists that Desktop's windows.
4. Open a new TextEdit window with Research active — it appears in Alt-Tab inside Research immediately.
5. `MainThreadStall.step()` never names the summon path; upstream touch-budget diff check.

### Milestone 5 — Rich tiles in both panels

**Objective:** Every Spaces-switcher tile shows the thumbnail of the last window focused on that Desktop and "Desktop N" — plus, when Projects are enabled, the names of the Projects homed there. Every Project-switcher tile shows the thumbnail of its most-recently-focused member, its name, a subtitle, and that member's title.
**Commit:** per task
**Status:** not started

- [ ] 5.1 — Add `ProjectIconResolver` as a pure kernel with its triad: given a Project's icon source and the live windows, return which window's thumbnail to show, or none. Only the most-recent source exists yet: Desktop Project → lowest-`lastFocusOrder` window whose `spaceIds` contains the Space; custom → lowest-`lastFocusOrder` member; no candidates → none. Files: `src/projects/ProjectIconResolver.swift`, `src/projects/ProjectIconResolverSpecs.md`, `src/projects/ProjectIconResolverTests.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`
- [ ] 5.2 — Grow `GridTileItem` to thumbnail (`CALayerContents?`), title, subtitle, detail; render the thumbnail in `GridTileView` with a `LightImageLayer` above the text, falling back to the icon when nil. **No new capture.** Files: `src/grid-panel/GridPanel.swift`
- [ ] 5.3 — Space tile content, *depends on 5.1 and 5.2*: thumbnail from `ProjectIconResolver` for the Desktop Project; title "Desktop N"; subtitle = the Desktop's own name (if any) followed, when enabled, by the custom Projects homed there, comma-separated. Accessibility label equals the full text. Files: `src/spaces/SpacesList.swift`, `src/spaces/SpacesPanel.swift`
- [ ] 5.4 — Project tile content, *depends on 5.1 and 5.2*: thumbnail; title = resolved name; subtitle = "Desktop N · k windows" using the home Space; detail = the resolved window's title. An empty custom Project still gets a tile, drawn greyed. Files: `src/projects/ProjectsPanel.swift`
- [ ] 5.5 — Rework `GridTileView.tileSize(for:)`, *depends on 5.3 and 5.4*: measure several lines **and clamp to a maximum width**, truncating with an ellipsis and a tooltip rather than widening the panel. A tile sized to the exactly measured width still truncates — a real past bug; do not reintroduce it. Files: `src/grid-panel/GridPanel.swift`
- [ ] 5.6 — Revisit `SpacesOrderResolver.gridColumns()` and `GridPanel.maxColumns()` against the wider tile, *depends on 5.5*, extending `SpacesOrderResolverTests` if the balancing rule changes. Files: `src/spaces/SpacesOrderResolver.swift`, `src/spaces/SpacesOrderResolverSpecs.md`, `src/spaces/SpacesOrderResolverTests.swift`, `src/grid-panel/GridPanel.swift`

**Verification:**
1. Build and tests pass; `audit-specs-tests` clean for `ProjectIconResolver`.
2. Disabled, 13 Desktops: the Spaces switcher fits on screen, balanced grid, each tile shows thumbnail or fallback icon, "Desktop N", and the Desktop's name if set — no Project names.
3. Enabled: Desktop tiles also list custom Projects homed there; the Project switcher shows Research with its member's thumbnail, name, "Desktop N · 2 windows" and the member's title; an emptied Project is greyed but selectable.
4. Summoning either panel stays visually instant — no capture is triggered by opening it.

### Milestone 6 — Choose a window as the icon, and pin it permanently

**Objective:** From the menu bar a user can make the focused window the icon of the current Desktop (always) or of any Project (when enabled). By default the tile tracks that window's live thumbnail and falls back when it closes; "Pin permanently" saves the picture to disk so it survives the window closing, an app relaunch and a reboot. "Reset icon" returns to the most-recent default.
**Commit:** per task
**Status:** not started

- [ ] 6.1 — Extend `iconSource` to three cases — most-recent, chosen window (tracked id), pinned picture (file name) — and extend `ProjectIconResolver` + triad: chosen alive → that window; chosen gone → most-recent; pinned file present → the file; pinned file missing → most-recent. Files: `src/projects/Projects.swift`, `src/projects/ProjectIconResolver.swift`, `src/projects/ProjectIconResolverSpecs.md`, `src/projects/ProjectIconResolverTests.swift`
- [ ] 6.2 — Add `ProjectIconStore`: write a downscaled PNG per Project id under Application Support (see Context), load lazily into a `CGImage` cache, delete on reset and on Project deletion. All I/O off-main. Files: `src/projects/ProjectIconStore.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`
- [ ] 6.3 — Pin flow, *depends on 6.2*: take the window's current `Window.thumbnail`; if nil, request one through the existing per-window throttled refresh and pin when delivered. Never call a capture API directly. Files: `src/projects/Projects.swift`, `src/projects/ProjectIconStore.swift`
- [ ] 6.4 — Persist the pinned file name; a chosen-window source is in-session only and degrades to most-recent on load. Files: `src/projects/ProjectsPreferences.swift`, `src/projects/Projects.swift`
- [ ] 6.5 — Menu bar, *depends on 6.1–6.3*, inside `ProjectsMenu` (no new `Menubar.swift` lines beyond the block from 2.7): "Use this Window as Icon for ▸", "Pin this Window as Icon for ▸", "Reset Icon for ▸", each listing "This Desktop" then, when enabled, the custom Projects. Files: `src/projects/ProjectsMenu.swift`
- [ ] 6.6 — Feed the resolved icon into both panels' tiles and regenerate strings, *depends on 6.5*. Files: `src/spaces/SpacesPanel.swift`, `src/projects/ProjectsPanel.swift`, `resources/l10n/Localizable.strings`

**Verification:**
1. Build and tests pass; `audit-specs-tests` clean; `ensure_generated_files_are_up_to_date.sh` exits 0.
2. Disabled: "Use this Window as Icon for ▸ This Desktop" on Safari — the Desktop tile keeps showing Safari as you focus other windows; close Safari — it falls back.
3. Enabled: "Pin this Window as Icon for ▸ Research" — a PNG appears under Application Support; close the window, relaunch, reboot — the Research tile still shows it. "Reset Icon" removes the file.
4. Pinning one window produces at most one capture request in the debug log; upstream touch-budget diff check.

### Milestone 7 — Add or remove the highlighted window from the switcher

**Objective:** With Projects enabled, one key pressed while the window switcher is open adds the highlighted window to the active custom Project, or removes it if already a member. With a Desktop active or Projects disabled, the key does nothing.
**Commit:** per task
**Status:** not started

- [ ] 7.1 — Add `toggleProjectMembershipShortcut`, default **P** (free among the window switcher's W / M / F / Q / H letter keys); it is only ever registered inside the enabled guard, so with Projects off it steals nothing. Files: `src/projects/ProjectsPreferences.swift`
- [ ] 7.2 — Register it beside the other Project shortcuts (same guarded block from 3.5) and handle it during an open switcher session via the existing `ShortcutAction` list, toggling membership for the highlighted window and refreshing the open UI, *depends on 7.1*. Files: `src/switcher/ShortcutAction.swift`, `src/preferences/settings-window/tabs/controls/ControlsTab.swift`, `src/projects/Projects.swift`
- [ ] 7.3 — Recorder row in `ProjectsSheet` plus searchable string; regenerate strings, *depends on 7.1*. Files: `src/projects/ProjectsSheet.swift`, `resources/l10n/Localizable.strings`

**Verification:**
1. Build, tests and `ensure_generated_files_are_up_to_date.sh` pass.
2. Enabled: press P on a highlighted non-member with Research active — it joins and stays listed; press again — it leaves and disappears.
3. Disabled: the key is not registered; pressing P in the window switcher does nothing new.

### Milestone 8 — Durable membership across relaunches

**Objective:** A custom Project's members survive quitting AltTab, the member apps quitting, and a reboot.
**Commit:** per task
**Status:** not started

- [ ] 8.1 — Add member patterns (bundle identifier plus window title) to `ProjectEntry`, keeping the permissive decoder so stored Projects without patterns still load. Files: `src/projects/ProjectsPreferences.swift`
- [ ] 8.2 — Save patterns on every membership change, *depends on 8.1*. Files: `src/projects/Projects.swift`
- [ ] 8.3 — Re-attach inside `Projects.windowAdded(_:)` (no new upstream edit), *depends on 8.1*: match the window against stored patterns with bundle-id prefix and literal title substring exactly as `ExceptionMatcher` does, and add it to each matching Project. Pure kernel with triad: exact re-attach; same app, different title, no match; a title that changed after saving; two Projects claiming one window; a pattern whose app is not running. Files: `src/projects/ProjectReattachResolver.swift`, `src/projects/ProjectReattachResolverSpecs.md`, `src/projects/ProjectReattachResolverTests.swift`, `src/projects/Projects.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`

**Verification:**
1. Build and tests pass; `audit-specs-tests` clean for `ProjectReattachResolver`.
2. Build Research from a Safari and a Terminal window; quit and relaunch AltTab — both still listed.
3. Quit Safari, relaunch it, reopen the same page — the window rejoins Research.
4. Reboot; Research survives with whatever members reopened.

### Milestone 9 — Drag a window onto a Project (stretch)

**Objective:** Dragging a window tile in the open switcher reveals a strip of Projects beneath the grid and drops the window into the one you release over.
**Commit:** per milestone
**Status:** not started

> Note: highest-risk milestone and the only one that must touch `TileView.swift` / `TilesView.swift`, which are upstream. The switcher panel is non-activating and its tiles already consume mouse tracking for hover selection, so a drag session may conflict. Prove that a drag can even start before building the strip; if it cannot, stop and raise it rather than reworking the switcher's mouse handling. Confirm with the dispatcher before starting that widening the upstream diff here is acceptable.

- [ ] 9.1 — Spike only: make `TileView` an `NSDraggingSource` and confirm a drag session starts from an open switcher without breaking hover selection or dismissal. Files: `src/switcher/main-window/TileView.swift`
- [ ] 9.2 — Add a Project strip below the grid, shown only during a drag, acting as `NSDraggingDestination`, *depends on 9.1*. Files: `src/projects/ProjectDropStripView.swift`, `src/switcher/main-window/TilesView.swift`, `alt-tab-macos.xcodeproj/project.pbxproj`
- [ ] 9.3 — On drop, add the window to that Project with visual confirmation, *depends on 9.2*. Files: `src/projects/Projects.swift`, `src/projects/ProjectDropStripView.swift`

**Verification:**
1. Build and tests pass.
2. Drag a tile downward — the strip appears; drop on Research — the window joins, confirmed via the Project switcher.
3. A plain click still focuses a window and a plain hover still highlights one.

## Out of scope

- **Renaming or changing the Spaces switcher.** It keeps its name, shortcuts, preference keys and behaviour; it gains only the shared panel and richer tile content.
- **Any new screen-capture API.** Tiles and pinned pictures reuse `Window.thumbnail`. A display-capture path for Desktops was rejected: the WindowServer does not render off-screen Spaces, and capture bursts wedged `replayd` in #5861.
- **Moving windows between macOS Spaces.** A Project is a view over windows, not a mover of them. `SLSMoveWindowsToManagedSpace` stays unused.
- **Changing any existing default or behaviour with Projects disabled.** A user who never flips the switch must not be able to tell this feature shipped, beyond the optional "Name this Desktop…" item and Desktop tile thumbnails.
- **Nested Projects, per-display Projects, and rules-based auto-membership** ("all Slack windows are always in Work"). Milestone 8's patterns make this easy later; do not add it now.
- **Editing any upstream file not in the touch budget.**

## Decisions

- **2026-09-07: approve only the two task 1.6 integration exceptions** recorded above; keep the remaining touch budget unchanged.

- **2026-09-07: defer task 1.1’s logout/login UUID check and continue Milestones 1–3 after relaunch stability is verified**, approved by the dispatcher.

- **Projects are opt-in behind one `projectsEnabled` switch, off by default.** With it off, the only user-visible additions are "Name this Desktop…", Desktop icon choice/pinning, and thumbnails on Space tiles — all Spaces-switcher features that ride on the Desktop record.
- **The Desktop Project is the per-Desktop record and exists regardless of the switch.** A Desktop's sticky name and chosen icon live on it, keyed by Space uuid so they survive reboots. The user never sees the word "Project" for it.
- **The Spaces switcher stays; Projects are a second auxiliary switcher.** Shared code (grid panel, shortcut seams) is extracted, never copied and never renamed.
- **Upstream touches are enumerated and budgeted.** Hooks into upstream are single calls into `Projects` (`windowAdded`, `windowsRemoved`, `ProjectsMenu.refresh`) so later milestones add behaviour without new upstream lines.
- **A custom Project's home Space is the Space current at creation.** Space tiles list Projects by home Space.
- **Only custom Projects filter the switcher.** A Desktop Project returns no member filter, so Alt-Tab keeps obeying `spacesToShow`. One defaulted parameter; no behaviour change for existing users or tests.
- **Membership is a filter clause, not a new list.** Ordering, search, tab grouping and rendering are untouched.
- **An active custom Project is pinned across a Space change AltTab caused**, and reset by one the user caused — including via the Spaces switcher. Timestamp, not flag, because focusing a window does not always change Space.
- **Auto-derived names are sticky, claimed once.** User-set always wins and is never auto-overwritten.
- **Session membership keys on `TrackedWindow.id`; durable membership keys on bundle id plus title.** Nothing else survives a process boundary — the wid is reused by unrelated windows.
- **Three icon sources, resolved by a pure kernel**: most-recent (default), chosen window (live, in-session), pinned picture (PNG on disk, permanent). Pictures are files under Application Support, not `UserDefaults` values.
- **Pinning reuses the existing thumbnail**, requesting one through the throttled per-window path only if none exists.
- **The Project hold shortcut ships unbound; the ⌘ / ⌥ / ⌃ layout is a one-click preset.** Shipping ⌥ would collide with the window switcher's upstream default and fail with -9878; changing the window switcher's default is an upstream behaviour change and out of scope. The preset rewrites the user's own preference values, which is what the Settings UI does anyway.
- **The membership toggle defaults to P** because it is only registered when Projects are enabled, so the default costs nothing for everyone else.
- **An empty custom Project still gets a tile**, greyed, so it stays reachable.
- **Joining a Project never moves a window between Spaces.**
- **Drag-and-drop stays last, behind a spike gate and an explicit go-ahead**, because it is the one milestone that must edit upstream switcher views.
- **Every milestone commits per task except the drag-and-drop stretch.**

## Open questions

None outstanding. Raise new ones with the dispatcher rather than deciding them here.
