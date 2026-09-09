# AltTabProjects friends release plan

Status: implementation and local cask testing authorized on September 9, 2026. Worktree: `/Volumes/Case/prj/alt-tab-projects-release`, branch `projects-release`. The current development changes were copied here without modifying the original checkout. A universal Release build and all 1,332 existing tests passed. Local cask installation and checksum/signature checks passed with a disposable ad-hoc copy. The selected Medical Informatics Engineering Developer ID team is `X5873NL7XM`. Developer ID signing, Apple notarization, ticket stapling, Gatekeeper assessment, cask style checks, and installation from the portable test kit passed. The signed output is `build/distribution-0.1.0/`, and `build/AltTabProjects-0.1.0-cask-test.zip` is ready to copy to the other Mac. Actual launch and feature testing on that Mac remain. The user authorized publishing a GitHub prerelease and testing the remote Homebrew download on September 9, 2026.

Publish a downloadable `AltTabProjects.app` through releases in `horner/alt-tab-macos`, with a Homebrew cask that installs that same release ZIP. Start with a manually initiated prerelease and updates through Homebrew or direct download. Keep distribution work on a dedicated branch so development can continue on `horner`.

## Findings from the current checkout

- `origin` is `horner/alt-tab-macos`; `upstream` is `lwouis/alt-tab-macos`. GitHub reports that the fork is public, its default branch is `master`, and its release list is empty.
- The working branch is `horner`, currently at `620cab02`, with substantial uncommitted Projects and Spaces work. The release source must include the intended finished changes, not just the current committed tip.
- Ignored `config/local.xcconfig` sets `AltTabDebug`, `com.lwouis.alt-tab-macos.debug`, version `99.0.0`, and an Apple Development signing identity. Both Debug and Release include this local file, so the existing Release configuration alone does not establish a distributable identity.
- `config/base.xcconfig` defaults to `AltTab` and upstream's bundle ID. `config/release.xcconfig` names upstream's Developer ID. The target's Release team comes from `TEAM_ID`.
- `.github/workflows/ci_cd.yml` runs on pushes to `master`. It performs semantic releases, updates upstream appcast links, uploads crash symbols, and dispatches an update to upstream's website repository. It is unsuitable for the friends release unchanged.
- `src/api/Endpoints.swift` derives the Sparkle feed, licensing, feedback, account, and purchase endpoints from upstream's domain. `Info.plist` embeds upstream's Sparkle public key; `src/App.swift` points repository links upstream.
- The inherited license manager starts a 14-day trial. The Debug QA helpers are excluded from Release, so their behavior cannot provide permanent feature access for friends.
- The user reports that Pro is activated for their account. Preserve that activation when planning the transition from Debug to the friends release. The account email and activation credentials are not part of the public release configuration. This is user-reported status, not an independently verified activation.
- Projects are saved in preferences. General settings already offers settings export/import, which can form the basis of a deliberate migration from the Debug app.

## Recommended release shape

| Item | Proposal |
| --- | --- |
| Development branch | Keep using `horner` |
| Distribution branch | `projects-release`, based on a reviewed, committed snapshot of `horner` |
| First tag | `projects-v0.1.0` |
| GitHub release title | `AltTabProjects 0.1.0 — Friends beta` |
| Release status | Prerelease, initially created as a draft |
| Download | `AltTabProjects.zip` containing `AltTabProjects.app` |
| Extra asset | `SHA256SUMS.txt` |
| Bundle version | `0.1.0` in both existing version fields; increment for every subsequent release |
| Homebrew package | Cask `alttab-projects` in the fork's top-level `Casks/` directory |
| Installation | Homebrew cask, or unzip and move to Applications; open and grant the app's requested permissions |
| Updates | `brew upgrade --cask horner/projects/alttab-projects`, or manual replacement from the release page |

Use the same app target with explicit Projects release settings, keeping the branding and distribution changes compact. An additional scheme/configuration is appropriate if needed to isolate those settings. Merely renaming a built `.app` is insufficient: product name, executable, bundle metadata, packaging paths, and user-facing identity must agree.

## Implementation stages, after the user gives the go

