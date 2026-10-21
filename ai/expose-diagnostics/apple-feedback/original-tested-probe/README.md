# Exact probe from the recorded comparison

These are the unmodified public-AppKit-only source and bundle metadata used in the original accessory → regular → accessory test. The helper-window buttons address a separate experiment; leave them unused for this gesture report. The synthetic input driver and system-inspection tools are not included. Use a physical trackpad and keyboard for reproduction.

## Build

With a matching Swift compiler and macOS SDK installed, run these commands from this directory:

```sh
bash build.sh
open /tmp/ExposeProbe-AppleFeedback-build/ExposeProbe.app
```

The script finds the selected toolchain with `xcrun`, then invokes `swiftc` directly in Swift 5 language mode. It does not use an Xcode project or the Xcode IDE. Override `EXPOSE_SAMPLE_SWIFTC` and `EXPOSE_SAMPLE_SDK` together to choose a matching compiler/SDK pair, or `EXPOSE_SAMPLE_OUT` to change the output directory.

This exact copied source was compile-verified with:

```sh
EXPOSE_SAMPLE_SWIFTC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc \
EXPOSE_SAMPLE_SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
bash build.sh
```

Use the physical-gesture steps in the sibling `sample/README.md`. The regular-mode button in this original probe is labeled **Use normal mode**. Do not click either helper-window button during the gesture comparison. After changing modes, activate another regular app and then click the probe again before testing.

The original probe records its own activation and window state to the temporary alttab-expose-investigation directory. It does not record typed text.
