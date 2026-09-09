#!/usr/bin/env python3
"""Package the compiled Projects app; public packages require notarization."""
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DISTRIBUTION_TEAM_ID = "X5873NL7XM"
MACH_MAGICS = {bytes.fromhex(value) for value in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}


def run(*args):
    return subprocess.run([str(arg) for arg in args], check=True, text=True, capture_output=True)


def is_macho(path):
    with path.open("rb") as handle:
        return handle.read(4) in MACH_MAGICS


def sign_app(app, identity):
    files = {path.resolve() for path in app.rglob("*") if path.is_file() and is_macho(path)}
    for path in sorted(files):
        run("lipo", path, "-verify_arch", "arm64", "x86_64")
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

  depends_on :macos

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
    run("lipo", source / "Contents/MacOS/AltTabProjects", "-verify_arch", "arm64", "x86_64")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    app = output / "AltTabProjects.app"
    run("ditto", source, app)
    sign_app(app, "-" if args.test_only else args.identity)
    signature = run("codesign", "-dv", "--verbose=4", app).stderr
    if not args.test_only and "Authority=Developer ID Application:" not in signature:
        raise SystemExit("The signed app must use Developer ID Application")
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
                "notarized": not args.test_only, "archive": zip_path.name, "sha256": checksum}
    (output / "build-info.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
    print(f"Package: {output}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.stdout + error.stderr)