1. **Choose and isolate the source.** Review the current uncommitted work, finish and commit the intended release contents, then create `projects-release` and use a separate checkout/worktree for release work. Do not blanket-commit the present working tree. Keep future release fixes on this branch; bring general fixes back to `horner` and merge selected development snapshots into the release branch. Record the exact source commit in every release.

2. **Establish the app identity.** Set the release product name to `AltTabProjects`, use a stable fork-specific bundle ID such as `com.horner.alt-tab-projects`, and establish the user's distribution Team ID and Developer ID identity. The exact bundle ID is a proposal until confirmed. Ensure local Debug overrides and `99.0.0` cannot leak into release builds. Keep Release optimization and omit Debug QA UI.

   Treat this as a separate installation from upstream and the current Debug app. Before moving an existing installation, export and back up settings, validate importing Projects data, and test relaunch. Do not assume settings import transfers licenses or macOS permissions. The repository's license/Keychain invariant requires an explicit migration before changing an existing installation's signing or bundle identity: preserve the user's reported Pro activation, or arrange export/restore or supported reactivation before retiring the old app. Verify Pro remains available after migration and relaunch before replacing the existing installation. Fix the friends app's identity before its first distribution and keep it stable in later builds.

3. **Separate fork distribution from upstream services.** Disable Sparkle initialization and all scheduled/manual/feedback-preflight update checks for this distribution; a high version number or changing only the automatic-check default is insufficient. Replace update UI with an “Open releases” action for this fork. Route support and issue links here, and disable upstream crash-report submission and feedback posting. Preserve appropriate upstream attribution. Configure these endpoints independently so changing the update or support destination does not inadvertently break retained licensing services.

   Preserve existing licensing behavior while the friends-build policy remains undecided. The user's personal Pro activation does not by itself choose a licensing policy for friends. The earlier suggestion of fully unlocked friends builds remains an unapproved option. Do not bundle the user's account, license key, or local activation state into the app or Homebrew package. Once the user chooses the friends policy, validate fresh installation, activation where applicable, and behavior after the inherited trial would expire. Do not rely on Debug mock state.

