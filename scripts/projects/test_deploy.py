import argparse
import copy
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import deploy


class DeployTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="Projects deploy tests ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "config").mkdir()
        (self.root / "config/projects.xcconfig").write_text(
            f"PRODUCT_NAME = AltTabProjects\nPRODUCT_BUNDLE_IDENTIFIER = {deploy.BUNDLE}\nTEAM_ID = {deploy.TEAM}\nCURRENT_PROJECT_VERSION = 0.2.0\n")
        notes = self.root / "release notes.md"
        notes.write_text("Projects beta improvements.\n")
        args = argparse.Namespace(notes=notes, dry_run=False, resume=False, identity=deploy.IDENTITY, notary_profile="test-profile")
        self.d = deploy.Deploy(args, self.root)
        self.head = "a" * 40
        self.d.git = Mock(side_effect=self.source_git)
        self.d.read_source()
        self.d.logs.mkdir(parents=True)
        self.d.output.mkdir(parents=True)

    def source_git(self, *args, **kwargs):
        if args[:2] == ("branch", "--show-current"):
            return deploy.BRANCH
        if args[:2] == ("remote", "get-url"):
            return deploy.REPO_URL
        if args == ("rev-parse", "HEAD"):
            return self.head
        return ""

    def package_fixture(self):
        (self.d.output / "AltTabProjects.zip").write_bytes(b"simulated notarized zip")
        self.d.sha = deploy.checksum(self.d.output / "AltTabProjects.zip")
        manifest = dict(version=self.d.version, source_commit=self.head, bundle_identifier=deploy.BUNDLE,
                        signing_team=deploy.TEAM, notarized=True, uncommitted_changes=False,
                        archive="AltTabProjects.zip", sha256=self.d.sha)
        (self.d.output / "build-info.json").write_text(json.dumps(manifest))
        (self.d.output / "SHA256SUMS.txt").write_text(f"{self.d.sha}  AltTabProjects.zip\n")
        (self.d.output / "notarization.json").write_text('{"status":"Accepted"}')
        self.d.cask_text = deploy.package.cask(self.d.version, self.d.sha, self.d.url, "alttab-projects")
        (self.d.output / "Casks").mkdir()
        (self.d.output / "Casks/alttab-projects.rb").write_text(self.d.cask_text)
        self.d.verify_archive = Mock()
        self.d.run = Mock(return_value="")
        return manifest

    def release_fixture(self, draft=True, names=deploy.ASSETS):
        self.package_fixture()
        self.events = []
        self.remote = dict(id=123, tag_name=self.d.tag, draft=draft, prerelease=True,
                           assets=[self.asset(name) for name in names])
        self.d.release = copy.deepcopy(self.remote)
        self.d.clean_source = Mock()
        self.d.tag_commit = Mock(return_value=self.head)
        self.d.find_release = lambda: copy.deepcopy(self.remote)
        self.d.run = self.release_command
        self.d.api = self.release_api

    def asset(self, name):
        return dict(name=name, digest=f"sha256:{deploy.checksum(self.d.output / name)}")

    def release_command(self, *args, **kwargs):
        self.events.append(args)
        if args[:3] == ("gh", "release", "create"):
            self.remote = dict(id=123, tag_name=self.d.tag, draft=True, prerelease=True, assets=[])
        if args[:3] == ("gh", "release", "upload"):
            paths = args[4:args.index("--repo")]
            self.remote["assets"].extend(self.asset(Path(path).name) for path in paths)
        if args[0] == "curl":
            Path(args[args.index("--output") + 1]).write_bytes((self.d.output / "AltTabProjects.zip").read_bytes())
        return ""

    def release_api(self, endpoint, *args):
        self.events.append(("publish", endpoint))
        self.remote["draft"] = False
        return copy.deepcopy(self.remote)

    def test_rejects_upstream_push_url(self):
        self.d.git.side_effect = lambda *args, **kwargs: "git@github.com:lwouis/alt-tab-macos.git" if "--push" in args else self.source_git(*args)
        with self.assertRaisesRegex(RuntimeError, "only horner"):
            self.d.read_source()

    def test_rejects_changed_bundle_identity(self):
        p = self.root / "config/projects.xcconfig"
        p.write_text(p.read_text().replace(deploy.BUNDLE, "com.example.other"))
        with self.assertRaisesRegex(RuntimeError, "unchanged"):
            self.d.read_source()

    def test_rejects_dirty_source_before_network_or_build(self):
        self.d.git.side_effect = lambda *args, **kwargs: " M src/file.swift" if args[0] == "status" else self.source_git(*args)
        self.d.api = Mock()
        with self.assertRaisesRegex(RuntimeError, "clean"):
            self.d.preflight()
        self.d.api.assert_not_called()

    def test_existing_version_requires_explicit_resume(self):
        self.d.find_release = Mock(return_value=dict(id=123))
        self.d.tag_commit = Mock(return_value=self.head)
        self.d.api = Mock(return_value=dict(full_name=deploy.REPO, private=False, permissions=dict(push=True), default_branch="master"))
        with patch("deploy.shutil.which", return_value="/tool"), self.assertRaisesRegex(RuntimeError, "--resume"):
            self.d.preflight()

    def test_rejects_reused_tag_pointing_to_other_source(self):
        self.d.args.resume = True
        self.d.find_release = Mock(return_value=None)
        self.d.tag_commit = Mock(return_value="b" * 40)
        self.d.api = Mock(return_value=dict(full_name=deploy.REPO, private=False, permissions=dict(push=True), default_branch="master"))
        with patch("deploy.shutil.which", return_value="/tool"), self.assertRaisesRegex(RuntimeError, "different source"):
            self.d.preflight()

    def test_resume_refuses_rebuilding_an_existing_release_without_original_package(self):
        self.d.args.resume = True
        self.d.find_release = Mock(return_value=dict(id=123, prerelease=True))
        self.d.tag_commit = Mock(return_value=self.head)
        self.d.api = Mock(return_value=dict(full_name=deploy.REPO, private=False, permissions=dict(push=True), default_branch="master"))
        with patch("deploy.shutil.which", return_value="/tool"), self.assertRaisesRegex(RuntimeError, "original completed"):
            self.d.preflight()

    def test_remote_annotated_tag_uses_peeled_commit(self):
        self.d.git = Mock(return_value=f"{'b' * 40}\trefs/tags/{self.d.tag}\n{self.head}\trefs/tags/{self.d.tag}^{{}}")
        self.assertEqual(self.d.tag_commit(remote=True), self.head)

    def test_package_verifies_metadata_archive_and_cask(self):
        self.package_fixture()
        self.d.validate_package()
        self.d.verify_archive.assert_called_once_with(self.d.output / "AltTabProjects.zip")

    def test_modified_zip_is_rejected(self):
        self.package_fixture()
        (self.d.output / "AltTabProjects.zip").write_bytes(b"replacement")
        with self.assertRaisesRegex(RuntimeError, "checksum mismatch"):
            self.d.validate_package()
        self.d.verify_archive.assert_not_called()

    def test_foreign_or_dirty_package_is_rejected(self):
        manifest = self.package_fixture()
        for key, value in [("source_commit", "b" * 40), ("signing_team", "OTHER"), ("notarized", False), ("uncommitted_changes", True)]:
            changed = dict(manifest, **{key: value})
            (self.d.output / "build-info.json").write_text(json.dumps(changed))
            with self.subTest(key=key), self.assertRaisesRegex(RuntimeError, "metadata"):
                self.d.validate_package()

    def test_resume_reuses_package_without_rebuilding_or_resigning(self):
        self.package_fixture()
        self.d.validate_package = Mock()
        self.d.prepare_package()
        calls = self.d.run.call_args_list
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0].args[1:3], ("-m", "unittest"))
        self.assertEqual(calls[1].args[:2], ("xcodebuild", "test"))
        self.d.validate_package.assert_called_once()

    def test_publish_orders_draft_upload_verification_and_public_download(self):
        self.release_fixture(names=[])
        self.d.release = None
        self.d.publish_release()
        self.assertEqual([event[:3] for event in self.events[:2]], [("gh", "release", "create"), ("gh", "release", "upload")])
        self.assertEqual(self.events[2][0], "publish")
        self.assertEqual(self.events[3][0], "curl")
        self.assertEqual(self.events[3][-1], self.d.url)
        self.assertIn(("push", "--atomic", "origin", f"HEAD:refs/heads/{deploy.BRANCH}", f"refs/tags/{self.d.tag}:refs/tags/{self.d.tag}"), [call.args for call in self.d.git.call_args_list])

    def test_partial_draft_uploads_only_missing_assets(self):
        self.release_fixture(names=["AltTabProjects.zip"])
        self.d.publish_release()
        upload = next(event for event in self.events if event[:3] == ("gh", "release", "upload"))
        self.assertEqual([Path(path).name for path in upload[4:upload.index("--repo")]], ["SHA256SUMS.txt", "build-info.json"])
        self.assertNotIn("--clobber", upload)

    def test_wrong_existing_asset_prevents_publication(self):
        self.release_fixture()
        self.d.release["assets"][0]["digest"] = "sha256:wrong"
        with self.assertRaisesRegex(RuntimeError, "not be overwritten"):
            self.d.publish_release()
        self.assertEqual(self.events, [])

    def test_wrong_partial_draft_is_rejected_before_uploading_more_assets(self):
        self.release_fixture(names=["AltTabProjects.zip"])
        self.d.release["assets"][0]["digest"] = "sha256:wrong"
        with self.assertRaisesRegex(RuntimeError, "not be overwritten"):
            self.d.publish_release()
        self.assertEqual(self.events, [])

    def test_github_asset_without_digest_is_downloaded_for_verification(self):
        self.release_fixture()
        self.d.release["assets"][0]["digest"] = None
        def download(*args, **kwargs):
            name = args[args.index("--pattern") + 1]
            target = Path(args[args.index("--dir") + 1]) / name
            target.write_bytes((self.d.output / name).read_bytes())
        self.d.run = Mock(side_effect=download)
        self.d.verify_assets()
        self.assertEqual(self.d.run.call_args.args[:3], ("gh", "release", "download"))

    def test_public_release_resume_never_edits_or_uploads_assets(self):
        self.release_fixture(draft=False)
        self.d.publish_release()
        self.assertEqual([event[0] for event in self.events], ["curl"])

    def test_resume_fetches_existing_tag_object_instead_of_recreating_it(self):
        self.release_fixture(draft=False)
        self.d.tag_commit.side_effect = [None, self.head]
        self.d.publish_release()
        calls = [call.args for call in self.d.git.call_args_list]
        self.assertIn(("fetch", "--no-tags", "origin", f"refs/tags/{self.d.tag}:refs/tags/{self.d.tag}"), calls)
        self.assertFalse(any(call[0] == "tag" for call in calls))

    def test_published_release_with_missing_assets_is_not_modified(self):
        self.release_fixture(draft=False, names=["AltTabProjects.zip"])
        with self.assertRaisesRegex(RuntimeError, "will not be modified"):
            self.d.publish_release()
        self.assertEqual(self.events, [])

    def test_brew_environment_disables_unrelated_cleanup(self):
        for key in ["HOMEBREW_NO_AUTO_UPDATE", "HOMEBREW_NO_AUTOREMOVE", "HOMEBREW_NO_INSTALL_CLEANUP"]:
            self.assertEqual(self.d.env[key], "1")

    def test_pipeline_stops_before_publication_when_tests_or_packaging_fail(self):
        self.d.preflight = Mock()
        self.d.prepare_package = Mock(side_effect=RuntimeError("tests failed"))
        self.d.publish_release = Mock()
        self.d.update_cask = Mock()
        self.d.verify_homebrew = Mock()
        self.d.prepare_package.__name__ = "prepare_package"
        with self.assertRaisesRegex(RuntimeError, "tests failed"):
            self.d.execute()
        self.d.publish_release.assert_not_called()
        self.d.update_cask.assert_not_called()
        self.d.verify_homebrew.assert_not_called()

    def test_second_deployment_is_blocked_by_os_lock(self):
        self.d.preflight = Mock()
        with (self.root / "build/projects-deploy.lock").open("w") as lock:
            deploy.fcntl.flock(lock, deploy.fcntl.LOCK_EX | deploy.fcntl.LOCK_NB)
            with self.assertRaisesRegex(RuntimeError, "Another Projects deployment"):
                self.d.execute()
        self.d.preflight.assert_not_called()


class GitIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="Projects release checkout ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "source with spaces"
        self.root.mkdir()
        self.origin = self.base / "remote.git"
        self.git("init", "--bare", self.origin, cwd=self.base)
        self.git("init", "-b", "master")
        self.git("config", "user.name", "Deployment Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("remote", "add", "origin", self.origin)
        (self.root / "Casks").mkdir()
        (self.root / "Casks/alttab-projects.rb").write_text('cask "alttab-projects" do\n  version "0.1.0"\nend\n')
        (self.root / "README.md").write_text("Keep this text.\nhttps://github.com/horner/alt-tab-macos/releases/tag/projects-v0.1.0\nHistory: https://github.com/horner/alt-tab-macos/releases/tag/projects-v0.0.1\n")
        (self.root / ".github/workflows").mkdir(parents=True)
        (self.root / ".github/workflows/ci_cd.yml").write_text("jobs:\n  build:\n    if: github.repository == 'lwouis/alt-tab-macos'\n    runs-on: macos-15\n")
        (self.root / ".gitignore").write_text("/build/\n")
        self.git("add", ".")
        self.git("commit", "-m", "test: seed repository")
        self.git("push", "-u", "origin", "master")
        self.git("switch", "-c", deploy.BRANCH)
        self.args = argparse.Namespace(notes=self.root / "notes.md", dry_run=False, resume=False, identity=deploy.IDENTITY, notary_profile="test-profile")
        self.d = deploy.Deploy(self.args, self.root)
        self.d.version = "0.2.0"
        self.d.tag = "projects-v0.2.0"
        self.d.default_branch = "master"
        self.d.logs = self.root / "build/deploy-0.2.0"
        self.d.logs.mkdir(parents=True)
        self.d.cask_text = deploy.package.cask("0.2.0", "a" * 64, "https://github.com/horner/alt-tab-macos/releases/download/projects-v0.2.0/AltTabProjects.zip", "alttab-projects")

    def git(self, *args, cwd=None):
        return subprocess.check_output(["git", *map(str, args)], cwd=cwd or self.root, text=True, stderr=subprocess.PIPE).strip()

    def test_cask_push_changes_only_cask_and_release_link_and_preserves_source(self):
        (self.root / "personal work.txt").write_text("Uncommitted work stays here.")
        before = self.git("rev-parse", "HEAD")
        self.d.update_cask()
        self.assertEqual(self.git("rev-parse", "HEAD"), before)
        self.assertEqual(self.git("branch", "--show-current"), deploy.BRANCH)
        self.assertEqual((self.root / "personal work.txt").read_text(), "Uncommitted work stays here.")
        remote_cask = self.git("--git-dir", self.origin, "show", "master:Casks/alttab-projects.rb")
        self.assertEqual(remote_cask, self.d.cask_text.strip())
        self.assertEqual(set(self.git("--git-dir", self.origin, "diff", "--name-only", "master^", "master").splitlines()), {"Casks/alttab-projects.rb", "README.md"})
        self.assertIn("Keep this text.", self.git("--git-dir", self.origin, "show", "master:README.md"))
        self.assertIn("History: https://github.com/horner/alt-tab-macos/releases/tag/projects-v0.0.1", self.git("--git-dir", self.origin, "show", "master:README.md"))
        first_push = self.git("--git-dir", self.origin, "rev-parse", "master")
        self.d.update_cask()
        self.assertEqual(self.git("--git-dir", self.origin, "rev-parse", "master"), first_push)

    def test_cask_downgrade_is_blocked(self):
        self.d.version = "0.0.9"
        with self.assertRaisesRegex(RuntimeError, "newer release"):
            self.d.update_cask()

    def test_missing_ci_guard_is_blocked(self):
        self.git("switch", "master")
        (self.root / ".github/workflows/ci_cd.yml").write_text("jobs:\n  build:\n    runs-on: macos-15\n")
        self.git("add", ".github/workflows/ci_cd.yml")
        self.git("commit", "-m", "test: remove guard")
        self.git("push", "origin", "master")
        self.git("switch", deploy.BRANCH)
        with self.assertRaisesRegex(RuntimeError, "CI publishing guard"):
            self.d.update_cask()

    def test_failed_cask_push_can_be_retried_without_changing_source(self):
        original = self.d.git
        def fail_push(*args, **kwargs):
            if args[0] == "push":
                raise RuntimeError("simulated non-fast-forward rejection")
            return original(*args, **kwargs)
        self.d.git = fail_push
        with self.assertRaisesRegex(RuntimeError, "simulated"):
            self.d.update_cask()
        self.assertEqual(self.git("branch", "--show-current"), deploy.BRANCH)
        self.d.git = original
        self.d.update_cask()
        self.assertEqual(self.git("--git-dir", self.origin, "show", "master:Casks/alttab-projects.rb"), self.d.cask_text.strip())

    def test_shell_dry_run_with_spaces_performs_no_build_network_or_writes(self):
        for name in ["deploy.sh", "scripts/projects/deploy.py", "scripts/projects/package.py"]:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(deploy.ROOT / name, target)
        (self.root / "config").mkdir()
        (self.root / "config/projects.xcconfig").write_text(
            f"PRODUCT_NAME = AltTabProjects\nPRODUCT_BUNDLE_IDENTIFIER = {deploy.BUNDLE}\nTEAM_ID = {deploy.TEAM}\nCURRENT_PROJECT_VERSION = 0.2.0\n")
        self.args.notes.write_text("Release notes.\n")
        self.git("remote", "set-url", "origin", deploy.REPO_URL)
        snapshot = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        output = subprocess.check_output([str(self.root / "deploy.sh"), "--notes", str(self.args.notes), "--dry-run"], cwd=self.base, text=True)
        self.assertIn("Preview only: projects-v0.2.0", output)
        self.assertEqual(snapshot, {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()})


if __name__ == "__main__":
    unittest.main()
