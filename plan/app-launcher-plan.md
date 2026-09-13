# Cmd+N app picker

Status: implemented; focus behavior confirmed by the user. Visual styling, app icons, and recent-use ordering added.

## Experience

While the switcher is open, **Cmd+N** replaces it with a small searchable picker. Type, select with Up/Down, and press Return. Releasing the shortcut modifiers leaves the picker open.

| Search | Action |
|---|---|
| `chrome` | Create a new Chrome window |
| `safari` | Create a new Safari window |
| `sms`, `text`, or `messages` | Open a new message composer in Messages |
| Another app's name | Open that app |

Each app has one result with its action clearly labeled. The picker closes after selection. **Escape closes the picker**; it does not reconstruct the previous switcher session. Message composition and sending happen in Messages.

## Build it in three steps

1. **Make the picker.** Add one local Cmd+N handler and a small programmatic AppKit panel containing an `NSSearchField` and an `NSTableView`. Dismiss the switcher through its existing lifecycle before presenting the picker on the next main-loop turn. The picker owns its keyboard input and cancellation. Reuse `SearchTestable` for filtering and the switcher's background material, theme, and selection styling. Rows show app logos, names, and actions in a fixed panel size.

2. **Supply the apps.** On picker opening, scan `/Applications`, `~/Applications`, `/System/Applications`, and `/System/Library/CoreServices/Applications` in the background. Walk ordinary subfolders, stop at app bundles, exclude embedded helpers, and deduplicate canonical paths. Show the previous in-memory list immediately while refreshing, or a loading label on first use. Keep the result list fixed during typing once that scan finishes. Show locations only to distinguish duplicate names. This covers standard installation folders; unusual custom folders and external drives are outside the first version.

3. **Perform the action.** Use `NSWorkspace` to open ordinary apps. Add three explicit functions for Chrome New Window, Safari New Window, and Messages New Message, invoking the target app's native menu command through existing Accessibility support. Start the app first when necessary, use existing readiness observers, and issue the creation command once. Select the actual New Window command rather than sending a global Cmd+N. Hide the picker before the action and show a simple error if it fails.

Keep the feature in `src/app-launcher/`. Small specs/tests cover pure matching, recent-use ordering, and action-selection logic. Integration consists of local key routing, the existing dismissal lifecycle, app-activation notifications, and source/test registration.

## Keep the first version small

- Fixed Cmd+N binding; if an existing user binding conflicts, preserve it and leave picker entry unavailable until that binding is changed.
- One result/action per app; Chrome and Safari create windows, Messages composes, and other apps open normally.
- Refresh on opening the picker. Persist only the most recent use of each app, and sort matching apps by that date. No Spotlight service, filesystem watchers, persistent app index, or custom-folder settings.
- No extra action menu, command parser, profile picker, shared switcher search mode, or window-selection restoration.

## Checks that matter

- Cmd+N works with the activation modifier held and from existing window search; releasing it does not dismiss or execute the picker. Repeated presses do not open extra pickers.
- Typing, arrows, Return, Escape, and input-method composition work. Late scan results cannot reopen or overwrite a closed/newer picker.
- Chrome and Safari create a separate window when already running and when stopped. Check Safari's tab/fullscreen preferences. Messages opens an unsent composer and leaves existing drafts intact.
- Never retry a creation command automatically after an ambiguous timeout; the app may already have performed it. Use the AX executor's non-retrying path.
- Disk scans and target-app Accessibility work stay off-main. AppKit view/window work stays on main with the existing deferral rules.
- Run focused keyboard/matching/action tests, manually exercise the four flows above, and compile using the command in `ai/build.sh`.

## Verification so far

- Debug build succeeds; 155 focused catalog, action-selection, keyboard, modifier, and search tests pass.
- Native creation produced one additional Chrome window and one additional Safari window. Test windows from these probes were closed.
- Picker filtering, repeated Cmd+N, and Safari launch worked in automated UI checks. Those checks activated AltTab and do not establish correct focus when invoked over another app.
- The user confirmed Cmd+S/Cmd+N work after stopping the temporary test app, restoring Focus-on-release, removing the test-only activation change, and restarting. Temporary focus logging has been removed.
- Messages' menu action returned success, but an unsent composer has not yet been visually verified. Cold launches, IME composition, and Safari fullscreen/tab preferences still need manual verification.
