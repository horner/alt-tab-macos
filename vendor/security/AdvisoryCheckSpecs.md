# Dependency advisory checks

`check_advisories.py` checks Yams and the libyaml sources bundled inside Yams.
The versioned `dependencies.json` inventory records source fingerprints and upstream
identity. Yams's version and commit come from the committed SPM `Package.resolved`.
The checker verifies that the project requests that exact release, then downloads
only its resolved commit into a temporary Git checkout. It does not build or execute
the downloaded package. The checkout is removed after the scan; no copy is committed.
Git and Python 3.9 or later are required. Each Git command has a timeout.

Libyaml's base commit and the changes applied by Yams are recorded separately from
the Swift wrapper's release. This provenance is tied to the containing Yams commit
and must be reviewed after a package update. Fingerprints include relative file names
and file contents; a changed dependency must have its provenance reviewed before the
scanner can pass. Git download failures, a mismatched checkout, stale lockfiles and
changed fingerprints all fail the check.

The checker uses the [OSV query API](https://google.github.io/osv.dev/post-v1-query/)
for each commit and, for Yams, its SwiftURL package version. It also checks
[published repository security advisories](https://docs.github.com/en/rest/security-advisories/repository-advisories)
in both upstream repositories. Repository advisories without a matching OSV record
require manual applicability review; they are not presented as confirmed affected
versions. Withdrawn advisories are excluded. All pages are checked, and duplicate
OSV matches for one dependency are combined.

Exit codes are 0 for no returned matches or unreviewed upstream advisories, 1 for
findings, and 2 for incomplete checks (invalid metadata, changed sources, bad API
responses, pagination failures, rate limits or network failures). Incomplete checks
never produce a clean report. Requests have timeouts and at most three attempts.
GitHub credentials are optional locally and are sent only to its API. Source files,
project files and user data are not uploaded; queries contain public dependency
identifiers. Coverage is limited to published records available from these services.

## Running and reviewing

From the repository root:

```sh
python3 -B -m unittest discover -s vendor/security -p '*Tests.py' -v
python3 -B vendor/security/check_advisories.py --json /tmp/vendor-advisories.json
```

A matching OSV advisory always fails the check. Do not suppress it to make CI green.
For a repository-only advisory determined not to apply, add a reviewed entry with
`dependency`, `id`, `revision`, `modified` (the advisory's `updated_at`) and a nonblank
`reason` to `reviewed_repository_advisories`. The review becomes invalid when the
advisory changes or the pinned revision changes. It cannot suppress an OSV match.

To update Yams, change its exact release in `project.pbxproj`, then resolve packages:

```sh
xcodebuild -resolvePackageDependencies -project alt-tab-macos.xcodeproj -scheme Debug -derivedDataPath DerivedData
```

Review the resulting `Package.resolved` commit against upstream. Review Yams's libyaml
import history and backported changes, update the library's `package_revision`, base
commit and `upstream_changes` in the inventory as needed, then print fingerprints:

```sh
python3 -B vendor/security/check_advisories.py --fingerprints
```

Update the reviewed inventory fingerprints, rerun the advisory check and the app's
storage tests, build, and commit the project requirement, lockfile and inventory together.
The checker does not automatically bless changed fingerprints or infer libyaml provenance.

## CI and notifications

`vendor_security.yml` runs daily at 09:41 UTC, on relevant pushes and pull requests,
and through Run workflow. It uses a pinned checkout action, a read-only token and the
runner's Python standard library and Git. Each run tests the checker and writes an advisory
report into the Actions job summary. Findings and incomplete scans fail the workflow;
notifications follow each maintainer's GitHub Actions notification settings. No issues
or messages are posted automatically, and no dependencies are updated automatically.

Scheduled runs begin after the workflow reaches the repository's default branch with
Actions enabled. GitHub disables scheduled workflows in inactive public repositories
after 60 days; forks may require explicitly enabling Actions and scheduled workflows.
See [GitHub's schedule documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

Tests cover package and commit requests, libyaml matches, source drift, review scope,
withdrawals, duplicate matches, pagination, malformed responses, retries and outages.
They also cover project/lockfile agreement, exact-commit downloads, temporary checkout
cleanup, download failures, source drift and stale bundled-library provenance.

## OSV-2020-1611 applicability review

The first live check on 2026-09-13 returned
[OSV-2020-1611](https://osv.dev/vulnerability/OSV-2020-1611) for libyaml base commit
`acd6f6f014c25e46363e718381e0b35205df2d83`: a medium-severity heap-buffer-overflow
read in `yaml_emitter_emit_flow_mapping_key`. Yams records this import in
[upstream commit 409e565](https://github.com/jpsim/Yams/commit/409e565756cfdf50642a59c8f4290a6961fe7f1d),
and Yams's `emitter.c` matches that libyaml revision byte for byte. The OSV
record returned no fixed revision.

Review on 2026-09-13 found no application patch indicated for this reported trigger:

- The libyaml maintainer closed the matching mapping-emitter reports as a defect in
  the fuzz harness ([issue 225](https://github.com/yaml/libyaml/issues/225#issuecomment-2120506373),
  [issue 268](https://github.com/yaml/libyaml/issues/268#issuecomment-2120500881)) and
  rejected the proposed library patch in [PR 228](https://github.com/yaml/libyaml/pull/228#issuecomment-2120493431).
- The harness returned failure after successful writes, then called the emitter again
  after the failure. The merged [OSS-Fuzz fix](https://github.com/google/oss-fuzz/pull/11818)
  corrects the callback's return values. Its description explains the empty-stack read.
- Our pinned `Sources/Yams/Emitter.swift` returns 1 after appending output, throws on
  a failed `yaml_emitter_emit`, and its top-level `serialize` skips `close` when emission
  throws. Deinitialization deletes the emitter. Project storage uses this top-level
  API and `YAMLEncoder`; it never catches an error and resumes an emitter. Its bundled
  C sources also omit the `dumper.c` API used by the faulty harness. Flow mappings
  remain reachable, so block formatting alone is not the basis for this assessment.

The original [OSS-Fuzz report](https://issues.oss-fuzz.com/issues/42486502) identifies
[testcase 6247032310988800](https://oss-fuzz.com/testcase?key=6247032310988800).
Its downloaded 16,299 bytes have SHA-256
`9ac95a334b90fef6cb148168a3baaac24389f62bf4b3aee69f80afb30c28a7da`.
A standalone Swift replay against Yams 5.1.3 passed 400 parse/serialize/parse
round trips: the complete input and input with the two fuzzer option bytes removed,
each with canonical output on and off, preserving mapping order. This exercised the
Yams API, not the full application's storage path. AddressSanitizer compilation
succeeded, but its runtime deadlocked during initialization before entering the
program on this macOS toolchain; no sanitizer pass is claimed. The upstream diagnosis
and local error-handling review are the primary evidence, not the absence of a crash.

The scanner still reports this active OSV record; this review does not suppress it.
Reassess if the advisory, bundled sources or application emitter usage changes.
Upstream confirmation is requested in [Yams issue 487](https://github.com/jpsim/Yams/issues/487).

## Upgrade and patch policy

Prefer a released upstream fix when a finding applies. Update the exact SPM release
and lockfile, review libyaml provenance and fingerprints, then run advisory checks,
storage tests and the app build. If no compatible release contains a required fix,
use a reviewed fork pinned to an immutable commit. Record its upstream patch and
regression test, retain advisory coverage of the original projects, and return to
the upstream package after a release includes the fix. Do not edit SPM cache files.

[Yams 6.2.2](https://github.com/jpsim/Yams/releases/tag/6.2.2) is pinned at
`a27b21e0c81c5bf42049b897a62aaf387e80f279`. It includes the separate parser nesting
security change from [PR 431](https://github.com/jpsim/Yams/pull/431), which was absent
from 5.1.3. The regression test `testExcessiveNestingFailsBeforeRecursiveComposition`
showed that a nested flow sequence could still reach Yams composition, so project
storage now validates libyaml events before recursive composition. The test covers
flow and block nesting; quoted and block scalar brackets remain valid.

The `emitter.c` in 6.2.2 remains byte-for-byte identical to 5.1.3; upgrading does not
clear OSV-2020-1611. Advisory checks continue to report it pending upstream review.
