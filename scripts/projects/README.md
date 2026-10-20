# Deploy AltTabProjects

Run `./deploy.sh` from the **projects-release** worktree. This is the supported agent entry point
for publishing a friends prerelease, Sparkle update feed and Homebrew cask to **horner/alt-tab-macos only**.
The default branch carries the cask, `projects-updates` carries `appcast.xml`, and development can
continue in its separate checkout. All Projects users are eligible for the friends beta channel.

## Agent workflow

1. Use the existing publication authorization in the conversation. Preparing code or this tooling
   alone does not publish a new app version; use `--dry-run` for a preview.
2. Work on `projects-release`. Bring over only the intended app changes, preserve the developer's
   other checkout, and inspect the final diff. Keep `PRODUCT_NAME`, bundle ID and Team ID unchanged.
3. Choose an unpublished numeric version, for example `0.1.2` after `0.1.1`, and update
   `CURRENT_PROJECT_VERSION` in `config/projects.xcconfig`. The script reads this value; it does not
   increment versions or commit application changes for you.
4. Write release notes describing the user-visible changes, relevant limitations, and installation
   or upgrade instructions. A file outside the checkout, such as `/tmp/AltTabProjects-0.1.2.md`, is
   convenient; a file inside the checkout must be committed with the intended source. Review it.
5. Commit the intended source with the repository's conventional commit format. Leave the release
   worktree clean, including untracked files. Then run:

   ```sh
   ./deploy.sh --notes /tmp/AltTabProjects-0.1.2.md --dry-run
   ./deploy.sh --notes /tmp/AltTabProjects-0.1.2.md --prepare-only
   ```

