#!/bin/bash
set -euo pipefail
probe_source="$(cd "$(dirname "$0")" && pwd)"
probe_output="${EXPOSE_DIAGNOSTICS_OUT:-/tmp/alttab-expose-diagnostics-build}"
probe_compiler="${EXPOSE_DIAGNOSTICS_SWIFTC:-/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc}"
probe_sdk="${EXPOSE_DIAGNOSTICS_SDK:-/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
probe_target="$(uname -m)-apple-macosx13.0"
mkdir -p "$probe_output/ExposeProbe.app/Contents/MacOS"
for probe_program in EventRecorder SyntheticInput Inspect; do
    "$probe_compiler" -swift-version 5 -sdk "$probe_sdk" -target "$probe_target" "$probe_source/$probe_program.swift" -o "$probe_output/$probe_program"
done
"$probe_compiler" -swift-version 5 -sdk "$probe_sdk" -target "$probe_target" "$probe_source/ModeProbe.swift" -o "$probe_output/ExposeProbe.app/Contents/MacOS/ExposeProbe"
cp "$probe_source/Info.plist" "$probe_output/ExposeProbe.app/Contents/Info.plist"
printf 'Diagnostics built in %s\n' "$probe_output"
