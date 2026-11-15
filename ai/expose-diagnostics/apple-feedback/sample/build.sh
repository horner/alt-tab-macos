#!/bin/bash
set -euo pipefail
sample_source="$(cd "$(dirname "$0")" && pwd)"
sample_output="${EXPOSE_SAMPLE_OUT:-/tmp/AccessoryExposeSample-build}"
sample_compiler="${EXPOSE_SAMPLE_SWIFTC:-$(xcrun --find swiftc)}"
sample_sdk="${EXPOSE_SAMPLE_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
sample_target="$(uname -m)-apple-macosx13.0"
sample_bundle="$sample_output/AccessoryExposeSample.app"
mkdir -p "$sample_bundle/Contents/MacOS"
"$sample_compiler" -swift-version 5 -sdk "$sample_sdk" -target "$sample_target" "$sample_source/AccessoryExposeSample.swift" -o "$sample_bundle/Contents/MacOS/AccessoryExposeSample"
cp "$sample_source/Info.plist" "$sample_bundle/Contents/Info.plist"
printf 'Built %s\n' "$sample_bundle"