6. Install and relaunch the exact signed candidate, replacing the existing local app while retaining
   a backup and its preferences. Perform the [runtime smoke tests](#runtime-smoke-tests-before-publication)
   and complete `build/deploy-<version>/runtime-smoke.json`. A build or successful ZIP download does
   not establish that the candidate was installed or tested. Then publish the same package:

   ```sh
   ./deploy.sh --notes /tmp/AltTabProjects-0.1.2.md --resume
   ```

7. Read the final result and `build/deploy-<version>/deployment.json`. Report the release and feed links,
   runtime observations, automated validation, and any remaining test-matrix limitations.

Versions 0.1.0 and [0.1.1](https://github.com/horner/alt-tab-macos/releases/tag/projects-v0.1.1) were
published manually before this script. The tooling itself does not change the app version. An ordinary attempt to deploy an
existing version is rejected; `--resume` is for recovering the same deployment, not republishing.

## Required setup

Use a Mac with command-line Xcode tools, Python 3.9 or newer, Git, GitHub CLI, and Homebrew.
The script invokes `xcodebuild` using the project's command-line build convention, not the Xcode UI.
GitHub CLI must authenticate to `github.com` with push access to the public `horner/alt-tab-macos`
fork. `origin` must fetch and push only that fork. Existing Git commit hooks still run.

The configured signing identity is:

```text
Developer ID Application: Medical Informatics Engineering, Inc. (X5873NL7XM)
```

Its certificate **and matching private key** must be available in Keychain. The notarization profile
on this Mac is `alttab-projects`. To configure it on another authorized signing Mac, import the
signing identity securely and enter an Apple app-specific password at the secure prompt:

```sh
xcrun notarytool store-credentials alttab-projects \
  --apple-id YOUR_APPLE_ID \
  --team-id X5873NL7XM
```

The script checks the identity and profile before building. `--identity` can select the established
Developer ID by name or SHA-1; `--notary-profile` selects another existing Keychain profile. Team
`X5873NL7XM` and bundle ID `com.horner.alt-tab-projects` remain mandatory. Do not put passwords,
private keys, license keys or exported personal preferences in source, notes or release assets.

Sparkle archive signing uses a separate Ed25519 private key in the Keychain account
`AltTabProjects Sparkle`; it does not use the Developer ID certificate. Its public key is committed
as `SPARKLE_PUBLIC_ED_KEY` in `config/projects.xcconfig` and embedded as `SUPublicEDKey` in the app.
Inspect only the public key with:

```sh
vendor/Sparkle/bin/generate_keys --account 'AltTabProjects Sparkle' -p
```

The established key must be present on the signing Mac. A new Mac needs that same key provisioned
securely; do not generate a replacement just to get a build working. Initial key creation uses
`vendor/Sparkle/bin/generate_keys --account 'AltTabProjects Sparkle'` only during an authorized
first setup. The package command rejects a Keychain key that differs from the app's public key.
Private update keys never belong in arguments, environment variables or repository files. Keep
the Developer ID, team, bundle ID and update key stable across releases.

The persistent Projects appcast is:

```text
https://raw.githubusercontent.com/horner/alt-tab-macos/projects-updates/appcast.xml
```

No hosting credentials beyond push access to this fork are needed. The first authorized deployment
creates the `projects-updates` branch with only `appcast.xml`; subsequent deployments change only
that file. There is no force push. A missing feed on an existing branch, malformed feed, changed
entry for an existing version, or newer published version stops feed publication. Do not create a
production feed as part of a tooling-only change. GitHub Raw can briefly cache the previous feed;
deployment verifies the public bytes with a commit query after its push.

Homebrew may download its style-check tooling. The script grants trust only to
`horner/projects/alttab-projects` on Homebrew versions that require it. All Homebrew commands disable
automatic updates, removal of unrelated dependencies, and installation cleanup. The script updates
only this tap explicitly. The command does not itself install, uninstall, launch or quit any app or
change preferences; installing and testing the candidate is a required separate step before publication.

## What the command does

1. Checks the source branch, clean commit, stable app identity, fork remotes, GitHub access,
   existing tags/releases, default-branch CI guard, signing identity and notarization profile.
   It rejects a tag on different source and a cask downgrade.
2. Runs the deployment tooling tests and Release app test suite, then builds the universal app using
   `scripts/projects/build.sh`.
3. Runs `scripts/projects/package.py` to sign embedded code and the app, submit it to Apple, staple
   the accepted ticket, and check Gatekeeper. The package contains a ZIP, SHA-256 manifest, cask and
   build metadata identifying the exact source commit. The final ZIP is extracted and verified again,
   including Sparkle's `Autoupdate`, `Updater.app`, framework links/resources, every Mach-O's two
   architectures and nested signatures. That exact final ZIP is Ed25519 signed with the Projects
   Keychain account. `build-info.json` records its signature, byte length, minimum macOS, public key
   and explicit `beta` channel. A candidate appcast preview is saved alongside the deployment logs.
4. `--prepare-only` stops here with the signed ZIP and a pending runtime report. Before any tag or
   release push, ordinary deployment requires passing runtime observations tied to the exact version,
   source commit and ZIP checksum. It validates the installed app and the running process against
   both signed architectures from that ZIP. Replacing app files while an older process is running
   does not satisfy the gate.
5. Pushes the release branch and an annotated `projects-v<version>` tag atomically, without force.
   Creates a draft prerelease, uploads the three assets, and verifies their GitHub SHA-256 digests
   (or downloads them to compare when GitHub does not supply a digest). Existing assets are never
   clobbered, and mismatches stop deployment.
6. Publishes the prerelease and downloads its ZIP anonymously from the public URL. Checks its
   checksum, version, bundle ID, Developer ID team, both architectures, signature, stapled ticket
   and Gatekeeper before publishing its feed or pointing the cask at it.
7. Appends the signed update to `projects-updates:appcast.xml` through a temporary worktree, then
   verifies an anonymous download of that feed. Its version, minimum macOS, enclosure URL, exact ZIP
   byte length and signature come from the verified package. The description contains the public
   GitHub release's actual notes as escaped plain text, and its publication timestamp stays stable
   on retries. Prior entries are retained; matching entries are left byte-for-byte unchanged and
   mismatches or downgrades fail. GitHub prerelease status is not a Sparkle channel: every item is
   explicitly `beta`, and Projects opts all users into that channel.
8. Creates a temporary detached worktree from the fork's current default branch. Changes only
   `Casks/alttab-projects.rb` and the first release download link in `README.md`, commits, and pushes without
   force. The inherited upstream publishing job must remain guarded by
   `github.repository == 'lwouis/alt-tab-macos'`. The script does not edit workflows or upstream.
9. Adds or updates the `horner/projects` tap, checks cask style, and uses `brew fetch` to download
   the release ZIP. Verifies that actual Homebrew download and the extracted app. It leaves any
   installed AltTabProjects app in place.

Build/package commands alone still do not publish. The implementation behind the shell entry point
is `scripts/projects/deploy.py`; archive signing is in `scripts/projects/package.py`, and appcast
generation is in `scripts/projects/updates.py`. The generated cask declares `auto_updates true`.

## Runtime smoke tests before publication

Use `--prepare-only` first. It performs the real tests, universal build, signing, notarization and
package checks without publishing a tag, GitHub release or cask. It writes a pending JSON report
at `build/deploy-<version>/runtime-smoke.json`; `--smoke-report /absolute/path/report.json` selects
another location. Existing reports are preserved rather than overwritten on retry.

Quit the running development or installed AltTab variant. Retain the existing app bundle outside
its installation location as a backup, then extract `build/release-<version>/AltTabProjects.zip`
and install its `AltTabProjects.app` in `/Applications`. Replace the whole bundle, rather than
copying new files over the old bundle. Keep existing preferences and permission grants. Launch
that installed app by its full path and verify its displayed release version.

Complete every report check with `"result": "pass"` and concrete `"observations"` after exercising
the behavior: startup and permissions; switcher cycling, search, dismissal and focus; Projects,
Desktop navigation and labels; Settings and retained preferences; the changes described in these
release notes; and persistence after quitting and relaunching. For a release with folder launchers,
the release-change observations must cover iTerm2 and VS Code reuse/new-window actions and the
folder picker, including Automation permission behavior. Failed or untested behavior must remain
`fail` or `pending` and blocks publication; fix the source and prepare a new candidate before retrying.

Computer Use can exercise these checks against the installed app. Attach by the full
`/Applications/AltTabProjects.app` path, since LaunchServices can retain records for backup and
staging copies. If attachment still reports a previous bundle identifier after replacement,
restart the native Computer Use helper and attach again; resetting its JavaScript session alone
did not clear cached app metadata during 0.1.5 validation. Preserve the app identity and existing
macOS permissions. Record observed UI outcomes, and leave a check pending when automation has
not exercised it.

Record `tester`, `tested_at` as an ISO timestamp with timezone, `installed_app` as the absolute
bundle path in `/Applications` or `~/Applications`, and `running_pid` after the relaunch test. For example,
`pgrep -x AltTabProjects` lists candidate PIDs and `codesign --display --verbose=4 +<pid>` identifies
their executable paths. Preserve the generated version, source commit and ZIP checksum fields.
The publisher checks that the installed signature matches the package's code hashes and that this
actual running process has the same identity, code hash and installed executable path. It records
the evidence in `runtime-smoke-verified.json` and the final deployment result.

Resume without changing the source or rebuilding the package. A report for another candidate, an
older running process, or a missing observation stops deployment before tag creation or publication.
There is no flag to bypass the runtime gate for an unpublished candidate. Recovery of an updater-enabled release
already public skips this new gate so its immutable assets, feed and cask can still be verified; that
recovery does not claim that runtime testing happened before publication. A local smoke test also
does not establish Intel or older-macOS compatibility beyond the machine actually tested.

## Output and recovery

- `build/release-<version>/` holds the original signed package. Retain this directory for retries.
- `build/deploy-<version>/` holds `tooling-tests.log`, `tests.log`, `build.log`, `package.log`, the runtime
  smoke report and verified evidence, `cask-style.log`, `brew-fetch.log`, and, after success, `deployment.json`.
  It also holds `appcast-preview.xml` before publication and `appcast.xml`/`public-appcast.xml` after
  feed publication. The result records the persistent feed URL and verified feed commit.
- `build/projects-tests/` caches test build products. Build output is ignored by Git.
- An OS file lock prevents two deployments in the same checkout. It releases automatically when
  the process exits, including interruption; a leftover lock file does not need deletion.

After resolving an interruption, rerun the same command with `--resume`, keeping the same clean
source commit, version and original package:

```sh
./deploy.sh --notes /tmp/AltTabProjects-0.1.2.md --resume
```

Tests run again. A completed package is verified and reused without rebuilding or signing. A partial
draft gets only its missing assets; matching assets remain untouched. An already published release
is verified without editing its assets, status or notes, and deployment continues to its feed, cask and
Homebrew checks. Existing remote tag objects are fetched rather than recreated.

Version 1.0.5 and older packages lack the required Sparkle metadata/helpers and cannot be resumed
with this tooling. Historical recovery requires the original release source/tooling and original
completed package, subject to its source and no-downgrade checks. Do not retrofit update metadata
or helpers into a published package or replace its assets; release a new updater-enabled version.

If packaging failed before `build-info.json` was written, preserve the incomplete output under a
different name, then retry. Once a GitHub release exists, recovery requires its original completed
package; do not rebuild or replace the published ZIP. Do not advance the release branch until the
deployment has finished. If a newer cask has already shipped, an older deployment cannot roll it back.

A rejected feed or default-branch push leaves its temporary checkout under `build/deploy-<version>/`
and prints its path. Inspect it if needed; `--resume` prepares a fresh checkout from the latest
remote branch. Do not force-push. Remove retained test checkouts with `git worktree remove`
after review. A local Homebrew tap with edits or a custom branch is preserved and causes verification
to stop; resolve those changes before retrying. An already published release stays published if a
later feed, cask or Homebrew step fails. An already published feed also stays in place if a later
cask or Homebrew step fails. Never replace its ZIP to repair a release; publish a new version.

`--dry-run` is strictly a local preview: it does not build, check credentials, query GitHub, fetch Git
refs, modify files or publish. It permits uncommitted preparation, but a real run requires a clean
commit and validates remote state. It is not a successful deployment check.

## Test deployment tooling without publishing

```sh
bash -n deploy.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/projects -p 'test_*.py' -v
./deploy.sh --notes /path/to/reviewed-notes.md --dry-run
```

The tests simulate GitHub and signing boundaries and use real temporary Git repositories to check
cask/feed-only pushes, preserved source work, retries, publication ordering, CI guards, version ordering,
signature metadata, helper packaging, and paths containing
spaces. They do not contact Apple/GitHub or install apps. A real deployment still requires the
credential and artifact checks above.

## Test an actual Sparkle upgrade without publication

Use disposable test checkouts and a local HTTPS server with a certificate trusted by the test Mac.
Build two distinct numeric versions, A and B, with the same established Developer ID, team, bundle ID
and Sparkle public key. Override `CURRENT_PROJECT_VERSION` and `SPARKLE_FEED_URL` at command-line
build time to use the test versions and test server; do not edit a signed app's `Info.plist`. Use the
universal Release command from `scripts/projects/build.sh`, then `package.py` with the established
identity and notarization profile for each build. Keep both completed outputs. These test packages
must never be passed to `deploy.sh` or published to the production feed.

Serve B's exact signed final ZIP and a test appcast containing its metadata. Generate that appcast
with `updates.appcast(build_info, zip_path, notes, published_at)`, then change only the test copy's
channel link and enclosure URL to the local HTTPS URLs. Keep the signature and byte length from B.
Install A in `/Applications` after retaining a rollback bundle and a preferences backup. Quit other
AltTab variants, launch A by full path, and use Settings → General → Check for Updates. Observe B's
notes, download, installation and relaunch; record the displayed version and running process before
and after. Confirm Projects, settings, stored license data and macOS permissions survive.

Repeat with an empty/no-newer feed, an unreachable server, Later/Cancel/Skip, and a deliberately
invalid signature; invalid content must not replace A. Exercise the Homebrew-installed location too.
Restore the rollback bundle and existing preferences when finished. Record the actual architecture
and macOS version tested; retain pending status for untested Intel/older-macOS or UI scenarios.

## Build and package separately

For local compilation only:

```sh
bash scripts/projects/build.sh
```

For a signed package without GitHub publication, use a new output directory and clean committed source:

```sh
python3 scripts/projects/package.py \
  --identity 'Developer ID Application: Medical Informatics Engineering, Inc. (X5873NL7XM)' \
  --notary-profile alttab-projects \
  --output build/manual-package
```

For an ad-hoc packaging test, `--test-only` produces a local-only archive that must not be published:

```sh
python3 scripts/projects/package.py --test-only --output build/cask-test
bash build/cask-test/install-local.sh --appdir=/tmp/alttab-projects-cask-install
```

The local installer validates the ZIP, creates `horner/projects-local`, and trusts only its named
cask when required. Use a machine without another cask owning `AltTabProjects.app` for install tests.
Do not uninstall an existing app merely to test packaging; the deployment script's `brew fetch`
verification avoids that conflict.

## Friends installing or updating

New installation:

```sh
if brew command trust >/dev/null 2>&1; then brew trust --cask horner/projects/alttab-projects; fi
brew tap horner/projects https://github.com/horner/alt-tab-macos.git
brew install --cask horner/projects/alttab-projects
```

Version 1.0.5 and older have no working updater helpers. Existing users need one manual download
or Homebrew upgrade to the first updater-enabled release. New installations check daily, show
Sparkle's update prompt, and install/relaunch after approval. All existing saved update policies
are retained, including manual policies that some 1.0.5 installations saved without a user choice.
After upgrading, use Settings → General → Check for updates now… to check immediately, or select
Check for updates periodically to enable daily checks. The same Updates policy menu can disable
checks or enable automatic installation. Friends betas are offered to all Projects users.

Homebrew bootstrap or explicit upgrade:

```sh
brew update
brew upgrade --cask --greedy horner/projects/alttab-projects
```

Quit other AltTab variants before opening AltTabProjects and grant Accessibility and Screen Recording
access. The current source enables all features without activation and hides purchase UI; existing
stored license data remains untouched. First-run naming, Projects membership, Desktop navigation,
and relaunch behavior require hands-on testing. Settings → General offers Export, Reset and Import
for testing defaults while retaining a backup. Preserve the established signing and bundle identity.
Minimum macOS and Intel runtime behavior need a real test matrix; universal packaging alone does
not establish runtime compatibility.
