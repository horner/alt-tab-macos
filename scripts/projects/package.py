#!/usr/bin/env python3
"""Package the compiled Projects app; public packages require notarization."""
import argparse
import base64
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DISTRIBUTION_TEAM_ID = "X5873NL7XM"
DISTRIBUTION_IDENTITY = "Developer ID Application: Medical Informatics Engineering, Inc. (X5873NL7XM)"
SPARKLE_ACCOUNT = "AltTabProjects Sparkle"
SPARKLE_SIGNER = ROOT / "vendor/Sparkle/bin/sign_update"
SPARKLE_KEY_GENERATOR = ROOT / "vendor/Sparkle/bin/generate_keys"
SPARKLE_RESOURCES = ("SUStatus.nib", "SUUpdateAlert.nib", "SUUpdatePermissionPrompt.nib",
                     "ReleaseNotesColorStyle.css", "Base.lproj/Sparkle.strings")
MACH_MAGICS = {bytes.fromhex(value) for value in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}


def run(*args):
    return subprocess.run([str(arg) for arg in args], check=True, text=True, capture_output=True)


def is_macho(path):
    with path.open("rb") as handle:
        return handle.read(4) in MACH_MAGICS


def verify_architectures(path, runner=None):
    # Xcode 27's lipo rejects multiple architectures in one -verify_arch call.
    for architecture in ("arm64", "x86_64"):
        (runner or run)("lipo", path, "-verify_arch", architecture)


def macho_files(app):
    return {path.resolve() for path in app.rglob("*") if path.is_file() and is_macho(path)}


def verify_sparkle_layout(app):
    framework = app / "Contents/Frameworks/Sparkle.framework"
    links = {"Versions/Current": "A", **{name: f"Versions/Current/{name}" for name in
             ("Sparkle", "Resources", "Autoupdate", "Updater.app")}}
    for name, target in links.items():
        path = framework / name
        if not path.is_symlink() or path.readlink().as_posix() != target or not path.exists():
            raise RuntimeError(f"Missing or invalid Sparkle framework link: {path}")
    for name in ("Autoupdate", "Updater.app/Contents/MacOS/Updater", "Sparkle"):
        path = framework / "Versions/A" / name
        if not path.is_file() or not is_macho(path) or not path.stat().st_mode & 0o111:
            raise RuntimeError(f"Missing Sparkle executable: {path}")
    if not (framework / "Updater.app/Contents/Resources/SUStatus.nib").exists():
        raise RuntimeError("Missing Sparkle Updater.app status window resource")
    resources = framework / "Versions/A/Resources"
    for name in SPARKLE_RESOURCES:
        if not (resources / name).exists():
            raise RuntimeError(f"Missing Sparkle resource: {resources / name}")
    with (resources / "Info.plist").open("rb") as handle:
        if plistlib.load(handle).get("CFBundleIdentifier") != "org.sparkle-project.Sparkle":
            raise RuntimeError("Sparkle framework must retain its canonical bundle identifier")
    with (framework / "Updater.app/Contents/Info.plist").open("rb") as handle:
        if plistlib.load(handle).get("CFBundleIdentifier") != "org.sparkle-project.Sparkle.Updater":
            raise RuntimeError("Sparkle Updater.app has an unexpected bundle identifier")


def verify_sparkle_bundle(app, runner=None):
    invoke = runner or run
    verify_sparkle_layout(app)
    for path in sorted(macho_files(app)):
        verify_architectures(path, invoke)
        invoke("codesign", "--verify", "--strict", path)
    invoke("codesign", "--verify", "--deep", "--strict", app)


def verify_sparkle_signature(archive_path, signature, runner=None):
    (runner or run)(SPARKLE_SIGNER, "--account", SPARKLE_ACCOUNT, "--verify", archive_path, signature)


def sparkle_metadata(archive_path, info, runner=None):
    invoke = runner or run
    public_key = info.get("SUPublicEDKey", "")
    try:
        if len(base64.b64decode(public_key, validate=True)) != 32:
            raise ValueError()
    except (ValueError, TypeError):
        raise RuntimeError("The Projects app must contain a valid Sparkle Ed25519 public key") from None
    result = invoke(SPARKLE_KEY_GENERATOR, "--account", SPARKLE_ACCOUNT, "-p")
    signing_key = (result.stdout if hasattr(result, "stdout") else result).strip()
    if signing_key != public_key:
        raise RuntimeError("The Sparkle Keychain account does not match the app's public update key")
    result = invoke(SPARKLE_SIGNER, "--account", SPARKLE_ACCOUNT, "-p", archive_path)
    signature = (result.stdout if hasattr(result, "stdout") else result).strip()
    try:
        if len(base64.b64decode(signature, validate=True)) != 64:
            raise ValueError()
    except (ValueError, TypeError):
        raise RuntimeError("Sparkle did not return a valid Ed25519 signature") from None
    verify_sparkle_signature(archive_path, signature, invoke)
    return dict(signature=signature, length=archive_path.stat().st_size,
                minimum_system_version=info["LSMinimumSystemVersion"], public_key=public_key, channel="beta")


def verify_archive(archive_path, test_only=False):
    with tempfile.TemporaryDirectory(prefix="projects-package-") as directory:
        run("ditto", "-x", "-k", archive_path, directory)
        app = Path(directory) / "AltTabProjects.app"
        verify_sparkle_bundle(app)
        if not test_only:
            signature = run("codesign", "-dv", "--verbose=4", app).stderr.splitlines()
            if f"Authority={DISTRIBUTION_IDENTITY}" not in signature or f"TeamIdentifier={DISTRIBUTION_TEAM_ID}" not in signature:
                raise RuntimeError("The archived app must use the established Developer ID and team")
            run("xcrun", "stapler", "validate", app)
            run("spctl", "--assess", "--type", "execute", app)
        return plistlib.loads((app / "Contents/Info.plist").read_bytes())


