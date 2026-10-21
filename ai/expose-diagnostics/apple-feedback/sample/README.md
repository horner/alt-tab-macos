# Accessory App Exposé sample

This small AppKit application creates two ordinary titled windows and switches between `NSApplication.ActivationPolicy.accessory` and `.regular`. It installs a main menu with Quit. It uses public AppKit APIs only: no gesture handlers, event interception, synthetic input, private APIs, transparent helper windows, or AltTab code.

The sample is derived from a probe that was tested locally on macOS 27.0 (26A428), with an accessory → regular → accessory comparison. This simplified variant has been compile-verified but has not yet been launched or live-tested. The parent investigation includes automated native-input observations; the steps below ask reviewers to reproduce with a physical trackpad.

## Build

With a matching Swift compiler and macOS SDK installed:

```sh
bash build.sh
open /tmp/AccessoryExposeSample-build/AccessoryExposeSample.app
```

The script uses the selected developer toolchain through `xcrun`, then invokes `swiftc` directly in Swift 5 language mode. It does not require an Xcode project or the Xcode IDE. `EXPOSE_SAMPLE_SWIFTC` and `EXPOSE_SAMPLE_SDK` can select a matching compiler/SDK pair; `EXPOSE_SAMPLE_OUT` overrides the output directory. It builds for the Mac's native architecture with a macOS 13 minimum deployment target.

Local compilation was verified with:

```sh
EXPOSE_SAMPLE_SWIFTC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc \
EXPOSE_SAMPLE_SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
bash build.sh
```

## Physical-gesture reproduction

1. In System Settings → Trackpad → More Gestures, enable App Exposé with a downward four-finger swipe. Make sure Control–Down is assigned to Application windows in the Mission Control keyboard shortcuts.
2. Open a regular application with a visible window, such as Chrome, alongside this sample. Keep both sample windows open and visible. The sample initially uses accessory mode and has no Dock icon.
3. Click the regular application's window, then click the sample's first window to activate the sample.
4. Perform the configured downward App Exposé swipe on the physical trackpad. Record which application's windows appear, then press Escape to exit App Exposé.
5. Repeat the regular-app → sample activation sequence. Press Control–Down. Record which application's windows appear, then press Escape.
6. Click **Use regular mode**. Repeat steps 3–5, including activation of the other regular app and reactivation of the sample.
7. Click **Use accessory mode**. Repeat steps 3–5 again, including the activation sequence.

Always begin each invocation with App Exposé dismissed. After changing activation policy, activating another regular application and then clicking the sample again is important to make the comparison consistent.

## Expected and previously observed behavior

Expected: the swipe and Control–Down both show the two sample windows while the sample is active, in either activation mode.

Observed in the original probe on macOS 27.0 (26A428): accessory-mode swipes showed the previously active regular application's windows, whereas Control–Down showed the sample's windows. Regular-mode swipes showed the sample's windows. Switching back to accessory mode restored the mismatch.

The version in which this behavior began is unconfirmed; the original probe was not tested on an older macOS release. The blank helper-window issue from the broader AltTab investigation is separate and is not part of this sample.

If capturing diagnostics for Apple, note the reproduction time with seconds and timezone, capture a short recording that identifies the invocation method, and collect a sysdiagnose immediately afterward.
