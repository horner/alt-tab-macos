#!/usr/bin/env python3
"""Check pinned dependency sources against OSV and published upstream advisories."""
import argparse
from contextlib import contextmanager
import hashlib
import html
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "vendor/security/dependencies.json"


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, new_url):
        return None


urlopen = build_opener(NoRedirect()).open


def source_hash(directory):
    digest = hashlib.sha256()
    files = sorted(p for p in directory.rglob("*") if p.is_file() and p.name != ".DS_Store")
    if not files:
        raise ValueError(f"No source files in {directory}")
    for path in files:
        if path.is_symlink():
            raise ValueError(f"Unexpected source symlink: {path}")
        digest.update(path.relative_to(directory).as_posix().encode() + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def local_path(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError("Dependency paths must stay inside the repository")
    return path


def load_manifest(path):
    data = json.loads(path.read_text())
    if not isinstance(data, dict) or type(data.get("schemaVersion")) is not int or data["schemaVersion"] != 1:
        raise ValueError("Expected a version 1 manifest")
    dependencies = data.get("dependencies")
    if not isinstance(dependencies, list) or not dependencies:
        raise ValueError("Expected a nonempty dependencies list")
    required = ["name", "repository", "source_path", "source_sha256"]
    if any(not isinstance(d, dict) or any(not isinstance(d.get(k), str) or not d[k] for k in required) for d in dependencies):
        raise ValueError("Each dependency needs a name, repository, source path and fingerprint")
    reviews = data.get("reviewed_repository_advisories", [])
    if not isinstance(reviews, list) or any(not isinstance(r, dict) for r in reviews):
        raise ValueError("Expected a reviewed repository advisories list")
    names = [d["name"] for d in data["dependencies"]]
    if len(names) != len(set(names)):
        raise ValueError("Dependency names must be unique")
    return data


def resolved_package(package, root):
    data = json.loads(local_path(root, package["resolved_file"]).read_text())
    if type(data.get("version")) is not int or data["version"] not in {2, 3}:
        raise ValueError("Unsupported Package.resolved format")
    pins = [p for p in data["pins"] if p.get("identity") == package["identity"]]
    if len(pins) != 1:
        raise ValueError("Expected exactly one resolved package pin")
    pin = pins[0]
    url = "https://github.com/" + package["repository"] + ".git"
    if pin.get("kind") != "remoteSourceControl" or pin.get("location") != url:
        raise ValueError("Resolved package repository differs from the inventory")
    state = pin["state"]
    if not re.fullmatch(r"[a-f0-9]{40}", state.get("revision", "")) or not re.fullmatch(r"\d+\.\d+\.\d+", state.get("version", "")):
        raise ValueError("A resolved release version and full commit are required")
    project = local_path(root, package["project_file"]).read_text()
    requirement = re.escape('repositoryURL = "' + url + '";') + r"\s*requirement = \{\s*kind = exactVersion;\s*version = " + re.escape(state["version"]) + r";\s*\};"
    if not re.search(requirement, project):
        raise ValueError("Project requirement differs from the resolved exact version")
    return {**state, "repository": package["repository"], "url": url}


@contextmanager
def package_checkouts(manifest, root):
    with tempfile.TemporaryDirectory(prefix="alt-tab-advisories-") as temporary:
        packages = {}
        for index, package in enumerate(manifest.get("swift_packages", [])):
            identity = package["identity"]
            if identity in packages:
                raise ValueError("Duplicate Swift package identity")
            pin = resolved_package(package, root)
            directory = Path(temporary) / str(index)
            directory.mkdir()
            commands = [["init", "--quiet"], ["fetch", "--quiet", "--depth=1", pin["url"], pin["revision"]],
                        ["checkout", "--quiet", "--detach", "FETCH_HEAD"]]
            for command in commands:
                subprocess.run(["git", "-C", str(directory), *command], check=True, capture_output=True, timeout=60)
            revision = subprocess.run(["git", "-C", str(directory), "rev-parse", "HEAD"], check=True,
                                      capture_output=True, text=True, timeout=10).stdout.strip()
            if revision != pin["revision"]:
                raise ValueError("Downloaded package differs from the resolved commit")
            packages[identity] = {**pin, "directory": directory}
        yield packages


def dependency_source(dependency, root, packages):
    if identity := dependency.get("package"):
        root = packages[identity]["directory"]
    return local_path(root, dependency["source_path"])


def identify(dependency, root, packages=None):
    packages = packages or {}
    actual = source_hash(dependency_source(dependency, root, packages))
    if actual != dependency["source_sha256"]:
        raise ValueError("Source fingerprint changed; verify the upstream revision and update dependencies.json")
    version = None
    revision = dependency.get("commit")
    if identity := dependency.get("package"):
        package = packages[identity]
        if revision:
            if dependency.get("package_revision") != package["revision"]:
                raise ValueError("Bundled library provenance needs review for this package revision")
        else:
            if package["repository"] != dependency["repository"]:
                raise ValueError("Resolved package repository differs from the dependency")
            version, revision = package["version"], package["revision"]
    if "upstream_file" in dependency:
        values = dict(line.split("=", 1) for line in local_path(root, dependency["upstream_file"]).read_text().splitlines() if "=" in line)
        version, revision = values["VERSION"].split("@")
        if values["SOURCE"].removesuffix(".git") != "https://github.com/" + dependency["repository"]:
            raise ValueError("UPSTREAM repository differs from the advisory manifest")
    if not isinstance(revision, str) or not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ValueError("A full upstream commit is required")
    return version, revision


def request_json(url, payload=None):
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.netloc not in {"api.osv.dev", "api.github.com"}:
        raise ValueError("Unexpected advisory API URL")
    headers = {"Accept": "application/json", "User-Agent": "AltTab-vendor-advisories"}
    if parsed.netloc == "api.github.com":
        headers["X-GitHub-Api-Version"] = "2022-11-28"
        if token := os.environ.get("GH_TOKEN"):
            headers["Authorization"] = "Bearer " + token
    if payload is not None:
        headers["Content-Type"] = "application/json"
    request = Request(url, data=None if payload is None else json.dumps(payload).encode(), headers=headers)
    for attempt in range(3):
        try:
            with urlopen(request, timeout=20) as response:
                return json.load(response), response.headers.get("Link", "")
        except HTTPError as error:
            if error.code not in {429, 500, 502, 503, 504} or attempt == 2:
                raise ValueError(f"{parsed.netloc} returned HTTP {error.code}") from error
        except (URLError, TimeoutError) as error:
            if attempt == 2:
                raise ValueError(f"{parsed.netloc} could not be reached") from error
        time.sleep(2 ** attempt)


def osv_advisories(query, fetch=request_json):
    results = []
    seen = set()
    payload = dict(query)
    for _ in range(100):
        data, _ = fetch("https://api.osv.dev/v1/query", payload)
        if not isinstance(data, dict) or not isinstance(data.get("vulns", []), list) or data.get("error"):
            raise ValueError("Invalid OSV response")
        results.extend(v for v in data.get("vulns", []) if not v.get("withdrawn"))
        token = data.get("next_page_token")
        if not token:
            return results
        if not isinstance(token, str) or token in seen:
            raise ValueError("Invalid OSV pagination")
        seen.add(token)
        payload["page_token"] = token
    raise ValueError("OSV pagination limit exceeded")


def repository_advisories(repository, fetch=request_json):
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repository):
        raise ValueError("Invalid upstream repository")
    base = f"https://api.github.com/repos/{repository}/security-advisories"
    url = base + "?state=published&per_page=100"
    results = []
    seen = set()
    for _ in range(100):
        if url in seen or url.split("?", 1)[0] != base:
            raise ValueError("Invalid GitHub pagination")
        seen.add(url)
        data, links = fetch(url)
        if not isinstance(data, list):
            raise ValueError("Invalid GitHub advisory response")
        results.extend(v for v in data if not v.get("withdrawn_at"))
        next_page = re.search(r'<([^>]+)>;\s*rel="next"', links)
        if not next_page:
            return results
        url = next_page.group(1)
    raise ValueError("GitHub pagination limit exceeded")


def is_reviewed(advisory, name, revision, reviews):
    return any(r.get("dependency") == name and r.get("revision") == revision
               and r.get("id") == advisory["ghsa_id"] and r.get("modified") == advisory["updated_at"]
               and isinstance(r.get("reason"), str) and r["reason"].strip() for r in reviews)


def scan(manifest, root=ROOT, fetch=request_json, packages=None):
    report = {"checked": [], "findings": [], "errors": []}
    for dependency in manifest["dependencies"]:
        name = dependency["name"]
        try:
            version, revision = identify(dependency, root, packages)
        except (ValueError, KeyError, TypeError, OSError) as error:
            report["errors"].append(f"{name}: {error}")
            continue
        report["checked"].append({"name": name, "version": version, "revision": revision})
        queries = [{"commit": revision}]
        if version and dependency.get("ecosystem"):
            queries.append({"package": {"ecosystem": dependency["ecosystem"], "name": "https://github.com/" + dependency["repository"]}, "version": version})
        advisories = {}
        for query in queries:
            try:
                for item in osv_advisories(query, fetch):
                    advisories[item["id"]] = item
            except (ValueError, KeyError, TypeError, AttributeError, OSError) as error:
                report["errors"].append(f"{name} / OSV: {error}")
        for id_, advisory in sorted(advisories.items()):
            report["findings"].append({"dependency": name, "id": id_, "kind": "OSV revision/version match",
                                       "summary": advisory.get("summary", "Advisory matches the pinned source"),
                                       "url": "https://osv.dev/vulnerability/" + quote(id_, safe="")})
        try:
            for advisory in repository_advisories(dependency["repository"], fetch):
                if is_reviewed(advisory, name, revision, manifest.get("reviewed_repository_advisories", [])):
                    continue
                report["findings"].append({"dependency": name, "id": advisory["ghsa_id"], "kind": "Upstream advisory needs applicability review",
                                           "summary": advisory["summary"], "modified": advisory["updated_at"],
                                           "url": f"https://github.com/{dependency['repository']}/security/advisories/" + quote(advisory["ghsa_id"], safe="")})
        except (ValueError, KeyError, TypeError, AttributeError, OSError) as error:
            report["errors"].append(f"{name} / GitHub: {error}")
    return report


def exit_status(report):
    return 2 if report["errors"] else 1 if report["findings"] else 0


def markdown(report):
    def clean(value):
        return html.escape(" ".join(str(value).split())).replace("|", "&#124;")
    lines = ["## Dependency advisories", ""]
    for dependency in report["checked"]:
        lines.append(f"- Checked {clean(dependency['name'])}: {clean(dependency['version'] or '')} `{dependency['revision']}`")
    for finding in report["findings"]:
        lines += ["", f"- **{clean(finding['dependency'])}** — [{clean(finding['id'])}]({finding['url']}): {clean(finding['summary'])}", f"  {clean(finding['kind'])}."]
    for error in report["errors"]:
        lines += ["", "- **Check incomplete:** " + clean(error)]
    if exit_status(report) == 0:
        lines += ["", "No matching OSV advisories or unreviewed published upstream advisories were returned."]
    lines += ["", "Matches require applicability review. Advisory database coverage is not proof that a dependency is vulnerability-free.", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fingerprints", action="store_true", help="Print current source fingerprints for a reviewed dependency update")
    parser.add_argument("--json", type=Path, help="Write the complete machine-readable report")
    parser.add_argument("--summary", type=Path, help="Append the report to a GitHub Actions step summary")
    args = parser.parse_args()
    try:
        manifest = load_manifest(MANIFEST)
        with package_checkouts(manifest, ROOT) as packages:
            if args.fingerprints:
                print(json.dumps({d["name"]: source_hash(dependency_source(d, ROOT, packages)) for d in manifest["dependencies"]}, indent=2))
                return 0
            report = scan(manifest, packages=packages)
    except (ValueError, KeyError, TypeError, AttributeError, OSError, subprocess.SubprocessError) as error:
        report = {"checked": [], "findings": [], "errors": [str(error)]}
    summary = markdown(report)
    print(summary)
    if args.json:
        args.json.write_text(json.dumps(report, indent=2) + "\n")
    if args.summary:
        with args.summary.open("a") as output:
            output.write(summary)
    return exit_status(report)


if __name__ == "__main__":
    raise SystemExit(main())
