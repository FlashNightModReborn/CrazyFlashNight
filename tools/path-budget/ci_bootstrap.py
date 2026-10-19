#!/usr/bin/env python3
"""Source for the ordinary workflow's inline bootstrap. Standard library only.

The ordinary PR workflow can itself be edited by a PR. This source selection
prevents accidental candidate-code execution; it is NOT a tamper-proof entry.
A reviewed main must already contain all three trusted executable files.
"""
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

FILES = ("path_budget.py", "git_gate.py", "github_gate.py")
MAX_BLOB = 2 * 1024 * 1024
OID = re.compile(r"[0-9a-f]{40}\Z")
REPO = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z")


class BootstrapError(ValueError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        raise BootstrapError("API redirect refused")


def oid(value):
    if not isinstance(value, str) or not OID.fullmatch(value):
        raise BootstrapError("Bootstrap needs a complete immutable GitHub SHA")
    return value


def get_api(repository, token=""):
    if not isinstance(repository, str) or not REPO.fullmatch(repository) or any(x in (".", "..") for x in repository.split("/")):
        raise BootstrapError("Invalid runner repository")
    opener = urllib.request.build_opener(NoRedirect())
    def get(endpoint, limit=6 * MAX_BLOB):
        headers = {"Accept": "application/vnd.github+json", "User-Agent": "CF7-path-budget-bootstrap",
                   "X-GitHub-Api-Version": "2022-11-28"}
        if token:
            headers["Authorization"] = "Bearer " + token
        request = urllib.request.Request("https://api.github.com/repos/" + repository + endpoint, headers=headers)
        with opener.open(request, timeout=60) as response:
            data = response.read(limit + 1)
        if len(data) > limit:
            raise BootstrapError("Bootstrap metadata/blob exceeds bound")
        value = json.loads(data.decode("utf-8"))
        if not isinstance(value, dict):
            raise BootstrapError("Bootstrap API response is not an object")
        return value
    return get


def select_executor(event, event_name, repository, get):
    if event.get("repository", {}).get("full_name", "").lower() != repository.lower():
        raise BootstrapError("Event repository mismatch")
    if event_name == "pull_request":
        base = event.get("pull_request", {}).get("base", {})
        if base.get("repo", {}).get("full_name", "").lower() != repository.lower():
            raise BootstrapError("PR base repository mismatch")
        if base.get("ref") == "main":
            return oid(base.get("sha"))
        # A contributor-owned target branch is not an executable trust anchor.
        # Freeze main once; the trusted driver checks base config against it.
        reference = get("/git/ref/heads/main")
        if reference.get("ref") != "refs/heads/main" or reference.get("object", {}).get("type") != "commit":
            raise BootstrapError("Cannot establish reviewed main executor")
        return oid(reference["object"].get("sha"))
    if event_name == "push" and event.get("ref") == "refs/heads/main" and not event.get("deleted"):
        before = oid(event.get("before"))
        if before == "0" * 40:
            raise BootstrapError("Bootstrap: no reviewed before commit")
        return before
    raise BootstrapError("Unsupported event for path-budget workflow")


def trusted_files(executor, get):
    commit = get("/git/commits/" + oid(executor))
    if commit.get("sha") != executor:
        raise BootstrapError("Executor commit identity mismatch")
    tree = oid(commit.get("tree", {}).get("sha"))
    # Resolve exact directories without recursive-tree truncation or code checkout.
    for directory in ("tools", "path-budget"):
        listing = get("/git/trees/" + tree)
        if listing.get("sha") != tree or listing.get("truncated") is not False:
            raise BootstrapError("Bootstrap tree listing incomplete")
        matches = [e for e in listing.get("tree", []) if e.get("path") == directory]
        if len(matches) != 1 or matches[0].get("type") != "tree" or matches[0].get("mode") != "040000":
            raise BootstrapError("Bootstrap pending: reviewed executor lacks tools/path-budget")
        tree = oid(matches[0].get("sha"))
    listing = get("/git/trees/" + tree)
    if listing.get("sha") != tree or listing.get("truncated") is not False:
        raise BootstrapError("Bootstrap checker directory incomplete")
    results = {}
    for filename in FILES:
        matches = [e for e in listing.get("tree", []) if e.get("path") == filename]
        if len(matches) != 1:
            raise BootstrapError("Bootstrap pending: missing reviewed " + filename)
        entry = matches[0]
        if entry.get("type") != "blob" or entry.get("mode") != "100644" or type(entry.get("size")) is not int or not 0 <= entry["size"] <= MAX_BLOB:
            raise BootstrapError("Untrusted mode/size for checker blob")
        expected = oid(entry.get("sha"))
        value = get("/git/blobs/" + expected)
        if value.get("sha") != expected or value.get("size") != entry["size"] or value.get("encoding") != "base64":
            raise BootstrapError("Checker blob identity mismatch")
        data = base64.b64decode("".join(value["content"].split()), validate=True)
        actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        if len(data) != entry["size"] or actual != expected:
            raise BootstrapError("Checker blob hash mismatch")
        results[filename] = data
    return results


def main():
    try:
        repository = os.environ["GITHUB_REPOSITORY"]
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
        get = get_api(repository, os.environ.get("GH_TOKEN", ""))
        executor = select_executor(event, os.environ["GITHUB_EVENT_NAME"], repository, get)
        files = trusted_files(executor, get)
        print("Trusted executor: " + executor, flush=True)
        with tempfile.TemporaryDirectory(prefix="cf7-path-budget-") as folder:
            for filename, data in files.items():
                Path(folder, filename).write_bytes(data)
            report = str(Path(folder, "report.json"))
            result = subprocess.run([sys.executable, "-I", "-S", str(Path(folder, "github_gate.py")),
                                     "--executor", executor, "--json", report], cwd=folder, check=False)
            if Path(report).exists():
                # Durable machine-readable JSON in the GitHub log. A fixed
                # prefix prevents path data from becoming workflow commands.
                payload = json.loads(Path(report).read_text(encoding="utf-8"))
                print("PATH_BUDGET_REPORT_JSON=" + json.dumps(payload, ensure_ascii=True, separators=(",", ":")))
            else:
                raise BootstrapError("Trusted runner returned no machine-readable report")
            return result.returncode
    except Exception as exc:
        payload = {"schema_version": 1, "gate": "incomplete", "bootstrap": True,
                   "error": str(exc), "candidate_code_executed": False}
        print("PATH_BUDGET_REPORT_JSON=" + json.dumps(payload, ensure_ascii=True, separators=(",", ":")))
        return 2


if __name__ == "__main__":
    sys.exit(main())
