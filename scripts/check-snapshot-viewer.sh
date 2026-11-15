#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
web=src/projects/snapshot-viewer/web
manifest="$web/dist/sources.sha256"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/alt-tab-viewer.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
{
    find "$web" -type f ! -path "$web/dist/*" ! -name .DS_Store
    printf '%s\n' scripts/build-snapshot-viewer.mjs scripts/check-snapshot-viewer.sh package.json package-lock.json "$web/dist/viewer.html" "$web/dist/THIRD-PARTY-NOTICES.txt"
} | LC_ALL=C sort > "$scratch/current"
sed 's/^[0-9a-f]*  //' "$manifest" > "$scratch/expected"
if ! cmp -s "$scratch/current" "$scratch/expected" || ! shasum -a 256 -c "$manifest" > "$scratch/check" 2>&1; then
    echo 'error: Snapshot viewer resources are stale. Run npm ci and npm run viewer:build, then include the generated resources.' >&2
    exit 1
fi
