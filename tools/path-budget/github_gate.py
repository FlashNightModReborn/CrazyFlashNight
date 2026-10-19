#!/usr/bin/env python3
"""Read-only GitHub tree adapter. Run only from reviewed trusted base code.

No checkout, Git fetch, asset blob download, candidate Python, local action,
package installation, cache, secret, or write API is used. Token, if provided,
needs contents:read only. Tree metadata and two bounded JSON blobs are read.
"""
import argparse
import base64
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import git_gate as gate
import path_budget as core

REPO = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z")
MAX_API_BYTES = 64 * 1024 * 1024


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        raise core.AuditError("API redirect refused; authorization stays on api.github.com")


def checked_repo(value):
    if not isinstance(value, str) or not REPO.fullmatch(value) or any(x in (".", "..") for x in value.split("/")):
        raise core.AuditError("Invalid immutable event repository identity")
    return value


class GitHubObjects:
    def __init__(self, repository, token="", head_repo=None, head_commit=None, head_repo_id=None):
        self.repository = checked_repo(repository)
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect())
        self.head_repo = checked_repo(head_repo) if head_repo else self.repository
        self.head_commit = head_commit
        self.head_repo_id = head_repo_id
        self.cache = {}
        self.requests = 0
        if self.head_repo != self.repository:
            identity = self.get(self.head_repo, "")
            if identity.get("id") != head_repo_id or identity.get("full_name", "").lower() != self.head_repo.lower():
                raise core.AuditError("Fork repository identity differs from frozen event")

    def get(self, repository, endpoint, limit=MAX_API_BYTES):
        repository = checked_repo(repository)
        url = "https://api.github.com/repos/" + repository + endpoint
        headers = {"Accept": "application/vnd.github+json", "User-Agent": "CF7-path-budget-metadata",
                   "X-GitHub-Api-Version": "2022-11-28"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        self.requests += 1
        with self.opener.open(urllib.request.Request(url, headers=headers), timeout=60) as response:
            raw = response.read(limit + 1)
        if len(raw) > limit:
            raise core.AuditError("API response exceeded bounded size")
        value = core.strict_json(raw.decode("utf-8"))
        if not isinstance(value, dict):
            raise core.AuditError("API response is not an object")
        return value

    def commit(self, commit):
        gate.checked_oid(commit)
        repositories = [self.repository]
        if commit == self.head_commit and self.head_repo != self.repository:
            repositories.append(self.head_repo)
        for index, repository in enumerate(repositories):
            try:
                value = self.get(repository, "/git/commits/" + commit)
                if value.get("sha") != commit:
                    raise core.AuditError("API commit identity mismatch")
                return repository, value
            except urllib.error.HTTPError as exc:
                if exc.code != 404 or index == len(repositories) - 1:
                    raise
        raise core.AuditError("No authorized repository can resolve fixed commit")

    def manifest(self, commit):
        gate.checked_oid(commit)
        if commit in self.cache:
            return self.cache[commit]
        repository, info = self.commit(commit)
        root = gate.checked_oid(info.get("tree", {}).get("sha"))
        result = self.get(repository, "/git/trees/" + root + "?recursive=1")
        if result.get("sha") != root or not isinstance(result.get("truncated"), bool):
            raise core.AuditError("Tree identity/truncation marker absent or invalid")
        fallback = result["truncated"]
        if not fallback:
            entries = api_entries(result.get("tree"), repository)
        else:
            # Recursive APIs can truncate. Retry smaller recursive subtrees and
            # expand only truncated nodes directly; then recompute all tree IDs.
            entries = []
            pending, recursive_cache, direct_cache = [("", root)], {root: result}, {}
            while pending:
                parent, tree = pending.pop()
                if tree not in recursive_cache:
                    recursive_cache[tree] = self.get(repository, "/git/trees/" + tree + "?recursive=1")
                subtree = recursive_cache[tree]
                if subtree.get("sha") != tree or not isinstance(subtree.get("truncated"), bool):
                    raise core.AuditError("Subtree identity/truncation marker invalid")
                if subtree["truncated"]:
                    if tree not in direct_cache:
                        direct = self.get(repository, "/git/trees/" + tree)
                        if direct.get("sha") != tree or direct.get("truncated") is not False:
                            raise core.AuditError("Direct tree API incomplete")
                        direct_cache[tree] = api_entries(direct.get("tree"), repository, direct=True)
                    children = direct_cache[tree]
                else:
                    children = api_entries(subtree.get("tree"), repository)
                for item in children:
                    name = (parent + "/" if parent else "") + item["path"]
                    entry = dict(item, path=name)
                    entries.append(entry)
                    if subtree["truncated"] and entry["type"] == "tree":
                        pending.append((name, entry["sha"]))
                if len(entries) > 2_000_000:
                    raise core.AuditError("Tree inventory exceeded explicit entry ceiling")
        gate.verify_tree_inventory(entries, root)
        manifest = {"schema_version": 1,
                    "source": {"kind": "github-tree-api", "repository": repository, "commit": commit,
                               "root_tree_sha": root,
                               "method": "fixed commit API binding; every tree hash recomputed",
                               "recursive_truncated_fallback": fallback,
                               "api_requests_so_far": self.requests},
                    "completeness": {"complete": True, "truncated": False,
                                     "expected_entries": len(entries), "uncovered": []},
                    "entries": entries}
        self.cache[commit] = manifest
        return manifest

    def small_json(self, entries, path):
        entry = gate.index_entries(entries).get(path)
        if not entry or entry["mode"] != "100644" or entry["type"] != "blob":
            raise core.AuditError("Required regular data blob missing: " + path)
        if not isinstance(entry.get("size"), int) or isinstance(entry["size"], bool) or not 0 <= entry["size"] <= gate.MAX_SMALL_BLOB:
            raise core.AuditError("Small data blob size missing/out of bounds: " + path)
        value = self.get(entry["_repository"], "/git/blobs/" + entry["sha"], limit=3 * gate.MAX_SMALL_BLOB)
        if value.get("sha") != entry["sha"] or value.get("encoding") != "base64" or value.get("size") != entry["size"]:
            raise core.AuditError("Blob API identity/encoding/size mismatch")
        try:
            body = base64.b64decode("".join(value["content"].split()), validate=True)
        except (ValueError, TypeError, KeyError) as exc:
            raise core.AuditError("Invalid blob base64") from exc
        if len(body) != entry["size"] or gate.git_hash("blob", body, len(entry["sha"])) != entry["sha"]:
            raise core.AuditError("Data blob hash verification failed")
        data = core.strict_json(body.decode("utf-8"))
        if not isinstance(data, dict):
            raise core.AuditError("Data blob must be a JSON object")
        return data


def api_entries(values, repository, direct=False):
    if not isinstance(values, list):
        raise core.AuditError("Tree API entries missing")
    result = []
    for value in values:
        if not isinstance(value, dict):
            raise core.AuditError("Invalid tree API entry")
        path = core.validate_path(value.get("path"))
        if direct and "/" in path:
            raise core.AuditError("Direct tree API unexpectedly returned descendants")
        mode, kind, oid = value.get("mode"), value.get("type"), gate.checked_oid(value.get("sha"))
        # Reuse exactly the NUL contract and mode/type validation. Paths are not
        # newline/shell parsed, normalized, or replaced after API decoding.
        raw = (str(mode) + " " + str(kind) + " " + oid + "\t" + path).encode("utf-8") + b"\0"
        parsed = core.parse_git_ls_tree_nul(raw)[0]
        parsed.update(size=value.get("size"), _repository=repository)
        result.append(parsed)
    return result


def frozen_event(event, event_name, repository, github_sha):
    repository = checked_repo(repository)
    if event.get("repository", {}).get("full_name", "").lower() != repository.lower():
        raise core.AuditError("Event repository differs from runner repository")
    if event_name == "pull_request":
        pr = event.get("pull_request", {})
        base, head = pr.get("base", {}), pr.get("head", {})
        if base.get("repo", {}).get("full_name", "").lower() != repository.lower():
            raise core.AuditError("PR base repository identity mismatch")
        base_commit, head_commit = gate.checked_oid(base.get("sha")), gate.checked_oid(head.get("sha"))
        head_repository = checked_repo(head.get("repo", {}).get("full_name"))
        return {"base": base_commit, "head": head_commit, "head_repo": head_repository,
                "head_repo_id": head.get("repo", {}).get("id"), "base_ref": base.get("ref"),
                "merge": gate.checked_oid(github_sha) if github_sha else None}
    if event_name == "push":
        if event.get("ref") != "refs/heads/main" or event.get("deleted") is True:
            raise core.AuditError("Only live main push is in this adapter's scope")
        base_commit, head_commit = gate.checked_oid(event.get("before")), gate.checked_oid(event.get("after"))
        if base_commit == "0" * len(base_commit):
            raise core.AuditError("Bootstrap: push has no reviewed before commit")
        if github_sha and github_sha != head_commit:
            raise core.AuditError("Push runner SHA differs from frozen after")
        return {"base": base_commit, "head": head_commit, "head_repo": repository,
                "head_repo_id": event["repository"].get("id"), "base_ref": "main", "merge": None}
    raise core.AuditError("Unsupported event; no implicit workflow_dispatch or merge_group guarantee")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", default=os.environ.get("GITHUB_EVENT_PATH"))
    parser.add_argument("--event-name", default=os.environ.get("GITHUB_EVENT_NAME"))
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--executor", required=True, help="Immutable reviewed code revision selected by bootstrap")
    parser.add_argument("--json", dest="json_output", required=True)
    args = parser.parse_args(argv)
    report = None
    try:
        executor = gate.checked_oid(args.executor)
        event = core.read_json(args.event)
        frozen = frozen_event(event, args.event_name, args.repository, os.environ.get("GITHUB_SHA"))
        reader = GitHubObjects(args.repository, os.environ.get("GH_TOKEN", ""),
                               frozen["head_repo"], frozen["head"], frozen["head_repo_id"])
        report = gate.audit_objects(reader, frozen["base"], frozen["head"], executor)
        report["comparison"]["executor_commit"] = executor
        report["comparison"]["event"] = args.event_name
        report["integration"] = {"status": "not_available", "scope": "head-only scan"}
        if args.event_name == "pull_request" and frozen["merge"] and frozen["merge"] != frozen["head"]:
            try:
                _, merge_info = reader.commit(frozen["merge"])
                parents = [item.get("sha") for item in merge_info.get("parents", [])]
                if parents != [frozen["base"], frozen["head"]]:
                    raise core.AuditError("Merge parents do not match frozen current base/head")
            except (core.AuditError, urllib.error.URLError) as exc:
                report["integration"] = {"status": "not_available", "scope": "head-only scan", "reason": str(exc)}
            else:
                # Once a bound integration commit exists, any scan/config error
                # is incomplete, never silently downgraded to a green head-only run.
                integration = gate.audit_objects(reader, frozen["base"], frozen["merge"], executor)
                report["integration"] = dict(gate.compact_report(integration), status="scanned_verified_parents")
                if integration["gate"] == "incomplete" or report["gate"] == "incomplete":
                    report["gate"] = "incomplete"
                elif integration["gate"] == "fail":
                    report["gate"] = "fail"
        report["api_requests"] = reader.requests
        gate.print_report(report)
        print("integration=%s gate=%s" % (report["integration"]["status"], report["integration"].get("gate", "head-only")))
        return 2 if report["gate"] == "incomplete" else 1 if report["gate"] == "fail" else 0
    except (core.AuditError, OSError, UnicodeError, ValueError, TypeError, KeyError, urllib.error.URLError) as exc:
        report = {"schema_version": 1, "gate": "incomplete", "error": str(exc), "candidate_code_executed": False}
        print("INCOMPLETE: " + json.dumps(str(exc), ensure_ascii=True), file=sys.stderr)
        return 2
    finally:
        if report is not None:
            Path(args.json_output).write_text(json.dumps(gate.compact_report(report), ensure_ascii=True, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
