#!/usr/bin/env python3
"""Audit fixed local Git objects without checkout, lazy fetch, or candidate code.

Run this file and path_budget.py from a reviewed trusted version. --base and
--head must be complete immutable commit IDs in an existing object database.
No repository script, hook, local action, filter, submodule, or LFS is executed.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict
from pathlib import Path

# -I intentionally excludes the script directory. Only this reviewed sibling is
# added explicitly; never add the candidate repo or cwd to Python's import path.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import path_budget as core

POLICY_PATH = "tools/path-budget/policy.json"
BASELINE_PATH = "tools/path-budget/exceptions.json"
IMPLEMENTATION_PREFIX = "tools/path-budget/"
WORKFLOW_PATH = ".github/workflows/path-budget.yml"
WORKFLOW_PREFIX = ".github/workflows/"
MAX_SMALL_BLOB = 2 * 1024 * 1024
MAX_TREE_BYTES = 128 * 1024 * 1024
OID = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")


def checked_oid(value):
    if not isinstance(value, str) or not OID.fullmatch(value):
        raise core.AuditError("Expected a complete lowercase immutable object ID")
    return value


class GitObjects:
    def __init__(self, repo):
        self.repo = str(Path(repo).resolve())
        # Avoid ambient alternate worktrees/config, replacement objects, network
        # prompts, and promisor lazy fetch. Read-only commands never checkout.
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_NO_REPLACE_OBJECTS="1", GIT_NO_LAZY_FETCH="1",
                        GIT_TERMINAL_PROMPT="0", GIT_OPTIONAL_LOCKS="0")

    def run(self, args, limit=MAX_SMALL_BLOB):
        command = ["git", "-C", self.repo, "-c", "core.fsmonitor=false",
                   "-c", "protocol.allow=never", "-c", "core.useReplaceRefs=false"] + list(args)
        with tempfile.TemporaryFile() as errors:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                                       stdout=subprocess.PIPE, stderr=errors, env=self.env)
            try:
                data = process.stdout.read(limit + 1)
                if len(data) > limit:
                    process.kill()
                    process.wait()
                    raise core.AuditError("Git object output exceeded size limit")
                status = process.wait(timeout=120)
            except BaseException:
                process.kill()
                process.wait()
                raise
            finally:
                process.stdout.close()
            if status:
                errors.seek(0)
                detail = errors.read(2048).decode("utf-8", errors="replace")
                # Escape potentially attacker-controlled stderr for log safety.
                raise core.AuditError("Git read failed: " + json.dumps(detail, ensure_ascii=True))
            return data

    def object(self, oid, kind, limit=MAX_SMALL_BLOB):
        checked_oid(oid)
        raw_kind = self.run(["cat-file", "-t", oid]).decode("ascii").strip()
        if raw_kind != kind:
            raise core.AuditError("Expected %s object, got %s" % (kind, raw_kind))
        size = int(self.run(["cat-file", "-s", oid]).strip())
        if size < 0 or size > limit:
            raise core.AuditError("Small object exceeded size limit")
        data = self.run(["cat-file", kind, oid], limit)
        if len(data) != size or git_hash(kind, data, len(oid)) != oid:
            raise core.AuditError("Object identity/size verification failed")
        return data

    def manifest(self, commit):
        checked_oid(commit)
        data = self.object(commit, "commit")
        first = data.split(b"\n", 1)[0]
        if not first.startswith(b"tree "):
            raise core.AuditError("Commit does not bind a root tree")
        try:
            tree = checked_oid(first[5:].decode("ascii"))
        except UnicodeError as exc:
            raise core.AuditError("Invalid commit tree ID") from exc
        if len(tree) != len(commit):
            raise core.AuditError("Mixed Git object formats")
        raw = self.run(["ls-tree", "-r", "-t", "-z", "--full-tree", commit], MAX_TREE_BYTES)
        entries = core.parse_git_ls_tree_nul(raw)
        verify_tree_inventory(entries, tree)
        return {"schema_version": 1,
                "source": {"kind": "git-objects", "commit": commit, "root_tree_sha": tree,
                           "method": "ls-tree -r -t -z --full-tree; all tree hashes recomputed",
                           "raw_nul_sha256": hashlib.sha256(raw).hexdigest()},
                "completeness": {"complete": True, "truncated": False,
                                 "expected_entries": len(entries), "uncovered": []},
                "entries": entries}

    def small_json(self, entries, path):
        entry = index_entries(entries).get(path)
        if not entry or entry["mode"] != "100644" or entry["type"] != "blob":
            raise core.AuditError("Required regular data blob missing: " + path)
        try:
            value = core.strict_json(self.object(entry["sha"], "blob").decode("utf-8"))
        except UnicodeError as exc:
            raise core.AuditError("Config is not strict UTF-8 JSON: " + path) from exc
        if not isinstance(value, dict):
            raise core.AuditError("Config must be a JSON object: " + path)
        return value


def git_hash(kind, data, oid_length=40):
    if oid_length not in (40, 64):
        raise core.AuditError("Unsupported Git object format")
    algorithm = hashlib.sha1 if oid_length == 40 else hashlib.sha256
    return algorithm(kind.encode("ascii") + b" " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def index_entries(entries):
    result = {}
    for entry in entries:
        name = core.validate_path(entry["path"])
        if name in result:
            raise core.AuditError("Duplicate Git path: " + repr(name))
        result[name] = entry
    return result


def verify_tree_inventory(entries, root_tree):
    """Prove every listed direct child and every directory against Git tree IDs."""
    checked_oid(root_tree)
    index = index_entries(entries)
    directories = {"": root_tree}
    children = {"": []}
    for name, entry in index.items():
        checked_oid(entry["sha"])
        if len(entry["sha"]) != len(root_tree):
            raise core.AuditError("Mixed Git object formats")
        if entry["type"] == "tree":
            directories[name] = entry["sha"]
            children.setdefault(name, [])
        parent, _, leaf = name.rpartition("/")
        children.setdefault(parent, []).append((leaf, entry))
    if set(children) - set(directories):
        raise core.AuditError("Inventory omits an ancestor directory")
    for parent, expected in directories.items():
        members = children[parent]
        members.sort(key=lambda item: item[0].encode("utf-8") + (b"/" if item[1]["type"] == "tree" else b""))
        chunks = []
        for name, entry in members:
            mode = b"40000" if entry["mode"] == "040000" else entry["mode"].encode("ascii")
            chunks.append(mode + b" " + name.encode("utf-8") + b"\0" + bytes.fromhex(entry["sha"]))
        if git_hash("tree", b"".join(chunks), len(root_tree)) != expected:
            raise core.AuditError("Incomplete/corrupt Git tree inventory at: " + repr(parent))


def policy_from_config(value):
    if set(value) != {"schema_version", "policy", "forbidden_new_prefixes"} or type(value["schema_version"]) is not int or value["schema_version"] != 1:
        raise core.AuditError("Unsupported policy config schema/fields")
    prefixes = value["forbidden_new_prefixes"]
    if not isinstance(prefixes, list) or any(not isinstance(p, str) for p in prefixes):
        raise core.AuditError("forbidden_new_prefixes must be an exact path list")
    if len({p.casefold() for p in prefixes}) != len(prefixes):
        raise core.AuditError("Duplicate forbidden prefix")
    for prefix in prefixes:
        core.validate_path(prefix)
        if prefix.endswith("/") or "\\" in prefix:
            raise core.AuditError("Forbidden prefixes have no trailing slash/backslash")
    policy = value["policy"]
    if not isinstance(policy, dict) or set(policy) != set(asdict(core.Policy())):
        raise core.AuditError("Policy must enumerate every exact policy field")
    try:
        return core.Policy(**policy).validate()
    except TypeError as exc:
        raise core.AuditError("Invalid policy fields") from exc


def implementation_changes(base_entries, head_entries):
    before, after = index_entries(base_entries), index_entries(head_entries)
    selected = sorted(p for p in set(before) | set(after)
                      if p.startswith(IMPLEMENTATION_PREFIX) or p.startswith(WORKFLOW_PREFIX))
    changes = []
    for path in selected:
        old, new = before.get(path), after.get(path)
        signature = lambda item: None if item is None else (item["mode"], item["type"], item["sha"])
        if signature(old) != signature(new):
            changes.append({"path": path,
                            "boundary": "workflow" if path.startswith(WORKFLOW_PREFIX) else "configuration" if path in (POLICY_PATH, BASELINE_PATH) else "implementation",
                            "before": old, "after": new})
    return changes


def audit_objects(reader, base_commit, head_commit, trust_commit=None):
    """The calling script is trusted; all repository blobs remain data only.

    Optional trust_commit anchors non-main bases: their config/baseline must be
    identical/subset of the already reviewed trust anchor before becoming refs.
    """
    started = time.perf_counter()
    base = reader.manifest(base_commit)
    head = reader.manifest(head_commit)
    base_config = reader.small_json(base["entries"], POLICY_PATH)
    candidate_config = reader.small_json(head["entries"], POLICY_PATH)
    policy = policy_from_config(base_config)
    policy_from_config(candidate_config)
    if candidate_config != base_config:
        raise core.AuditError("Candidate policy changed versus trusted base")
    reference = reader.small_json(base["entries"], BASELINE_PATH)
    candidate = reader.small_json(head["entries"], BASELINE_PATH)
    core.baseline_entries(reference, policy)
    if trust_commit is not None:
        anchor = reader.manifest(trust_commit)
        anchor_config = reader.small_json(anchor["entries"], POLICY_PATH)
        if base_config != anchor_config:
            raise core.AuditError("Base policy differs from reviewed trust anchor")
        anchor_baseline = reader.small_json(anchor["entries"], BASELINE_PATH)
        core.baseline_entries(anchor_baseline, policy)
        core.validate_baseline_revision(reference, anchor_baseline)
    report = core.audit(head, policy, candidate, reference)
    base_paths = set(index_entries(base["entries"]))
    boundary = [{"path": entry["path"], "forbidden_prefix": prefix,
                 "reason": "new path enters a retired evidence root"}
                for entry in head["entries"] if entry["path"] not in base_paths
                for prefix in base_config["forbidden_new_prefixes"]
                if entry["path"].casefold() == prefix.casefold() or entry["path"].casefold().startswith(prefix.casefold() + "/")]
    report["boundary_violations"] = boundary
    report["summary"]["boundary_violations"] = len(boundary)
    if boundary and report["gate"] != "incomplete":
        report["gate"] = "fail"
    report["comparison"] = {"base_commit": base_commit, "head_commit": head_commit,
                            "base_root_tree": base["source"]["root_tree_sha"],
                            "head_root_tree": head["source"]["root_tree_sha"],
                            "trust_commit": trust_commit,
                            "scope": "head tree only; no integration/merge-tree claim",
                            "changes": implementation_changes(base["entries"], head["entries"]),
                            "candidate_code_executed": False,
                            "acquire_and_scan_seconds": time.perf_counter() - started}
    return report


def compact_report(report):
    # Keep every failure and precise affected path, avoid an all-entry 40MB CI log.
    return {key: value for key, value in report.items()
            if key not in ("entries", "impact_matrix", "by_top_directory", "longest_30")}


def print_report(report):
    summary = report["summary"]
    print("gate=%s entries=%d new=%d historical=%d stale=%d" %
          (report["gate"], summary["entries"], summary["new_violations"],
           summary["historical_exceptions"], summary["stale_exceptions"]))
    print("comparison=" + json.dumps(report.get("comparison", {}), ensure_ascii=True, sort_keys=True))
    for error in report["coverage"]["errors"]:
        print("INCOMPLETE: " + json.dumps(error, ensure_ascii=True))
    for row in report["violations"]:
        if row["status"] == "new_violation":
            print("VIOLATION: " + json.dumps(row, ensure_ascii=True, sort_keys=True))
    for row in report.get("boundary_violations", []):
        print("RETIRED_ROOT: " + json.dumps(row, ensure_ascii=True, sort_keys=True))
    for row in report["baseline"]["stale_requires_removal"]:
        print("STALE: " + json.dumps(row, ensure_ascii=True, sort_keys=True))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--trust", help="Reviewed config/baseline anchor for a non-main target base")
    parser.add_argument("--json", dest="json_output")
    args = parser.parse_args(argv)
    try:
        report = audit_objects(GitObjects(args.repo), checked_oid(args.base), checked_oid(args.head),
                               checked_oid(args.trust) if args.trust else None)
        if args.json_output:
            Path(args.json_output).write_text(json.dumps(compact_report(report), ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
        print_report(report)
        return 2 if report["gate"] == "incomplete" else 1 if report["gate"] == "fail" else 0
    except (core.AuditError, OSError, UnicodeError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        error = {"schema_version": 1, "gate": "incomplete", "error": str(exc),
                 "comparison": {"base_commit": args.base, "head_commit": args.head,
                                "candidate_code_executed": False}}
        if args.json_output:
            Path(args.json_output).write_text(json.dumps(error, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
        print("INCOMPLETE: " + json.dumps(str(exc), ensure_ascii=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
