import base64
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import package


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="Projects package tests ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "AltTabProjects.app"
        self.framework = self.app / "Contents/Frameworks/Sparkle.framework"
        self.version = self.framework / "Versions/A"
        self.version.mkdir(parents=True)
        (self.framework / "Versions/Current").symlink_to("A")
        for name in ("Sparkle", "Resources", "Autoupdate", "Updater.app"):
            (self.framework / name).symlink_to(f"Versions/Current/{name}")
        for name in ("Sparkle", "Autoupdate", "Updater.app/Contents/MacOS/Updater"):
            self.macho(self.version / name)
        self.macho(self.app / "Contents/MacOS/AltTabProjects")
        self.plist(self.version / "Resources/Info.plist", CFBundleIdentifier="org.sparkle-project.Sparkle")
        self.plist(self.version / "Updater.app/Contents/Info.plist",
                   CFBundleIdentifier="org.sparkle-project.Sparkle.Updater")
        status = self.version / "Updater.app/Contents/Resources/SUStatus.nib"
        status.parent.mkdir(parents=True)
        status.write_bytes(b"updater status window")
        for name in package.SPARKLE_RESOURCES:
            path = self.version / "Resources" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"Sparkle resource")
        self.plist(self.app / "Contents/Info.plist", CFBundleIdentifier="com.horner.alt-tab-projects")

    def macho(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(bytes.fromhex("cafebabe") + b"universal fixture")
        path.chmod(0o755)

    def plist(self, path, **values):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(plistlib.dumps(values))

    def test_missing_or_broken_helpers_stop_before_signing(self):
        for name in ("Autoupdate", "Updater.app/Contents/MacOS/Updater"):
            with self.subTest(name=name):
                path = self.version / name
                contents = path.read_bytes()
                path.unlink()
                with patch.object(package, "run") as run, self.assertRaisesRegex(RuntimeError, "Sparkle"):
                    package.sign_app(self.app, "-")
                run.assert_not_called()
                path.write_bytes(contents)
                path.chmod(0o755)

    def test_framework_root_links_are_required(self):
        for name in ("Resources", "Sparkle", "Autoupdate", "Updater.app"):
            with self.subTest(name=name):
                link = self.framework / name
                link.unlink()
                link.symlink_to(f"Versions/A/{name}")
                with self.assertRaisesRegex(RuntimeError, "framework link"):
                    package.verify_sparkle_layout(self.app)
                link.unlink()
                link.symlink_to(f"Versions/Current/{name}")

    def test_missing_resources_and_wrong_bundle_identifier_fail(self):
        resource = self.version / "Resources/SUUpdateAlert.nib"
        resource.unlink()
        with self.assertRaisesRegex(RuntimeError, "resource"):
            package.verify_sparkle_layout(self.app)
        resource.write_bytes(b"nib")
        self.plist(self.version / "Resources/Info.plist", CFBundleIdentifier="sparkle.Sparkle")
        with self.assertRaisesRegex(RuntimeError, "canonical bundle identifier"):
            package.verify_sparkle_layout(self.app)

    def test_missing_updater_status_window_is_rejected(self):
        (self.version / "Updater.app/Contents/Resources/SUStatus.nib").unlink()
        with self.assertRaisesRegex(RuntimeError, "Updater.app status window"):
            package.verify_sparkle_layout(self.app)

    def test_verifies_both_architectures_and_each_nested_signature(self):
        run = Mock()
        package.verify_sparkle_bundle(self.app, run)
        for path in package.macho_files(self.app):
            for architecture in ("arm64", "x86_64"):
                run.assert_any_call("lipo", path, "-verify_arch", architecture)
            run.assert_any_call("codesign", "--verify", "--strict", path)
        run.assert_any_call("codesign", "--verify", "--deep", "--strict", self.app)

    def test_nested_signature_failure_rejects_package(self):
        def run(*args):
            if args[0] == "codesign":
                raise subprocess.CalledProcessError(1, args)
        with self.assertRaises(subprocess.CalledProcessError):
            package.verify_sparkle_bundle(self.app, run)

    def test_verifies_extracted_final_archive_and_its_identity(self):
        extracted = self.root / "extracted"
        extracted.mkdir()
        shutil.copytree(self.app, extracted / self.app.name, symlinks=True)
        identity = f"Authority={package.DISTRIBUTION_IDENTITY}\nTeamIdentifier={package.DISTRIBUTION_TEAM_ID}\n"
        with patch.object(package.tempfile, "TemporaryDirectory") as temporary, \
                patch.object(package, "run", return_value=Mock(stderr=identity)) as run, \
                patch.object(package, "verify_sparkle_bundle") as verify:
            temporary.return_value.__enter__.return_value = str(extracted)
            info = package.verify_archive(self.root / "final.zip")
        run.assert_any_call("ditto", "-x", "-k", self.root / "final.zip", str(extracted))
        verify.assert_called_once_with(extracted / self.app.name)
        run.assert_any_call("xcrun", "stapler", "validate", extracted / self.app.name)
        self.assertEqual(info["CFBundleIdentifier"], "com.horner.alt-tab-projects")

    def test_sparkle_signs_exact_archive_with_separate_keychain_account(self):
        archive = self.root / "AltTabProjects.zip"
        archive.write_bytes(b"final stapled archive")
        public = base64.b64encode(bytes(range(32))).decode()
        signature = base64.b64encode(bytes(range(64))).decode()
        info = dict(SUPublicEDKey=public, LSMinimumSystemVersion="12.0")
        run = Mock(side_effect=[Mock(stdout=public + "\n"), Mock(stdout=signature + "\n"), Mock()])
        metadata = package.sparkle_metadata(archive, info, run)
        self.assertEqual(metadata, dict(signature=signature, length=archive.stat().st_size,
                                       minimum_system_version="12.0", public_key=public, channel="beta"))
        run.assert_any_call(package.SPARKLE_KEY_GENERATOR, "--account", "AltTabProjects Sparkle", "-p")
        run.assert_any_call(package.SPARKLE_SIGNER, "--account", "AltTabProjects Sparkle", "-p", archive)
        run.assert_any_call(package.SPARKLE_SIGNER, "--account", "AltTabProjects Sparkle", "--verify", archive, signature)
        self.assertNotIn("-s", [str(arg) for call in run.call_args_list for arg in call.args])

    def test_wrong_keychain_account_or_invalid_signature_is_rejected(self):
        archive = self.root / "AltTabProjects.zip"
        archive.write_bytes(b"zip")
        public = base64.b64encode(bytes(32)).decode()
        info = dict(SUPublicEDKey=public, LSMinimumSystemVersion="12.0")
        with self.assertRaisesRegex(RuntimeError, "Keychain account"):
            package.sparkle_metadata(archive, info, Mock(return_value=Mock(stdout="other key")))
        with self.assertRaisesRegex(RuntimeError, "signature"):
            package.sparkle_metadata(archive, info, Mock(side_effect=[public, "invalid signature"]))
        with self.assertRaisesRegex(RuntimeError, "public key"):
            package.sparkle_metadata(archive, dict(info, SUPublicEDKey="invalid"), Mock())

    def test_cask_declares_automatic_updates(self):
        self.assertIn("\n  auto_updates true\n", package.cask("1.0.6", "abc", "https://example.test/app.zip", "test"))

    @unittest.skipUnless(shutil.which("ditto") and shutil.which("rsync") and shutil.which("plutil"), "macOS copy tools required")
    def test_copy_phase_repairs_reembedded_framework_and_ignores_disabled_signing_identity(self):
        products = self.root / "products"
        resources = products / "Sparkle_Sparkle.bundle/Contents/Resources"
        shutil.copytree(self.version / "Resources", resources)
        framework = products / "App.app/Contents/Frameworks/Sparkle.framework"
        shutil.copytree(self.framework, framework, symlinks=True)
        helpers = self.root / "vendor/Sparkle/Helpers"
        helpers.mkdir(parents=True)
        shutil.copytree(self.version / "Updater.app", helpers / "Updater.app")
        shutil.copy2(self.version / "Autoupdate", helpers / "Autoupdate")
        commands = self.root / "commands"
        commands.mkdir()
        codesign = commands / "codesign"
        codesign.write_text('#!/bin/sh\n[ "$3" = "-" ]\n')
        codesign.chmod(0o755)
        env = dict(os.environ, SRCROOT=str(self.root), BUILT_PRODUCTS_DIR=str(products),
                   FRAMEWORKS_FOLDER_PATH="App.app/Contents/Frameworks", CODE_SIGNING_ALLOWED="NO",
                   CODE_SIGN_IDENTITY="Unavailable Identity", PATH=f"{commands}:{os.environ['PATH']}")
        script = package.ROOT / "scripts/copy_sparkle_helpers.sh"
        for _ in range(2):
            (framework / "Versions/A/Autoupdate").unlink()
            (framework / "Autoupdate").unlink()
            subprocess.run(["bash", str(script)], check=True, env=env, capture_output=True, text=True)
            package.verify_sparkle_layout(products / "App.app")


if __name__ == "__main__":
    unittest.main()
