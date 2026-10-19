# App Exposé gesture target investigation

On macOS 27.0 (26A428), App Exposé's trackpad path selects the previously active regular application when an accessory application is active. Control–Down selects the active accessory application correctly. This reproduces with a minimal AppKit application containing no AltTab code.

## Verified result

Each test began with Exposé closed. The same synthetic downward Dock-swipe sequence was used for every row. WindowManager's accessibility tree identifies the actual exposed windows; its unified log independently names the target process and input source.

| Active application | Mode | Trigger | Exposed application |
| --- | --- | --- | --- |
| Chrome | regular | Downward swipe | Chrome |
| AltTabProjects | accessory | Downward swipe | Chrome |
| AltTabProjects | accessory | Control–Down | AltTabProjects |
| Minimal probe, A | accessory | Downward swipe | Chrome |
| Minimal probe, A | accessory | Control–Down | Probe |
| Same probe, B | regular | Downward swipe | Probe |
| Same probe, A again | accessory | Downward swipe | Chrome |

Chrome was activated and then the probe was reactivated between each policy change. Both probe windows and its main menu remained the same. This A/B/A comparison isolates activation policy. AltTabProjects was unmodified throughout.

In the September 24, 2026 comparison, the recorder shows AltTabProjects as the front application when WindowManager opens Chrome's windows via a `gesture` trigger. Control–Down instead opens AltTabProjects via `hotKey`. The later minimal-probe A/B/A reproduces this selection difference independently.

Dock's activation notification names AltTabProjects as frontmost while retaining Chrome's `LSMenuBarOwnerASN`. The gesture target matches that menu-bar owner. Selecting stale regular/menu-bar-owner state rather than the active accessory process explains the observed behavior. The exact internal WindowManager function performing this selection was not inspected.

The minimal AppKit reproduction requires no AltTab code. No older macOS installation was available, so the release in which this behavior first appeared remains unverified.

## Blank entries are a separate defect

Adding three transparent 2×2 `.managed` windows to the probe yields five Exposé entries: two real windows and three blank entries. Changing only the helpers to `.stationary` yields two entries.

The earlier AltTab keyboard test exposed ten labels plus eleven blank entries (the supplied screenshot had ten blank entries). The three-window control proves that managed transparent helpers contribute blank entries; it does not assign every blank runtime entry to a particular window.

An October 19, 2026 navigation probe compared focusable anchors assigned to an empty Desktop. Stationary anchors did not switch Desktops; transient anchors moved back to the current Desktop. A managed anchor reached its destination, but ordering it out selected an older key window and returned to the origin. Promoting an ordered stationary anchor to managed before focus, then restoring stationary behavior after confirmed arrival, preserved the destination and key window on repeated trips. `src/spaces/DesktopWindows.swift` uses this last approach, with stale-request guards and bounded cleanup. Visible Project labels remain managed. Excluding the invisible anchors with `setAccessibilityElement(false)` also kept the visible probe controls accessible after navigation; the same repeated arrival checks still passed.

## Public reproduction and local evidence

`apple-feedback/REPORT.md` contains the reproduction report, and `apple-feedback/FORUM-POST.md` preserves the submitted public forum text. The `sample/` and `original-tested-probe/` directories contain standalone public-AppKit reproductions. `SUPPORT-REQUEST.md` contains the technical support question without account or correspondence details.

Raw evidence is retained locally under the ignored `evidence/` directory. It is not included in source distributions, because accessibility output, activation records and window metadata can contain user activity:

- `evidence/results.json`: window lists extracted from WindowManager AX snapshots.
- `evidence/*.txt`: WindowManager AX results, excluding unrelated Dock content.
- `evidence/window-manager.log`: selected native transitions and activation records.
- `evidence/events.jsonl`: gesture phases, key markers and front-application state; unrelated window metadata removed.

Personal Feedback history, account/submission records, escalation drafts and the generated report ZIP are also ignored. Do not include them when packaging the public sample. Review any newly collected logs before sharing them.

Synthetic input was explicitly authorized by the user. Physical finger detection was not simulated. The successful Chrome test validates the system Dock-swipe path; the same sequence reproduces the reported AltTab mismatch. The upward sequence also opened Mission Control.

## Reproduction tools

These are standalone diagnostic programs, not part of the shipping application. They compile in Swift 5 language mode and require a matching macOS SDK/toolchain. The input helper uses private macOS 27 HID/SkyLight APIs and refuses to send input while the screen is locked or Accessibility access is unavailable. It makes no permission changes.

Run `bash ai/expose-diagnostics/build.sh`. The script uses direct `swiftc`, creates `/tmp/alttab-expose-diagnostics-build`, and neither launches an app nor posts input. Override `EXPOSE_DIAGNOSTICS_SWIFTC`, `EXPOSE_DIAGNOSTICS_SDK`, or `EXPOSE_DIAGNOSTICS_OUT` when needed.

Tools in the output directory:

- `EventRecorder <target-pid>`: listen-only gesture/key markers, activation records and Dock notifications as JSON lines. On this macOS release, Dock notification subscriptions succeeded but did not report the tested Exposé transitions, so use `Inspect` and unified logs to verify results.
- `Inspect <WindowManager-pid> <Dock-pid>`: bounded-depth AX tree and onscreen window metadata.
- `SyntheticInput check`: verify unlocked session and Accessibility access without posting input.
- `SyntheticInput activate <pid>`: request activation of an already running application.
- `SyntheticInput key down`: Control–Down with arrow-key modifier flags. `key escape` exits Exposé.
- `SyntheticInput swipe -1.5 3`: App Exposé. `swipe 1.5 3`: Mission Control.
- `ExposeProbe.app`: two titled windows, a menu, activation-policy buttons, and transparent-helper controls. Per-process logs go into the temporary `alttab-expose-investigation` directory.

Launch the control app, activate Chrome, then reactivate the probe. Perform the swipe, inspect WindowManager, Escape, perform Control–Down, inspect, and Escape. Repeat with the normal-mode button, then accessory mode again. Reactivating after a policy change is essential; changing policy while already active did not provide a valid normal-mode control in the first attempt.

The probe implements the HID event schema described by [Mac Mouse Fix's reference implementation](https://github.com/oomol-lab/dockswipe/blob/main/TouchSimulator.reference.m) and the [macOS 27 compatibility implementation](https://github.com/timmyagentic/mac-mouse-fix-macos-27-fix/blob/main/src/main.m). The proof above comes from local live tests, not from those projects' claims.

## Validation and cleanup

All four diagnostic programs compiled successfully. The A/B/A and helper comparisons above ran on the user's machine. The diagnostic tools did not edit production source, app signatures, bundle identities, preferences or project files. The temporary probe app and recorders were stopped and focus returned to Codex.

These diagnostics validate the reproduction tools independently of the shipping application's build. The standalone programs remain diagnostic tools. The production anchor change addresses blank entries separately from the accessory-app gesture targeting issue above.
