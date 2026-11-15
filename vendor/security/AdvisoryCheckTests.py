import copy
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from urllib.error import URLError

import check_advisories as checker


class AdvisoryCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        source = self.root / "Sources"
        source.mkdir()
        (source / "parser.c").write_text("upstream source\n")
        (self.root / "UPSTREAM").write_text("VERSION=1.2.3@" + "a" * 40 + "\nSOURCE=https://github.com/example/parser.git\n")
        self.dependency = {"name": "Parser", "repository": "example/parser", "source_path": "Sources",
                           "source_sha256": checker.source_hash(source), "upstream_file": "UPSTREAM", "ecosystem": "SwiftURL"}
        self.manifest = {"schemaVersion": 1, "dependencies": [self.dependency], "reviewed_repository_advisories": []}

    @staticmethod
    def empty(url, payload=None):
        return ({}, "") if payload is not None else ([], "")

    @staticmethod
    def upstream():
        return {"ghsa_id": "GHSA-1234-5678-9abc", "summary": "Upstream advisory", "updated_at": "2026-09-13T10:00:00Z"}

    def testChecksCommitPackageVersionAndPublishedUpstreamAdvisories(self):
        requests = []
        def fetch(url, payload=None):
            requests.append((url, payload))
            return self.empty(url, payload)
        report = checker.scan(self.manifest, self.root, fetch)
        self.assertEqual(checker.exit_status(report), 0)
        self.assertEqual(requests[0][1], {"commit": "a" * 40})
        self.assertEqual(requests[1][1]["version"], "1.2.3")
        self.assertEqual(requests[1][1]["package"], {"ecosystem": "SwiftURL", "name": "https://github.com/example/parser"})
        self.assertIn("state=published", requests[2][0])

    def testBundledLibraryCommitMatchFails(self):
        self.dependency.pop("upstream_file")
        self.dependency["commit"] = "b" * 40
        def fetch(url, payload=None):
            if payload:
                self.assertEqual(payload["commit"], "b" * 40)
                return {"vulns": [{"id": "OSV-2020-1611", "summary": "Heap-buffer-overflow"}]}, ""
            return [], ""
        report = checker.scan(self.manifest, self.root, fetch)
        self.assertEqual(checker.exit_status(report), 1)
        self.assertEqual(report["findings"][0]["id"], "OSV-2020-1611")
        self.assertIn("OSV revision/version match", checker.markdown(report))
        self.assertNotIn("No matching", checker.markdown(report))

    def testDuplicateMatchesAndWithdrawnAdvisories(self):
        def fetch(url, payload=None):
            if payload:
                return {"vulns": [{"id": "OSV-active"}, {"id": "OSV-withdrawn", "withdrawn": "2025-01-01"}]}, ""
            return [{**self.upstream(), "withdrawn_at": "2025-01-01"}], ""
        report = checker.scan(self.manifest, self.root, fetch)
        self.assertEqual([v["id"] for v in report["findings"]], ["OSV-active"])

    def testUpstreamAdvisoryRequiresReviewWithoutClaimingApplicability(self):
        def fetch(url, payload=None):
            return ({}, "") if payload else ([self.upstream()], "")
        report = checker.scan(self.manifest, self.root, fetch)
        self.assertEqual(checker.exit_status(report), 1)
        self.assertEqual(report["findings"][0]["kind"], "Upstream advisory needs applicability review")

    def testReviewIsBoundToRevisionAdvisoryModificationAndReason(self):
        advisory = self.upstream()
        review = {"dependency": "Parser", "revision": "a" * 40, "id": advisory["ghsa_id"], "modified": advisory["updated_at"], "reason": "Fixed before this revision"}
        self.assertTrue(checker.is_reviewed(advisory, "Parser", "a" * 40, [review]))
        self.assertFalse(checker.is_reviewed(advisory, "Parser", "b" * 40, [review]))
        self.assertFalse(checker.is_reviewed({**advisory, "updated_at": "2026-09-14"}, "Parser", "a" * 40, [review]))
        self.assertFalse(checker.is_reviewed(advisory, "Parser", "a" * 40, [{**review, "reason": " "}]))
        self.manifest["reviewed_repository_advisories"] = [review]
        def fetch(url, payload=None):
            return ({"vulns": [{"id": advisory["ghsa_id"]}]}, "") if payload else ([advisory], "")
        report = checker.scan(self.manifest, self.root, fetch)
        self.assertEqual(checker.exit_status(report), 1)
        self.assertEqual([f["kind"] for f in report["findings"]], ["OSV revision/version match"])

    def testChangedSourceFailsBeforeQueryingAStalePin(self):
        (self.root / "Sources/parser.c").write_text("different version\n")
        report = checker.scan(self.manifest, self.root, lambda *args: self.fail("Must validate source provenance first"))
        self.assertEqual(checker.exit_status(report), 2)
        self.assertIn("fingerprint changed", report["errors"][0])

    def package(self):
        package = {"identity": "parser", "repository": "example/parser", "resolved_file": "Package.resolved", "project_file": "project.pbxproj"}
        data = {"version": 3, "pins": [{"identity": "parser", "kind": "remoteSourceControl", "location": "https://github.com/example/parser.git",
                                       "state": {"version": "1.2.3", "revision": "a" * 40}}]}
        (self.root / "Package.resolved").write_text(json.dumps(data))
        (self.root / "project.pbxproj").write_text('repositoryURL = "https://github.com/example/parser.git"; requirement = { kind = exactVersion; version = 1.2.3; };')
        return package, data

    def testResolvedPackageMustMatchProjectVersionRepositoryAndCommit(self):
        package, data = self.package()
        self.assertEqual(checker.resolved_package(package, self.root)["revision"], "a" * 40)
        for change in [lambda d: d.update(version=4), lambda d: d["pins"].clear(), lambda d: d["pins"].append(d["pins"][0]),
                       lambda d: d["pins"][0].update(location="https://github.com/other/parser.git"),
                       lambda d: d["pins"][0]["state"].update(revision="main"), lambda d: d["pins"][0]["state"].update(version="2.0.0")]:
            candidate = copy.deepcopy(data)
            change(candidate)
            (self.root / "Package.resolved").write_text(json.dumps(candidate))
            with self.assertRaises(ValueError):
                checker.resolved_package(package, self.root)

    def testRemoteSourcesUseResolvedVersionAndChangedSourcesFail(self):
        self.dependency.pop("upstream_file")
        self.dependency["package"] = "parser"
        packages = {"parser": {"directory": self.root, "repository": "example/parser", "version": "2.0.0", "revision": "b" * 40}}
        queries = []
        def fetch(url, payload=None):
            if payload:
                queries.append(payload)
            return self.empty(url, payload)
        report = checker.scan(self.manifest, self.root, fetch, packages)
        self.assertEqual(checker.exit_status(report), 0)
        self.assertEqual(queries[0], {"commit": "b" * 40})
        self.assertEqual(queries[1]["version"], "2.0.0")
        (self.root / "Sources/parser.c").write_text("unreviewed changes")
        self.assertEqual(checker.exit_status(checker.scan(self.manifest, self.root, self.empty, packages)), 2)

    def testBundledProvenanceRequiresReviewWhenParentPackageChanges(self):
        self.dependency.pop("upstream_file")
        self.dependency.update(package="parser", commit="b" * 40, package_revision="a" * 40)
        packages = {"parser": {"directory": self.root, "revision": "a" * 40}}
        self.assertEqual(checker.identify(self.dependency, self.root, packages), (None, "b" * 40))
        packages["parser"]["revision"] = "c" * 40
        with self.assertRaisesRegex(ValueError, "provenance needs review"):
            checker.identify(self.dependency, self.root, packages)

    def testPackageCheckoutFetchesExactCommitAndCleansUp(self):
        package, _ = self.package()
        calls = []
        def run(command, **kwargs):
            calls.append(command)
            return SimpleNamespace(stdout="a" * 40 + "\n")
        with patch.object(checker.subprocess, "run", side_effect=run):
            with checker.package_checkouts({"swift_packages": [package]}, self.root) as packages:
                directory = packages["parser"]["directory"]
                self.assertTrue(directory.is_dir())
                self.assertEqual(packages["parser"]["version"], "1.2.3")
            self.assertFalse(directory.exists())
        self.assertEqual(calls[1][3:], ["fetch", "--quiet", "--depth=1", "https://github.com/example/parser.git", "a" * 40])
        self.assertEqual(calls[2][3:], ["checkout", "--quiet", "--detach", "FETCH_HEAD"])

    def testWrongCheckoutAndDownloadFailureCannotPass(self):
        package, _ = self.package()
        with patch.object(checker.subprocess, "run", return_value=SimpleNamespace(stdout="b" * 40)):
            with self.assertRaisesRegex(ValueError, "differs from the resolved commit"):
                with checker.package_checkouts({"swift_packages": [package]}, self.root):
                    self.fail("Must reject wrong checkout")
        with patch.object(checker.subprocess, "run", side_effect=subprocess.TimeoutExpired("git", 60)):
            with self.assertRaises(subprocess.TimeoutExpired):
                with checker.package_checkouts({"swift_packages": [package]}, self.root):
                    self.fail("Must reject failed download")

    def testFingerprintIncludesAddedRemovedAndRenamedFiles(self):
        original = checker.source_hash(self.root / "Sources")
        path = self.root / "Sources/parser.c"
        path.rename(path.with_name("other.c"))
        self.assertNotEqual(checker.source_hash(self.root / "Sources"), original)
        path.with_name("other.c").rename(path)
        self.assertEqual(checker.source_hash(self.root / "Sources"), original)
        (self.root / "Sources/new.c").write_text("extra")
        self.assertNotEqual(checker.source_hash(self.root / "Sources"), original)

    def testMalformedMetadataAndPathsCannotProduceCleanScan(self):
        for replacement in [{"source_path": "../elsewhere"}, {"upstream_file": "missing"}, {"repository": "another/repository"}]:
            manifest = copy.deepcopy(self.manifest)
            manifest["dependencies"][0].update(replacement)
            self.assertEqual(checker.exit_status(checker.scan(manifest, self.root, self.empty)), 2)

    def testServiceFailureStillChecksOtherSourcesAndFailsIncomplete(self):
        requests = []
        def fetch(url, payload=None):
            requests.append(url)
            if payload:
                raise ValueError("Service unavailable")
            return [self.upstream()], ""
        report = checker.scan(self.manifest, self.root, fetch)
        self.assertEqual(len(requests), 3)
        self.assertEqual(checker.exit_status(report), 2)
        self.assertEqual(len(report["findings"]), 1)
        self.assertIn("Check incomplete", checker.markdown(report))
        self.assertNotIn("No matching", checker.markdown(report))

    def testOSVPaginationIncludesLaterMatches(self):
        pages = []
        def fetch(url, payload):
            pages.append(dict(payload))
            return ({"vulns": [{"id": "later"}]}, "") if payload.get("page_token") else ({"next_page_token": "page2"}, "")
        self.assertEqual(checker.osv_advisories({"commit": "a" * 40}, fetch), [{"id": "later"}])
        self.assertEqual(pages[1]["page_token"], "page2")
        with self.assertRaisesRegex(ValueError, "pagination"):
            checker.osv_advisories({}, lambda *args: ({"next_page_token": "same"}, ""))

    def testGitHubPaginationIncludesLaterMatchesAndRejectsOtherHosts(self):
        base = "https://api.github.com/repos/example/parser/security-advisories"
        def fetch(url):
            return ([self.upstream()], "") if "after=next" in url else ([], f'<{base}?after=next>; rel="next"')
        self.assertEqual(checker.repository_advisories("example/parser", fetch), [self.upstream()])
        with self.assertRaisesRegex(ValueError, "pagination"):
            checker.repository_advisories("example/parser", lambda *args: ([], '<https://other.example/>; rel="next"'))

    def testMalformedResponsesAreNotCleanResults(self):
        for response in [{"error": "bad query"}, {"vulns": {}}, {"vulns": [{}]}, {"vulns": ["invalid"]}]:
            def fetch(url, payload=None):
                return (response, "") if payload else ([], "")
            self.assertEqual(checker.exit_status(checker.scan(self.manifest, self.root, fetch)), 2)

    def testNetworkFailureHasBoundedRetriesAndRejectsUnknownHosts(self):
        with patch.object(checker, "urlopen", side_effect=URLError("offline")) as request, patch.object(checker.time, "sleep"):
            with self.assertRaisesRegex(ValueError, "could not be reached"):
                checker.request_json("https://api.osv.dev/v1/query", {"commit": "a" * 40})
            self.assertEqual(request.call_count, 3)
        with self.assertRaisesRegex(ValueError, "Unexpected"):
            checker.request_json("https://example.com")

    def testCanonicalAPIRequestsDoNotFollowRedirects(self):
        self.assertIsNone(checker.NoRedirect().redirect_request(None, None, 302, "Found", {}, "https://other.example"))

    def testManifestRejectsUnsupportedVersionsAndDuplicateDependencies(self):
        path = self.root / "manifest.json"
        for manifest in [[], {"schemaVersion": True}, {"schemaVersion": 1, "dependencies": [None]}, {"schemaVersion": 99}, {**self.manifest, "dependencies": [self.dependency, self.dependency]}]:
            path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                checker.load_manifest(path)


if __name__ == "__main__":
    unittest.main()
