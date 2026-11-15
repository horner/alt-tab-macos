# App Exposé swipe targets the previous regular app when an accessory app is active; Control–Down targets the active app

## Summary

On macOS 27.0 (26A428), App Exposé selects different applications depending on whether it is invoked by the downward trackpad gesture or Control–Down. When an AppKit accessory application is active, the gesture exposes the previously active regular application's windows. Control–Down exposes the active accessory application's windows correctly.

This affects ordinary titled windows, including settings windows. It is reproducible independently of AltTabProjects in a small AppKit application with two standard NSWindows and a main menu. Switching the same test application from `.accessory` to `.regular` makes the gesture select the correct application; switching back restores the failure.

## Environment

- macOS 27.0, build 26A428, Apple silicon.
- App Exposé downward trackpad gesture enabled in System Settings.
- An AppKit app with `LSUIElement = true` / `NSApplication.ActivationPolicy.accessory`.
- First noticed after upgrading to macOS 27. The same test has not yet been run on an older macOS version, so the version of introduction is unconfirmed.

## Steps to reproduce

1. Launch the attached AppKit sample in accessory mode. Leave both ordinary titled windows open.
2. Activate another regular application with an open window (Google Chrome was used in the recorded test).
3. Click the sample's first window so the accessory application is active.
4. Swipe down with the configured three- or four-finger App Exposé gesture.
5. Observe that the regular application's windows appear, rather than the sample's two windows. Exit Exposé with Escape.
6. Activate the sample again and press Control–Down. Observe that its two windows appear correctly. Exit with Escape.
7. Click “Use regular mode” in the sample, activate the other regular app, then click the sample again. Repeat the downward gesture. The sample's windows now appear correctly.
8. Click “Use accessory mode,” activate the other regular app, then click the sample again. Repeat the gesture. The other application's windows appear again.

Reactivating the other app and then the sample after each policy change is part of the comparison. Begin each gesture or shortcut test with Exposé closed.

## Expected result

Both the trackpad gesture and Control–Down expose the active application's windows, including when it uses accessory activation policy. Apple's macOS 27 user guide presents these as equivalent ways to show all open windows for the current app:

https://support.apple.com/en-ge/guide/mac-help/mh35798/mac

If accessory applications are intentionally excluded from the gesture path, please clarify that contract and provide a supported way for an accessory app's active windows to participate.

## Actual result and controls

| Active app | Activation policy | Input | Exposed windows |
| --- | --- | --- | --- |
| Chrome | regular | Downward gesture | Chrome |
| AltTabProjects | accessory | Downward gesture | Chrome |
| AltTabProjects | accessory | Control–Down | AltTabProjects |
| Minimal AppKit probe, A | accessory | Downward gesture | Chrome |
| Same probe, A | accessory | Control–Down | Probe |
| Same probe, B | regular | Downward gesture | Probe |
| Same probe, A again | accessory | Downward gesture | Chrome |

The probe has no gesture recognizers, event taps, global shortcuts, custom window subclasses, or AltTab code. The two probe windows and its main menu remained the same during the recorded activation-policy comparison.

## Investigation evidence and limits

The original symptom was observed with a physical four-finger swipe in AltTabProjects. The recorded automated comparison used the same synthetic system Dock-swipe sequence for all gesture rows, and separately generated Control–Down. WindowManager's accessibility tree confirmed which windows were exposed, and its unified log independently recorded the target process and whether the trigger was a gesture or hotkey. Physical finger recognition was not part of the automated comparison.

During the minimal probe comparison on September 24, 2026 (America/Indiana/Indianapolis, UTC−04:00), the gesture selected Chrome at 05:21:49 while the probe was active in accessory mode. Control–Down selected the probe at 05:21:58. After changing to regular mode and reactivating, the gesture selected the probe at 05:22:16. After changing back to accessory and reactivating, it selected Chrome at 05:22:39.

Activation records show the accessory application becoming frontmost while the previous regular application remains the menu-bar owner. The gesture target matches that regular application. This is a correlation useful for triage, not a claim about an inspected internal implementation.

The attached simplified sample uses only public AppKit APIs and is derived from the tested probe. It has been compiled successfully; the simplified variant has not yet been separately tested interactively. Source for the exact recorded probe is also included. No private synthetic-input implementation is required to build or run either sample; an engineer can use the physical trackpad and keyboard steps above.

## Impact and workaround

Users of the affected accessory app cannot use their configured App Exposé gesture to discover its open windows, including windows across desktops, even though the keyboard shortcut works. Control–Down is a user workaround. Permanently changing to regular activation policy changes the app's Dock/menu behavior, so it is not an equivalent application workaround.

Please investigate the mismatch in App Exposé's application targeting and advise whether there is a supported workaround that preserves accessory activation policy.
