# Deploy AltTabProjects

Run `./deploy.sh` from the **projects-release** worktree. This is the supported agent entry point
for publishing a friends prerelease and its Homebrew cask to **horner/alt-tab-macos only**.
The default branch carries the cask; development can continue in its separate checkout.

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
   ./deploy.sh --notes /tmp/AltTabProjects-0.1.2.md
   ```

6. Read the final result and `build/deploy-<version>/deployment.json`. Report the release link,
   validation results, and anything that still requires hands-on testing. Do not claim first-run
   UI testing from build or packaging checks alone.

The current published app is [0.1.1](https://github.com/horner/alt-tab-macos/releases/tag/projects-v0.1.1).
The deployment tooling itself does not change the app version. An ordinary attempt to deploy an
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

Homebrew may download its style-check tooling. The script grants trust only to
`horner/projects/alttab-projects` on Homebrew versions that require it. All Homebrew commands disable
automatic updates, removal of unrelated dependencies, and installation cleanup. The script updates
only this tap explicitly. It does not install, uninstall, launch or quit any app or change preferences.

## What the command does

1. Checks the source branch, clean commit, stable app identity, fork remotes, GitHub access,
   existing tags/releases, default-branch CI guard, signing identity and notarization profile.
   It rejects a tag on different source and a cask downgrade.
2. Runs the deployment tooling tests and Release app test suite, then builds the universal app using
   `scripts/projects/build.sh`.
3. Runs `scripts/projects/package.py` to sign embedded code and the app, submit it to Apple, staple
   the accepted ticket, and check Gatekeeper. The package contains a ZIP, SHA-256 manifest, cask and
   build metadata identifying the exact source commit. The ZIP is extracted and verified again.
4. Pushes the release branch and an annotated `projects-v<version>` tag atomically, without force.
   Creates a draft prerelease, uploads the three assets, and verifies their GitHub SHA-256 digests
   (or downloads them to compare when GitHub does not supply a digest). Existing assets are never
   clobbered, and mismatches stop deployment.
5. Publishes the prerelease and downloads its ZIP anonymously from the public URL. Checks its
   checksum, version, bundle ID, Developer ID team, both architectures, signature, stapled ticket
   and Gatekeeper before pointing the cask at it.
6. Creates a temporary detached worktree from the fork's current default branch. Changes only
   `Casks/alttab-projects.rb` and the first release download link in `README.md`, commits, and pushes without
   force. The inherited upstream publishing job must remain guarded by
   `github.repository == 'lwouis/alt-tab-macos'`. The script does not edit workflows or upstream.
7. Adds or updates the `horner/projects` tap, checks cask style, and uses `brew fetch` to download
   the release ZIP. Verifies that actual Homebrew download and the extracted app. It leaves any
   installed AltTabProjects app in place.

Build/package commands alone still do not publish. The implementation behind the shell entry point
is `scripts/projects/deploy.py`; the signing implementation is `scripts/projects/package.py`.

## Output and recovery

- `build/release-<version>/` holds the original signed package. Retain this directory for retries.
- `build/deploy-<version>/` holds `tooling-tests.log`, `tests.log`, `build.log`, `package.log`, `cask-style.log`,
  `brew-fetch.log`, and, after success, `deployment.json`.
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
is verified without editing its assets, status or notes, and deployment continues to its cask and
Homebrew checks. Existing remote tag objects are fetched rather than recreated.

If packaging failed before `build-info.json` was written, preserve the incomplete output under a
different name, then retry. Once a GitHub release exists, recovery requires its original completed
package; do not rebuild or replace the published ZIP. Do not advance the release branch until the
deployment has finished. If a newer cask has already shipped, an older deployment cannot roll it back.

A rejected default-branch push leaves the temporary cask checkout under `build/deploy-<version>/`
and prints its path. Inspect it if needed; `--resume` prepares a fresh checkout from the latest
remote default branch. Do not force-push. Remove retained test checkouts with `git worktree remove`
after review. A local Homebrew tap with edits or a custom branch is preserved and causes verification
to stop; resolve those changes before retrying. An already published release stays published if a
later cask or Homebrew step fails.

`--dry-run` is strictly a local preview: it does not build, check credentials, query GitHub, fetch Git
refs, modify files or publish. It permits uncommitted preparation, but a real run requires a clean
commit and validates remote state. It is not a successful deployment check.

## Test deployment tooling without publishing

```sh
bash -n deploy.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/projects -p 'test_deploy.py' -v
./deploy.sh --notes /path/to/reviewed-notes.md --dry-run
```

The tests simulate GitHub and signing boundaries and use real temporary Git repositories to check
cask-only pushes, preserved source work, retries, CI guards, version ordering, and paths containing
spaces. They do not contact Apple/GitHub or install apps. A real deployment still requires the
credential and artifact checks above.

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

Update:

```sh
brew update
brew upgrade --cask horner/projects/alttab-projects
```

Quit other AltTab variants before opening AltTabProjects, grant Accessibility and Screen Recording
access, and activate Pro normally. First-run naming, Projects membership, Desktop navigation, and
relaunch behavior require hands-on testing. Settings → General offers Export, Reset and Import for
testing defaults while retaining a backup. The release keeps the existing licensing behavior and
its distinct identity from AltTabDebug. Minimum macOS and Intel runtime behavior need a real test
matrix; universal packaging alone does not establish runtime compatibility.
