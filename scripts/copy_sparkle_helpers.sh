#!/usr/bin/env bash
set -euo pipefail

SPARKLE_FW="$BUILT_PRODUCTS_DIR/$FRAMEWORKS_FOLDER_PATH/Sparkle.framework"
SPARKLE_VERSIONED="$SPARKLE_FW/Versions/A"
SPM_RESOURCES="$BUILT_PRODUCTS_DIR/Sparkle_Sparkle.bundle/Contents/Resources"
SPARKLE_PKG="$BUILT_PRODUCTS_DIR/PackageFrameworks/Sparkle.framework/Versions/A"

if [ ! -d "$SPARKLE_VERSIONED" ] || [ ! -d "$SPM_RESOURCES" ]; then
    echo "error: Sparkle framework and resources must be embedded before Copy Sparkle Helpers" >&2
    exit 1
fi
for resource in SUStatus.nib SUUpdateAlert.nib SUUpdatePermissionPrompt.nib ReleaseNotesColorStyle.css Base.lproj/Sparkle.strings; do
    if [ ! -e "$SPM_RESOURCES/$resource" ]; then
        echo "error: missing Sparkle resource: $resource" >&2
        exit 1
    fi
done

# Sparkle locates its installer helpers at the framework root through NSBundle.
# Keep those links alongside the binary and Resources links in a versioned framework.
rm -rf "$SPARKLE_VERSIONED/Resources/Updater.app" "$SPARKLE_VERSIONED/Resources/Autoupdate" \
       "$SPARKLE_VERSIONED/Updater.app" "$SPARKLE_VERSIONED/Autoupdate"
ditto "$SRCROOT/vendor/Sparkle/Helpers/Updater.app" "$SPARKLE_VERSIONED/Updater.app"
ditto "$SRCROOT/vendor/Sparkle/Helpers/Autoupdate" "$SPARKLE_VERSIONED/Autoupdate"
for name in Autoupdate Updater.app; do
    ln -sfn "Versions/Current/$name" "$SPARKLE_FW/$name"
done
mkdir -p "$SPARKLE_VERSIONED/Resources"
rsync -a "$SPM_RESOURCES/" "$SPARKLE_VERSIONED/Resources/"

# Debug's absolute PackageFrameworks rpath makes bundleForClass: resolve this copy.
if [ -d "$SPARKLE_PKG" ]; then
    mkdir -p "$SPARKLE_PKG/Resources"
    rsync -a "$SPM_RESOURCES/" "$SPARKLE_PKG/Resources/"
fi

# Sparkle's localization and helper lookup use its canonical bundle identifier.
for plist in "$SPARKLE_VERSIONED/Resources/Info.plist" "$SPARKLE_PKG/Resources/Info.plist"; do
    if [ -f "$plist" ]; then
        plutil -replace CFBundleIdentifier -string "org.sparkle-project.Sparkle" "$plist"
    fi
done

# Resource changes invalidate SPM's framework seal even when app signing is disabled.
IDENT="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
if [ "${CODE_SIGNING_ALLOWED:-YES}" = NO ]; then
    IDENT=-
fi
codesign --force --sign "$IDENT" "$SPARKLE_FW"
