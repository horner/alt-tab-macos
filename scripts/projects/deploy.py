#!/usr/bin/env python3
"""Deploy the committed Projects release to the horner fork and its Homebrew cask."""
import argparse
import fcntl
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
import package

ROOT = Path(__file__).resolve().parents[2]
REPO = "horner/alt-tab-macos"
REPO_URL = f"https://github.com/{REPO}.git"
BRANCH = "projects-release"
TAP = "horner/projects"
CASK = f"{TAP}/alttab-projects"
IDENTITY = "Developer ID Application: Medical Informatics Engineering, Inc. (X5873NL7XM)"
TEAM = "X5873NL7XM"
BUNDLE = "com.horner.alt-tab-projects"
ASSETS = ("AltTabProjects.zip", "SHA256SUMS.txt", "build-info.json")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def checksum(path):
    with path.open("rb") as handle:
        digest = hashlib.sha256()
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fork_remote(url):
    return url in (REPO_URL, REPO_URL.removesuffix(".git"),
                   f"git@github.com:{REPO}.git", f"ssh://git@github.com/{REPO}.git")


class Deploy:
    def __init__(self, args, root=ROOT):
        self.args = args
        self.root = root
        self.env = dict(os.environ, GH_HOST="github.com", HOMEBREW_NO_AUTO_UPDATE="1",
                        HOMEBREW_NO_AUTOREMOVE="1", HOMEBREW_NO_INSTALL_CLEANUP="1",
                        PYTHONDONTWRITEBYTECODE="1")
        self.env.pop("HOMEBREW_CASK_OPTS", None)

    def run(self, *args, cwd=None, log=None, check=True):
        command = [str(arg) for arg in args]
        if log:
            print(f"Running {command[0]} {command[1]} — log: {log}", flush=True)
            with log.open("w") as handle:
                result = subprocess.run(command, cwd=cwd or self.root, env=self.env,
                                        text=True, stdout=handle, stderr=subprocess.STDOUT)
            require(result.returncode == 0, f"Command failed; inspect {log}")
            return ""
        result = subprocess.run(command, cwd=cwd or self.root, env=self.env, text=True, capture_output=True)
        if check:
            require(result.returncode == 0, f"{command[0]} {command[1]} failed:\n{result.stdout}{result.stderr}")
            return result.stdout.strip()
        return result

    def git(self, *args, cwd=None):
        return self.run("git", *args, cwd=cwd)

    def api(self, endpoint, *args):
        return json.loads(self.run("gh", "api", endpoint, *args))

    def clean_source(self):
        require(self.git("rev-parse", "HEAD") == self.commit, "Source HEAD changed during deployment.")
        require(not self.git("status", "--porcelain"), "Commit intended changes and leave the release worktree clean.")

    def read_source(self):
        config = (self.root / "config/projects.xcconfig").read_text()
        settings = dict(re.findall(r"^(\w+)\s*=\s*(.*?)\s*$", config, re.MULTILINE))
        self.version = settings.get("CURRENT_PROJECT_VERSION", "")
        require(re.fullmatch(r"\d+\.\d+\.\d+", self.version), "Set a numeric X.Y.Z release version in config/projects.xcconfig.")
        require(settings.get("PRODUCT_BUNDLE_IDENTIFIER") == BUNDLE and settings.get("TEAM_ID") == TEAM
                and settings.get("PRODUCT_NAME") == "AltTabProjects", "The established app name, bundle ID and signing team must remain unchanged.")
        require(self.git("branch", "--show-current") == BRANCH, f"Deploy from the {BRANCH} worktree.")
        for direction in ([], ["--push"]):
            urls = self.git("remote", "get-url", *direction, "--all", "origin").splitlines()
            require(urls and all(fork_remote(url) for url in urls), f"origin must fetch and push only {REPO}.")
        self.commit = self.git("rev-parse", "HEAD")
        self.tag = f"projects-v{self.version}"
        self.url = f"https://github.com/{REPO}/releases/download/{self.tag}/AltTabProjects.zip"
        self.output = self.root / "build" / f"release-{self.version}"
        self.logs = self.root / "build" / f"deploy-{self.version}"
        self.notes = self.args.notes.resolve()
        require(self.notes.is_file() and self.notes.read_text().strip(), "Provide a nonempty release-notes file with --notes.")
        require("#" not in str(self.output), "GitHub interprets # in asset paths as a label; use a checkout path without #.")

    def find_release(self):
        pages = self.api(f"repos/{REPO}/releases?per_page=100", "--paginate", "--slurp")
        matches = [release for page in pages for release in page if release["tag_name"] == self.tag]
        require(len(matches) <= 1, f"Multiple releases found for {self.tag}.")
        return matches[0] if matches else None

    def tag_commit(self, remote=False):
        if remote:
            lines = self.git("ls-remote", "--tags", "origin", f"refs/tags/{self.tag}", f"refs/tags/{self.tag}^{{}}")
            refs = dict(line.split()[::-1] for line in lines.splitlines())
            return refs.get(f"refs/tags/{self.tag}^{{}}", refs.get(f"refs/tags/{self.tag}"))
        result = self.run("git", "rev-parse", "--verify", f"refs/tags/{self.tag}^{{commit}}", check=False)
        return result.stdout.strip() if result.returncode == 0 else None

    def preflight(self):
        self.clean_source()
        for tool in ("git", "gh", "xcodebuild", "xcrun", "security", "codesign", "lipo", "spctl", "ditto", "ruby", "brew", "curl"):
            require(shutil.which(tool), f"Required command is missing: {tool}")
        repository = self.api(f"repos/{REPO}")
        require(repository["full_name"] == REPO and not repository["private"]
                and repository.get("permissions", {}).get("push"), f"GitHub authentication needs push access to public {REPO}.")
        self.default_branch = repository["default_branch"]
        require(self.default_branch != BRANCH, "The Homebrew default branch must be separate from release source.")
        self.release = self.find_release()
        tags = [self.tag_commit(), self.tag_commit(remote=True)]
        require(all(value in (None, self.commit) for value in tags), f"{self.tag} already points to different source. Use a new version.")
        if self.release or any(tags) or self.output.exists():
            require(self.args.resume, "This version already has a tag, release or local package. Use a new version, or --resume for this exact source.")
        if self.release:
            require(tags[1] == self.commit, "The existing release must have a remote tag matching this commit.")
            require(self.release["prerelease"], "Refusing to change the status of an existing stable release.")
            require((self.output / "build-info.json").is_file(), "Resume requires the original completed local package; published assets are never rebuilt.")
        self.git("fetch", "--no-tags", "origin", f"refs/heads/{self.default_branch}:refs/remotes/origin/{self.default_branch}",
                 f"refs/heads/{BRANCH}:refs/remotes/origin/{BRANCH}")
        self.git("merge-base", "--is-ancestor", f"origin/{BRANCH}", self.commit)
        self.check_workflow(f"origin/{self.default_branch}")
        self.check_cask_version(f"origin/{self.default_branch}")
        identities = self.run("security", "find-identity", "-v", "-p", "codesigning")
        require(self.args.identity in identities, "The requested Developer ID identity and private key are not available in Keychain.")
        self.run("xcrun", "notarytool", "history", "--keychain-profile", self.args.notary_profile, "--output-format", "json")

    def check_workflow(self, ref):
        workflow = self.git("show", f"{ref}:.github/workflows/ci_cd.yml")
        require(re.search(r"(?m)^  build:\n    if: github\.repository == 'lwouis/alt-tab-macos'\s*$", workflow),
                "The default branch must retain the upstream-only CI publishing guard.")

    def check_cask_version(self, ref):
        cask = self.git("show", f"{ref}:Casks/alttab-projects.rb")
        version = re.search(r'^  version "(\d+\.\d+\.\d+)"$', cask, re.MULTILINE)
        require(version, "The default-branch cask has an unexpected version format.")
        require(tuple(map(int, version[1].split("."))) <= tuple(map(int, self.version.split("."))),
                "The cask already has a newer release; refusing to downgrade it.")

    def validate_app(self, app):
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        require(info["CFBundleIdentifier"] == BUNDLE and info["CFBundleShortVersionString"] == self.version,
                "Downloaded app identity or version differs from the release.")
        self.run("codesign", "--verify", "--deep", "--strict", app)
        signature = self.run("codesign", "-dv", "--verbose=4", app, check=False)
        require(signature.returncode == 0 and "Authority=Developer ID Application:" in signature.stderr
                and f"TeamIdentifier={TEAM}" in signature.stderr.splitlines(), "The app has an unexpected signing identity.")
        self.run("lipo", app / "Contents/MacOS/AltTabProjects", "-verify_arch", "arm64", "x86_64")
        self.run("xcrun", "stapler", "validate", app)
        self.run("spctl", "--assess", "--type", "execute", app)

    def validate_package(self):
        manifest = json.loads((self.output / "build-info.json").read_text())
        expected = dict(version=self.version, source_commit=self.commit, bundle_identifier=BUNDLE,
                        signing_team=TEAM, notarized=True, uncommitted_changes=False, archive="AltTabProjects.zip")
        require(all(manifest.get(key) == value for key, value in expected.items()), "Package metadata does not match this clean, notarized release.")
        self.sha = checksum(self.output / "AltTabProjects.zip")
        require(manifest["sha256"] == self.sha, "Package ZIP checksum mismatch.")
        require((self.output / "SHA256SUMS.txt").read_text() == f"{self.sha}  AltTabProjects.zip\n", "Checksum manifest mismatch.")
        self.cask_text = package.cask(self.version, self.sha, self.url, "alttab-projects")
        require((self.output / "Casks/alttab-projects.rb").read_text() == self.cask_text, "Generated cask differs from the verified package.")
        require(json.loads((self.output / "notarization.json").read_text()).get("status") == "Accepted", "Apple has not accepted this package.")
        self.verify_archive(self.output / "AltTabProjects.zip")
        self.run("ruby", "-c", self.output / "Casks/alttab-projects.rb")

    def verify_archive(self, archive):
        require(checksum(archive) == self.sha, "Downloaded ZIP differs from the notarized package.")
        with tempfile.TemporaryDirectory(prefix="verify-", dir=self.logs) as directory:
            self.run("ditto", "-x", "-k", archive, directory)
            self.validate_app(Path(directory) / "AltTabProjects.app")

    def prepare_package(self):
        self.run(sys.executable, "-m", "unittest", "discover", "-s", "scripts/projects", "-p", "test_deploy.py",
                 log=self.logs / "tooling-tests.log")
        self.run("xcodebuild", "test", "-project", "alt-tab-macos.xcodeproj", "-scheme", "Test", "-configuration", "Release",
                 "-derivedDataPath", self.root / "build/projects-tests", log=self.logs / "tests.log")
        if not (self.output / "build-info.json").exists():
            if self.output.exists():
                raise RuntimeError(f"Incomplete package at {self.output}; preserve it under a different name, then retry with --resume.")
            self.run("bash", self.root / "scripts/projects/build.sh", log=self.logs / "build.log")
            self.clean_source()
            self.run(sys.executable, self.root / "scripts/projects/package.py", "--identity", self.args.identity,
                     "--notary-profile", self.args.notary_profile, "--output", self.output, log=self.logs / "package.log")
        self.clean_source()
        self.validate_package()

    def verify_assets(self, allow_missing=False):
        assets = {asset["name"]: asset for asset in self.release["assets"]}
        require(set(assets) <= set(ASSETS) and (allow_missing or set(assets) == set(ASSETS)),
                "Release asset set is incomplete or contains unexpected files.")
        for name in assets:
            expected = checksum(self.output / name)
            digest = assets[name].get("digest")
            if digest:
                require(digest == f"sha256:{expected}", f"GitHub asset {name} differs; it will not be overwritten.")
            else:
                with tempfile.TemporaryDirectory(dir=self.logs) as directory:
                    self.run("gh", "release", "download", self.tag, "--repo", REPO, "--pattern", name, "--dir", directory)
                    require(checksum(Path(directory) / name) == expected, f"GitHub asset {name} differs; it will not be overwritten.")

    def publish_release(self):
        self.clean_source()
        if self.tag_commit() is None:
            remote_commit = self.tag_commit(remote=True)
            if remote_commit:
                require(remote_commit == self.commit, "The remote tag changed; refusing to replace it.")
                self.git("fetch", "--no-tags", "origin", f"refs/tags/{self.tag}:refs/tags/{self.tag}")
            else:
                self.git("tag", "-a", self.tag, self.commit, "-m", f"AltTabProjects {self.version} friends beta")
        self.git("push", "--atomic", "origin", f"HEAD:refs/heads/{BRANCH}", f"refs/tags/{self.tag}:refs/tags/{self.tag}")
        if not self.release:
            self.run("gh", "release", "create", self.tag, "--repo", REPO, "--verify-tag", "--draft", "--prerelease",
                     "--title", f"AltTabProjects {self.version} — Friends beta", "--notes-file", self.notes)
            self.release = self.find_release()
        require(self.release, "GitHub did not return the created release. Retry with --resume.")
        self.verify_assets(allow_missing=True)
        existing = {asset["name"] for asset in self.release["assets"]}
        missing = [name for name in ASSETS if name not in existing]
        if missing:
            require(self.release["draft"], "A published release is missing assets; it will not be modified.")
            self.run("gh", "release", "upload", self.tag, *[self.output / name for name in missing], "--repo", REPO)
            self.release = self.find_release()
        self.verify_assets()
        if self.release["draft"]:
            self.release = self.api(f"repos/{REPO}/releases/{self.release['id']}", "--method", "PATCH", "-F", "draft=false", "-F", "prerelease=true")
        require(not self.release["draft"], "The release is still a draft; the cask will not be changed.")
        with tempfile.TemporaryDirectory(dir=self.logs) as directory:
            archive = Path(directory) / "AltTabProjects.zip"
            self.run("curl", "--fail", "--silent", "--show-error", "--location", "--retry", "3", "--proto", "=https",
                     "--proto-redir", "=https", "--output", archive, self.url)
            self.verify_archive(archive)

    def update_cask(self):
        self.git("fetch", "--no-tags", "origin", f"refs/heads/{self.default_branch}:refs/remotes/origin/{self.default_branch}")
        self.check_workflow(f"origin/{self.default_branch}")
        self.check_cask_version(f"origin/{self.default_branch}")
        parent = Path(tempfile.mkdtemp(prefix="cask-", dir=self.logs))
        checkout = parent / "checkout"
        self.git("worktree", "add", "--detach", checkout, f"origin/{self.default_branch}")
        try:
            cask = checkout / "Casks/alttab-projects.rb"
            cask.parent.mkdir(exist_ok=True)
            cask.write_text(self.cask_text)
            readme = checkout / "README.md"
            text = readme.read_text()
            readme.write_text(re.sub(r"https://github\.com/horner/alt-tab-macos/releases/tag/projects-v\d+\.\d+\.\d+",
                                     f"https://github.com/{REPO}/releases/tag/{self.tag}", text, count=1))
            self.git("diff", "--check", cwd=checkout)
            self.git("add", "--", "Casks/alttab-projects.rb", "README.md", cwd=checkout)
            changed = self.git("diff", "--cached", "--name-only", cwd=checkout).splitlines()
            require(set(changed) <= {"Casks/alttab-projects.rb", "README.md"}, "Unexpected staged files in the cask worktree.")
            if changed:
                self.git("commit", "-m", f"chore: release AltTabProjects {self.version}", cwd=checkout)
                self.git("push", "origin", f"HEAD:refs/heads/{self.default_branch}", cwd=checkout)
        except BaseException:
            print(f"Cask checkout retained for inspection: {checkout}", file=sys.stderr)
            raise
        self.git("worktree", "remove", checkout)
        parent.rmdir()

    def verify_homebrew(self):
        if self.run("brew", "command", "trust", check=False).returncode == 0:
            self.run("brew", "trust", "--cask", CASK)
        self.run("brew", "tap", TAP, REPO_URL)
        tap = Path(self.run("brew", "--repository", TAP))
        require(fork_remote(self.git("remote", "get-url", "origin", cwd=tap)), "The installed Homebrew tap points to another repository.")
        require(not self.git("status", "--porcelain", cwd=tap), "The installed Homebrew tap has local changes; preserve them before retrying.")
        require(self.git("branch", "--show-current", cwd=tap) == self.default_branch, "The Homebrew tap is on a custom branch.")
        self.git("pull", "--ff-only", cwd=tap)
        require((tap / "Casks/alttab-projects.rb").read_text() == self.cask_text, "The public tap does not contain the expected cask.")
        self.run("brew", "style", "--cask", CASK, log=self.logs / "cask-style.log")
        self.run("brew", "fetch", "--cask", "--force", "--retry", CASK, log=self.logs / "brew-fetch.log")
        archive = Path(self.run("brew", "--cache", "--cask", CASK))
        self.verify_archive(archive)

    def execute(self):
        self.read_source()
        if self.args.dry_run:
            print(f"Preview only: {self.tag} from {self.commit}\nRepository: {REPO}\nNotes: {self.notes}\n"
                  f"Package: {self.output}\nSteps: preflight → tests → universal build → sign/notarize → draft/upload/verify/publish → cask commit → Homebrew fetch/Gatekeeper\n"
                  "No build, credentials check, network request, Git mutation or publication was performed.\n"
                  "Actual deployment requires clean committed source, a new version, and configured credentials; use --resume only for the same source/package.")
            return
        (self.root / "build").mkdir(exist_ok=True)
        with (self.root / "build/projects-deploy.lock").open("w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError("Another Projects deployment is running in this checkout.")
            self.preflight()
            self.logs.mkdir(parents=True, exist_ok=True)
            print(f"Deploying {self.tag} ({self.commit}) to {REPO}. Logs: {self.logs}", flush=True)
            for step in (self.prepare_package, self.publish_release, self.update_cask, self.verify_homebrew):
                print(step.__name__.replace("_", " ").capitalize(), flush=True)
                step()
            result = dict(version=self.version, source_commit=self.commit, sha256=self.sha,
                          release_url=f"https://github.com/{REPO}/releases/tag/{self.tag}",
                          notarized=True, public_download_verified=True, homebrew_download_verified=True)
            (self.logs / "deployment.json").write_text(json.dumps(result, indent=2) + "\n")
            print(f"Deployed: {result['release_url']}\nHomebrew ZIP verified. Installed apps and preferences were not changed.")


def main():
    parser = argparse.ArgumentParser(prog="deploy.sh", description=__doc__)
    parser.add_argument("--notes", type=Path, required=True, help="Nonempty release notes; prepare and review before deploying")
    parser.add_argument("--dry-run", action="store_true", help="Print the local plan only; no builds, network calls or writes")
    parser.add_argument("--resume", action="store_true", help="Continue the same commit/version using its original completed package")
    parser.add_argument("--identity", default=IDENTITY, help="Developer ID identity name or SHA-1; the established team is required")
    parser.add_argument("--notary-profile", default="alttab-projects", help="notarytool Keychain profile name")
    args = parser.parse_args()
    try:
        Deploy(args).execute()
    except KeyboardInterrupt:
        print("Deployment interrupted. Preserve the source and original package; use --resume to continue.", file=sys.stderr)
        return 130
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(f"Deployment stopped: {error}\nAfter resolving the problem, use --resume with the same source and package if publication already started.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
