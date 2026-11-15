#!/bin/bash
set -euo pipefail
probe_source="$(cd "$(dirname "$0")" && pwd)"
probe_output="${EXPOSE_SAMPLE_OUT:-/tmp/ExposeProbe-AppleFeedback-build}"
probe_compiler="${EXPOSE_SAMPLE_SWIFTC:-$(xcrun --find swiftc)}"
probe_sdk="${EXPOSE_SAMPLE_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
probe_target="$(uname -m)-apple-macosx13.0"
probe_bundle="$probe_output/ExposeProbe.app"
mkdir -p "$probe_bundle/Contents/MacOS"
"$probe_compiler" -swift-version 5 -sdk "$probe_sdk" -target "$probe_target" "$probe_source/ModeProbe.swift" -o "$probe_bundle/Contents/MacOS/ExposeProbe"
cp "$probe_source/Info.plist" "$probe_bundle/Contents/Info.plist"
printf 'Built %s\n' "$probe_bundle"
