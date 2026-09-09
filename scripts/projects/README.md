# AltTabProjects packaging

Worktree: `/Volumes/Case/prj/alt-tab-projects-release`, branch `projects-release`.

`config/projects.xcconfig` sets the Release app name, version, bundle ID, and `PROJECTS_DISTRIBUTION` condition. The app keeps normal Pro licensing, opens this fork for support and feedback, and uses the release page for updates. It does not start Sparkle or the upstream crash reporter. Debug settings are independent.

## Build

From the worktree root:

```sh
bash scripts/projects/build.sh
```

This uses the command-line build convention from `ai/build.sh`, producing an unsigned universal `DerivedData/Build/Products/Release/AltTabProjects.app`. Signing happens on a packaging copy so credentials do not enter build configuration or source control.

## Sign and notarize

The release uses `Developer ID Application: Medical Informatics Engineering, Inc. (X5873NL7XM)`. Its certificate and matching private key are installed in the login Keychain. Developer ID signing and nested signature verification passed on September 9, 2026.

The `alttab-projects` notarization profile is configured on this Mac. Apple accepted version 0.1.0, and the stapled app passed Gatekeeper assessment. The published output is `build/release-0.1.0/`. [Version 0.1.0](https://github.com/horner/alt-tab-macos/releases/tag/projects-v0.1.0) is available through the public `horner/projects/alttab-projects` cask; see the repository README for installation commands. The earlier portable test kit remains in `build/AltTabProjects-0.1.0-cask-test.zip`.

Create the notarization profile once, entering an Apple app-specific password at the secure prompt:

```sh
xcrun notarytool store-credentials alttab-projects \
  --apple-id YOUR_APPLE_ID \
  --team-id X5873NL7XM
```

Then package with that identity and profile:

```sh
python3 scripts/projects/package.py \
  --identity 'Developer ID Application: Medical Informatics Engineering, Inc. (X5873NL7XM)' \
  --notary-profile alttab-projects \
  --output build/release-0.1.0
```

The output directory must be new, and production packaging requires a clean working tree. The packager verifies both architectures in all embedded Mach-O files, signs nested code before the outer app, verifies the signature, submits for notarization, staples the accepted ticket, and verifies Gatekeeper assessment. It then writes the final ZIP, checksum, casks, and build metadata. A public cask is only generated after these checks pass.

Use the same Developer ID team and bundle identity on subsequent releases. `com.horner.alt-tab-projects` is a separate app identity from the current Debug installation. Export settings from Debug and use the app's settings import if desired. Projects data is included in those preferences. Keep the old installation available until the imported data and Pro activation are verified; permissions and license activation are not copied by the settings import. Enter the license normally on the other Mac. No account email, license key, or personal settings are packaged.

## Local Homebrew test

For packaging checks without distribution credentials:

```sh
python3 scripts/projects/package.py --test-only --output build/cask-test
bash build/cask-test/install-local.sh --appdir=/tmp/alttab-projects-cask-install
```

The ad-hoc test output is not notarized and must not be published as the friends release. The installer verifies the ZIP checksum, creates a local `horner/projects-local` tap if needed, and installs the cask `alttab-projects-local`. If Homebrew supports explicit tap trust, the installer trusts only this named cask. It leaves macOS quarantine handling intact. Local tests install into a temporary directory so the existing apps are not replaced.

For the prepared version 0.1.0 test, copy `build/AltTabProjects-0.1.0-cask-test.zip` to the other Mac and unzip it in Downloads:

```sh
cd ~/Downloads/AltTabProjects-0.1.0-cask-test
bash install-local.sh
```

For the other Mac, copy the signed distribution output directory, keeping its ZIP, `Casks/`, `SHA256SUMS.txt`, and `install-local.sh` together. Run:

```sh
cd /path/to/copied/distribution-0.1.0
bash install-local.sh
```

That installs `AltTabProjects.app` into Applications through Homebrew. Quit other AltTab variants, open the app, grant Accessibility and Screen Recording access, and activate Pro normally. Validate Projects creation/switching, Desktop navigation, window restoration, and relaunch persistence. The minimum bundle setting is macOS 10.14.4; actual Projects compatibility on older macOS versions and Intel hardware remains untested. The cask uses `depends_on :macos` because the bundle minimum predates Homebrew's currently allowed macOS releases.

To uninstall the local test while retaining app settings:

```sh
HOMEBREW_NO_AUTOREMOVE=1 brew uninstall --cask horner/projects-local/alttab-projects-local
```

Uninstall that local cask before installing a future public `alttab-projects` cask, because both install the same app filename. The local tap reads a copied ZIP; updating through GitHub requires the public cask below.

## GitHub distribution

The signed output contains `AltTabProjects.zip` and `Casks/alttab-projects.rb` with the final ZIP checksum and a versioned URL in `horner/alt-tab-macos`. Publish the matching `projects-v0.1.0` release asset before copying that cask to the fork's default branch. The release worktree guards the inherited workflow against running on this fork; apply that guard on the default branch before its cask update. No publication commands run as part of building or packaging.

Distribution packaging requires a clean, committed source snapshot and records its source commit and signing team. The release tag must point to that commit. Ad-hoc local tests may use uncommitted changes.

## Checks completed

- Universal Release build succeeded with Xcode 26.6.
- 1,332 tests passed in the Release test configuration.
- Every packaged Mach-O has `arm64` and `x86_64` slices.
- Local Homebrew installation and removal, cask style, ZIP checksum, and installed code-signature verification passed.
- Developer ID signing and nested signature verification passed with team `X5873NL7XM`.
- Apple notarization accepted submission `e73d2e75-e953-417a-ab49-af6c90c5048c`; the stapled app passes Gatekeeper as `Notarized Developer ID`.
- The portable kit was extracted into a different directory containing spaces and installed with the cask initially untrusted. Cask trust setup, installation, signature checks, ticket validation, and uninstall passed on macOS 26.6.2 / arm64.
- Both generated casks passed Homebrew style checks. Homebrew also downloaded the published GitHub asset and installed `/Applications/AltTabProjects.app`; the installed copy passed signature, ticket, Gatekeeper, version, bundle ID, and architecture checks. Actual launch and feature testing on the other Mac remain for the user.
- Comment audit: source baseline was 11,627 comment lines / 44,054 code lines. Reviewed `App.swift` (92 comment lines), `Endpoints.swift` (0), and `GeneralTab.swift` (3). Fixed the stale hard-coded license URL scheme in `App.swift`; retained the measured AppKit/WindowServer ordering notes. No runtime behavior changed in the comment audit.
