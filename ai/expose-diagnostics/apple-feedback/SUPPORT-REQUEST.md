# App Exposé targeting for NSApplication.ActivationPolicy.accessory on macOS 27

Feedback ID: FB24919003

I am developing an AppKit accessory application, AltTabProjects, and need guidance on its supported activation/window configuration for App Exposé on macOS 27.0 (26A428), Apple silicon.

With the accessory app active, a physical four-finger downward App Exposé swipe does not expose its windows, including its Settings window. Control–Down does. Apple documents the swipe and Control–Down as ways to show the current app's windows: https://support.apple.com/en-ge/guide/mac-help/mh35798/mac

An automated comparison using the same synthetic system gesture sequence for every case showed the previously active regular application's windows when the accessory app was active. A small AppKit probe with two ordinary NSWindows and a main menu reproduced the activation-policy dependence: accessory selected Chrome, regular selected the probe, then accessory selected Chrome again. Before each comparison, I activated Chrome and then reactivated the probe. A separately generated Control–Down selected the accessory probe correctly. This isolates system gesture targeting, but it is not a physical-trackpad comparison in the probe.

The probe uses public AppKit APIs and has no gesture recognizers, event taps, global shortcuts, custom window subclasses, or AltTab implementation. The attached Feedback report contains the exact tested probe and a simplified public-API sample. Both compile; the simplified variant has not yet been separately live-tested. The samples require no synthetic input tooling to reproduce manually. The version of macOS that introduced the issue is unconfirmed because this comparison has not been run on an older release.

Physical reproduction steps for the simplified sample:

1. Enable the four-finger downward App Exposé gesture and Control–Down for Application windows in System Settings.
2. Launch the sample in accessory mode with its two ordinary windows open.
3. Click a regular application's window, then click the sample's first window.
4. Swipe down physically and record which application's windows appear. Press Escape.
5. Repeat the regular-app → sample activation sequence and press Control–Down. Record the result and press Escape.
6. Choose “Use regular mode,” repeat the activation sequence, and test again.
7. Choose “Use accessory mode,” repeat the activation sequence, and test again. Begin every test with App Exposé closed.

The exact original probe uses the label “Use normal mode” for regular mode. Leave its helper-window controls unused; those concern a separate experiment.

My questions are:

- Is App Exposé's gesture path intended to exclude an active accessory application's ordinary windows even though Control–Down includes them?
- If not, is there a supported activation or window configuration that lets those windows participate while preserving `.accessory` policy and avoiding a Dock icon?

Control–Down is a user workaround. Permanently changing to `.regular` changes the app's Dock/menu behavior. I am seeking clarification of the public API contract and a supported workaround, rather than a fix date or details of Apple's internal implementation.