4. **Add a workflow confined to this fork.** Create `.github/workflows/projects-release.yml` on the release branch. Trigger it only on pushed `projects-v*` tags, require `github.repository == 'horner/alt-tab-macos'`, validate the version, and verify the tagged commit belongs to the release branch. Ordinary branch pushes must not publish. Explicitly target this repository for release creation. Disable the inherited publishing workflow in the fork before using its release machinery, and exclude its appcast, website, crash-symbol, and semantic-release steps from the new workflow.

   Use a clean checkout with explicit release settings, a pinned/tested macOS toolchain, and scoped permissions: read access for building and `contents: write` only where release assets are uploaded. Store the user's signing/notarization credentials in this fork's Actions secrets, import signing material into a temporary keychain, and clean it up. Do not print secrets or use the old environment-dump script. Create a draft prerelease after successful validation; the user can then publish the reviewed assets.

   A tag trigger avoids needing to alter `master` just to expose a manual workflow button. If a button is preferred later, GitHub requires a `workflow_dispatch` workflow to exist on the default branch, even when it runs against another branch. See [GitHub's manual workflow documentation](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).

5. **Build and package only after authorization.** Confirm a usable Developer ID Application certificate and notarization credentials belonging to the user. The selected Developer ID Application identity for Medical Informatics Engineering, Inc. (`X5873NL7XM`) is installed with its matching private key, and signing verification passed. The `alttab-projects` notarization profile is configured, and Apple accepted the first signed build.

   Use the command-line build conventions in `ai/build.sh`, adapted for Release and explicit Projects settings. Target Apple silicon and Intel, then verify both architecture slices in the app and required embedded components. Sign the app and nested code correctly, notarize, staple the ticket to the app, and re-create the ZIP from that stapled app. Verify signatures, notarization, archive contents, and the final checksum. Apple describes Developer ID signing and notarization for direct distribution in its [Developer ID guidance](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) and [packaging guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

6. **Validate the download experience and publish.** Test the actual ZIP after a browser download, on a clean account or another Mac, before publishing the draft. Cover first launch, Accessibility and Screen Recording permission setup, ordinary window switching, Projects creation and switching, Desktop navigation, browser restoration, saved data after relaunch, login launch, and installing the next version over the previous one. Verify the selected license policy, the user's Pro migration, and that upstream update/feedback/crash services receive no requests. Any licensing requests must match the chosen policy. Quit other AltTab variants during shortcut checks.

   Run the relevant existing tests plus focused tests for distribution-specific behavior once builds are authorized. Test Apple silicon and Intel before claiming both are supported. The current deployment setting is macOS 10.14.4, but the Projects feature's supported macOS range must be established by testing; do not infer compatibility from that setting alone. Include clear setup instructions, tested macOS versions, known limitations, attribution, existing license notices, and the exact source tag in the release notes. Publish the reviewed draft at `https://github.com/horner/alt-tab-macos/releases`.

7. **Publish the Homebrew cask.** Keep both the app assets and cask in the existing `horner/alt-tab-macos` repository. Add `Casks/alttab-projects.rb` to its default branch, currently `master`, after disabling the inherited publishing workflow there. The release implementation stays on `projects-release`; the default branch receives the small cask definition and its version updates. A cask present only on the release branch will not be found by a normal tap of the repository's default branch.

   Friends would run the following commands once this distribution exists:

   ```sh
   brew tap horner/projects https://github.com/horner/alt-tab-macos.git
   brew install --cask horner/projects/alttab-projects
   ```

   Homebrew supports an explicit Git URL for repositories without the usual `homebrew-` name, so this does not require another repository. `horner/projects` is the local tap name mapped to this fork. See [Homebrew's tap documentation](https://docs.brew.sh/Taps).

   Define the cask with version `0.1.0`, the SHA-256 of the final notarized/stapled ZIP, URL `https://github.com/horner/alt-tab-macos/releases/download/projects-v0.1.0/AltTabProjects.zip`, name `AltTabProjects`, the fork homepage, an accurate description, and `app "AltTabProjects.app"`. Use a versioned URL and real checksum. Declare the tested minimum macOS version once established. Keep the distinct `alttab-projects` token rather than taking over the upstream `alt-tab` cask. Homebrew casks describe installation of the prebuilt app; friends do not compile it. See the [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook).

   Validate the cask syntax/style and audit the public asset, then test install, launch, upgrade, and uninstall with the released ZIP. Installation still needs the app's normal permission onboarding. Ordinary uninstall must retain preferences and Projects data; any optional full cleanup must be restricted to this app's confirmed identity. Retain the signed/notarized distribution requirement.

   Publish the GitHub asset first, then update the default-branch cask's version and checksum. Never point the public cask at an inaccessible draft release. Initially make the small cask update explicitly after publication; automate it later using the same repository's scoped credentials if useful. A failed cask update leaves the previous version available and can be retried without rebuilding the app.

   To update later, friends run:

   ```sh
   brew update
   brew upgrade --cask horner/projects/alttab-projects
   ```

   A future lightweight `horner/homebrew-tap` companion repository could shorten installation to `brew install --cask horner/tap/alttab-projects` and avoid cloning the app source into Homebrew. That is optional; the initial plan keeps distribution entirely in the existing fork.

## Follow-up releases

Use a new version and tag for every published binary; keep previous downloads available. If a release is broken, document the issue and publish a corrected version rather than silently replacing its assets. Back up settings before downgrades when the stored data format has changed.

Update the Homebrew cask after each release's assets are publicly available and verified. This gives friends an upgrade path without an in-app updater. Add in-app automatic updates only if useful later; that requires the fork's own Sparkle signing keys and public feed, matching release asset URLs, version ordering, and an end-to-end upgrade test. It should be a separate milestone.

## Decisions still needed

- Friends-build feature policy remains undecided. The user reports personal Pro activation; preserve existing licensing behavior until they choose how friends receive feature access.
- Keep bundle ID `com.horner.alt-tab-projects` and the selected Medical Informatics Engineering Developer ID team `X5873NL7XM` stable. The configured `alttab-projects` profile notarized version 0.1.0 successfully; verify actual app behavior on the other Mac before public release.
- Identify friends' macOS versions and whether Intel support is needed to set the actual test matrix.

See `scripts/projects/README.md` for the implemented build, package, and local cask test commands. Publishing to GitHub remains a separate step after the signed artifact is ready for review.