def sign_app(app, identity):
    verify_sparkle_layout(app)
    files = macho_files(app)
    for path in sorted(files):
        verify_architectures(path)
    bundles = {path.resolve() for path in app.rglob("*")
               if path.is_dir() and path.suffix in (".app", ".framework", ".xpc")}
    timestamp = "--timestamp=none" if identity == "-" else "--timestamp"
    for path in sorted(files | bundles, key=lambda item: (-len(item.parts), str(item))):
        run("codesign", "--force", "--sign", identity, timestamp, "--options", "runtime",
            "--preserve-metadata=entitlements", path)
    run("codesign", "--force", "--sign", identity, timestamp, "--options", "runtime",
        "--entitlements", ROOT / "alt_tab_macos.entitlements", app)
    run("codesign", "--verify", "--deep", "--strict", app)


def archive(app, destination):
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, destination)


def cask(version, checksum, url, token):
    return f'''cask "{token}" do
  version "{version}"
  sha256 "{checksum}"

  url {json.dumps(url)}
  name "AltTabProjects"
  desc "Window and Desktop switcher with saved Projects"
  homepage "https://github.com/horner/alt-tab-macos"

  auto_updates true
  depends_on macos: :monterey

  app "AltTabProjects.app"
end
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", help="Developer ID Application signing identity or SHA-1")
    parser.add_argument("--notary-profile", help="Existing notarytool Keychain profile")
    parser.add_argument("--test-only", action="store_true", help="Ad-hoc local cask test; never publish")
    parser.add_argument("--output", type=Path, required=True, help="New output directory")
    args = parser.parse_args()
    if args.test_only and (args.identity or args.notary_profile):
        parser.error("--test-only cannot use distribution credentials")
    if not args.test_only and not (args.identity and args.notary_profile):
        parser.error("Distribution requires --identity and --notary-profile")
    source_commit = run("git", "-C", ROOT, "rev-parse", "HEAD").stdout.strip()
    uncommitted_changes = bool(run("git", "-C", ROOT, "status", "--porcelain").stdout)
    if not args.test_only and uncommitted_changes:
        parser.error("Commit the intended release source before creating a distribution package")
    source = ROOT / "DerivedData/Build/Products/Release/AltTabProjects.app"
    with (source / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        parser.error("Expected a three-component numeric app version")
    if info["CFBundleIdentifier"] != "com.horner.alt-tab-projects":
        parser.error("Unexpected bundle identity")
    verify_architectures(source / "Contents/MacOS/AltTabProjects")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    app = output / "AltTabProjects.app"
    run("ditto", source, app)
    sign_app(app, "-" if args.test_only else args.identity)
    signature = run("codesign", "-dv", "--verbose=4", app).stderr
    if not args.test_only and f"Authority={DISTRIBUTION_IDENTITY}" not in signature.splitlines():
        raise SystemExit("The signed app must use the established Developer ID Application identity")
    if not args.test_only and f"TeamIdentifier={DISTRIBUTION_TEAM_ID}" not in signature.splitlines():
        raise SystemExit("The signed app must use the established Medical Informatics Engineering team")
    archive_name = f"AltTabProjects-{version}-local-test.zip" if args.test_only else "AltTabProjects.zip"
    zip_path = output / archive_name
    archive(app, zip_path)
    if not args.test_only:
        print("Waiting for Apple notarization…", flush=True)
        result = run("xcrun", "notarytool", "submit", zip_path, "--keychain-profile",
                     args.notary_profile, "--wait", "--timeout", "15m", "--output-format", "json")
        notarization = json.loads(result.stdout)
        (output / "notarization.json").write_text(json.dumps(notarization, indent=2) + "\n")
        if notarization.get("status") != "Accepted":
            raise SystemExit("Notarization was not accepted; no cask generated")
        run("xcrun", "stapler", "staple", app)
        run("xcrun", "stapler", "validate", app)
        run("spctl", "--assess", "--type", "execute", app)
        zip_path.unlink()
        archive(app, zip_path)
    info = verify_archive(zip_path, args.test_only)
    sparkle = None if args.test_only else sparkle_metadata(zip_path, info)
    checksum = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    (output / "SHA256SUMS.txt").write_text(f"{checksum}  {zip_path.name}\n")
    release_url = f"https://github.com/horner/alt-tab-macos/releases/download/projects-v{version}/{zip_path.name}"
    (output / "Casks").mkdir()
    (output / "Casks/alttab-projects-local.rb").write_text(
        cask(version, checksum, "LOCAL_ARCHIVE_URL", "alttab-projects-local"))
    if not args.test_only:
        (output / "Casks/alttab-projects.rb").write_text(
            cask(version, checksum, release_url, "alttab-projects"))
    shutil.copy2(ROOT / "scripts/projects/install-local.sh", output / "install-local.sh")
    manifest = {"version": version, "bundle_identifier": info["CFBundleIdentifier"],
                "source_commit": source_commit, "uncommitted_changes": uncommitted_changes,
                "signing_team": None if args.test_only else DISTRIBUTION_TEAM_ID,
                "notarized": not args.test_only, "archive": zip_path.name, "sha256": checksum,
                "sparkle": sparkle}
    (output / "build-info.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
    print(f"Package: {output}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.stdout + error.stderr)
