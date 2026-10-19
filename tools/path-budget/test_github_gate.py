import base64
import contextlib
import copy
import io
import json
import os
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

import ci_bootstrap as boot
import git_gate as gate
import github_gate as github
import path_budget as core
from test_git_gate import ObjectRepo


class FakeAPI(github.GitHubObjects):
    def __init__(self, database, repository="owner/repo", **kwargs):
        self.database = database
        self.calls = []
        super().__init__(repository, **kwargs)

    def get(self, repository, endpoint, limit=github.MAX_API_BYTES):
        self.requests += 1
        self.calls.append((repository, endpoint))
        key = (repository, endpoint)
        if key not in self.database:
            raise urllib.error.HTTPError("https://api.github.com/missing", 404, "missing", {}, None)
        return copy.deepcopy(self.database[key])


def api_database(repo, commits, repository="owner/repo"):
    reader = gate.GitObjects(repo.root)
    database = {}
    for commit in commits:
        manifest = reader.manifest(commit)
        root = manifest["source"]["root_tree_sha"]
        raw = reader.object(commit, "commit").decode()
        parents = [{"sha": line[7:]} for line in raw.splitlines() if line.startswith("parent ")]
        database[(repository, "/git/commits/" + commit)] = {"sha": commit, "tree": {"sha": root}, "parents": parents}
        recursive, children = [], {"": []}
        directories = {"": root}
        for entry in manifest["entries"]:
            value = dict(entry)
            if value["type"] == "blob":
                data = reader.object(entry["sha"], "blob")
                value["size"] = len(data)
                database[(repository, "/git/blobs/" + entry["sha"])] = {
                    "sha": entry["sha"], "size": len(data), "encoding": "base64",
                    "content": base64.encodebytes(data).decode()}
            if value["type"] == "tree":
                directories[entry["path"]] = entry["sha"]
                children.setdefault(entry["path"], [])
            recursive.append(value)
            parent, _, leaf = entry["path"].rpartition("/")
            children.setdefault(parent, []).append(dict(value, path=leaf))
        database[(repository, "/git/trees/" + root + "?recursive=1")] = {"sha": root, "truncated": False, "tree": recursive}
        for path, oid in directories.items():
            database[(repository, "/git/trees/" + oid)] = {"sha": oid, "truncated": False, "tree": children[path]}
            prefix = path + "/" if path else ""
            descendants = [dict(e, path=e["path"][len(prefix):]) for e in recursive
                           if e["path"].startswith(prefix) and e["path"] != path]
            database[(repository, "/git/trees/" + oid + "?recursive=1")] = {
                "sha": oid, "truncated": False, "tree": descendants}
    return database


def event(base, head, base_ref="main", head_repo="owner/repo"):
    return {"repository": {"full_name": "owner/repo", "id": 1},
            "pull_request": {"base": {"sha": base, "ref": base_ref, "repo": {"full_name": "owner/repo"}},
                             "head": {"sha": head, "repo": {"full_name": head_repo, "id": 2}}}}


class GitHubAndBootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = ObjectRepo(Path(self.temp.name) / "r.git")
        self.files = self.repo.project(okay=b"x")
        for filename in boot.FILES:
            self.files["tools/path-budget/" + filename] = ("# reviewed " + filename).encode()
        self.base = self.repo.commit(self.files)
        self.head = self.repo.commit(dict(self.files, **{"中文😀/quote\"tab\tline\n": b"new"}), self.base)
        self.database = api_database(self.repo, [self.base, self.head])

    def tearDown(self):
        self.temp.cleanup()

    def test_complete_tree_and_small_blob_hash_audit(self):
        reader = FakeAPI(self.database)
        report = gate.audit_objects(reader, self.base, self.head, self.base)
        self.assertEqual(report["gate"], "pass")
        self.assertEqual(report["source"]["commit"], self.head)
        self.assertTrue(all(not endpoint.startswith("/contents") for _, endpoint in reader.calls))
        blob_calls = [endpoint for _, endpoint in reader.calls if endpoint.startswith("/git/blobs/")]
        # Only policy and baseline JSON are read, never asset or candidate code.
        self.assertLessEqual(len(set(blob_calls)), 2)

    def test_recursive_truncation_falls_back_to_verified_direct_trees(self):
        root = self.database[("owner/repo", "/git/commits/" + self.head)]["tree"]["sha"]
        self.database[("owner/repo", "/git/trees/" + root + "?recursive=1")].update(truncated=True, tree=[])
        result = FakeAPI(self.database).manifest(self.head)
        self.assertTrue(result["source"]["recursive_truncated_fallback"])
        self.assertTrue(any("中文" in item["path"] for item in result["entries"]))

    def test_truncated_direct_missing_entry_and_tree_hash_mismatch_rejected(self):
        root = self.database[("owner/repo", "/git/commits/" + self.head)]["tree"]["sha"]
        for mutate in (lambda x: x["tree"].pop(), lambda x: x.update(sha="a" * 40), lambda x: x.pop("truncated")):
            data = copy.deepcopy(self.database)
            mutate(data[("owner/repo", "/git/trees/" + root + "?recursive=1")])
            with self.subTest(mutate=mutate), self.assertRaises(core.AuditError):
                FakeAPI(data).manifest(self.head)
        data = copy.deepcopy(self.database)
        data[("owner/repo", "/git/trees/" + root + "?recursive=1")]["truncated"] = True
        data[("owner/repo", "/git/trees/" + root)]["truncated"] = True
        with self.assertRaisesRegex(core.AuditError, "incomplete"):
            FakeAPI(data).manifest(self.head)

    def test_corrupt_json_blob_or_size_rejected(self):
        entry = next(e for e in gate.GitObjects(self.repo.root).manifest(self.head)["entries"] if e["path"] == gate.POLICY_PATH)
        key = ("owner/repo", "/git/blobs/" + entry["sha"])
        for mutate in (lambda x: x.update(content=base64.b64encode(b"{}").decode()), lambda x: x.update(size=999),
                       lambda x: x.update(content="not base64!")):
            data = copy.deepcopy(self.database); mutate(data[key])
            reader = FakeAPI(data); source = reader.manifest(self.head)
            with self.subTest(mutate=mutate), self.assertRaises(core.AuditError):
                reader.small_json(source["entries"], gate.POLICY_PATH)

    def test_verified_fork_fallback_and_identity_rejection(self):
        data = api_database(self.repo, [self.base])
        data.update(api_database(self.repo, [self.head], "fork/repo"))
        data[("fork/repo", "")] = {"id": 2, "full_name": "fork/repo"}
        reader = FakeAPI(data, head_repo="fork/repo", head_commit=self.head, head_repo_id=2)
        self.assertEqual(reader.manifest(self.head)["source"]["repository"], "fork/repo")
        with self.assertRaisesRegex(core.AuditError, "identity"):
            FakeAPI(data, head_repo="fork/repo", head_commit=self.head, head_repo_id=999)

    def test_event_freezes_all_prs_and_main_push_ids(self):
        frozen = github.frozen_event(event(self.base, self.head), "pull_request", "owner/repo", self.head)
        self.assertEqual((frozen["base"], frozen["head"]), (self.base, self.head))
        push = {"repository": {"full_name": "owner/repo"}, "ref": "refs/heads/main", "before": self.base, "after": self.head}
        self.assertEqual(github.frozen_event(push, "push", "owner/repo", self.head)["base"], self.base)
        for mutate in (lambda x: x.update(before="0" * 40), lambda x: x.update(ref="refs/heads/other")):
            bad = copy.deepcopy(push); mutate(bad)
            with self.assertRaises(core.AuditError):
                github.frozen_event(bad, "push", "owner/repo", self.head)
        with self.assertRaises(core.AuditError):
            github.frozen_event(event(self.base, self.head), "pull_request", "different/repo", self.head)

    def test_bootstrap_uses_base_before_or_main_never_candidate(self):
        get = lambda endpoint: {"ref": "refs/heads/main", "object": {"type": "commit", "sha": self.base}}
        self.assertEqual(boot.select_executor(event(self.base, self.head), "pull_request", "owner/repo", get), self.base)
        self.assertEqual(boot.select_executor(event(self.head, self.head, "contributor-branch"), "pull_request", "owner/repo", get), self.base)
        push = {"repository": {"full_name": "owner/repo"}, "ref": "refs/heads/main", "before": self.base, "after": self.head}
        self.assertEqual(boot.select_executor(push, "push", "owner/repo", get), self.base)
        push["before"] = "0" * 40
        with self.assertRaisesRegex(boot.BootstrapError, "Bootstrap"):
            boot.select_executor(push, "push", "owner/repo", get)

    def test_bootstrap_downloads_only_three_reviewed_exact_blobs(self):
        get = lambda endpoint: copy.deepcopy(self.database[("owner/repo", endpoint)])
        files = boot.trusted_files(self.base, get)
        self.assertEqual(set(files), set(boot.FILES))
        self.assertEqual(files["git_gate.py"], b"# reviewed git_gate.py")
        data = copy.deepcopy(self.database)
        entry = next(e for e in gate.GitObjects(self.repo.root).manifest(self.base)["entries"] if e["path"] == "tools/path-budget/git_gate.py")
        data[("owner/repo", "/git/blobs/" + entry["sha"])]["content"] = base64.b64encode(b"# malicious").decode()
        with self.assertRaisesRegex(boot.BootstrapError, "hash"):
            boot.trusted_files(self.base, lambda endpoint: data[("owner/repo", endpoint)])

    def test_missing_trusted_code_is_bootstrap_failure_no_candidate_fallback(self):
        empty = self.repo.commit({"readme": b"x"})
        data = api_database(self.repo, [empty])
        with self.assertRaisesRegex(boot.BootstrapError, "Bootstrap pending"):
            boot.trusted_files(empty, lambda endpoint: data[("owner/repo", endpoint)])

    def test_workflow_inline_bootstrap_matches_source(self):
        directory = Path(__file__).resolve().parent
        workflow_path = directory.parent.parent / ".github/workflows/path-budget.yml"
        if not workflow_path.exists():
            self.skipTest("Workflow is intentionally absent during trusted core bootstrap")
        workflow = workflow_path.read_text()
        embedded = workflow.split("          python3 -I -S - <<'PYBOOTSTRAP'\n", 1)[1].rsplit("          PYBOOTSTRAP\n", 1)[0]
        self.assertEqual("\n".join(line[10:] for line in embedded.splitlines()) + "\n", (directory / "ci_bootstrap.py").read_text())
        self.assertNotIn("actions/checkout", workflow)
        self.assertNotIn("paths-ignore", workflow)
        self.assertNotIn("secrets.", workflow)
        self.assertIn("contents: read", workflow)
        self.assertIn("branches: [main]", workflow)

    def run_main(self, data, merge):
        event_path = Path(self.temp.name) / "event.json"
        event_path.write_text(json.dumps(event(self.base, self.head)))
        report_path = Path(self.temp.name) / "report.json"
        environment = {"GITHUB_SHA": merge, "GITHUB_EVENT_NAME": "pull_request", "GITHUB_EVENT_PATH": str(event_path),
                       "GITHUB_REPOSITORY": "owner/repo"}
        reader = FakeAPI(data)
        with mock.patch.dict(os.environ, environment), mock.patch.object(github, "GitHubObjects", return_value=reader), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            status = github.main(["--executor", self.base, "--json", str(report_path)])
        return status, json.loads(report_path.read_text())

    def merge_commit(self, files, parents=None):
        parents = parents or [self.base, self.head]
        tree = self.repo.tree(files)
        raw = ("tree " + tree + "\n" + "".join("parent " + p + "\n" for p in parents) +
               "author A <a@b> 0 +0000\ncommitter A <a@b> 0 +0000\n\nmerge\n").encode()
        return self.repo.put("commit", raw)

    def test_verified_merge_new_violation_fails_even_when_head_passes(self):
        merge = self.merge_commit(dict(self.files, **{"new/" + "x" * 180: b"x"}))
        data = api_database(self.repo, [self.base, self.head, merge])
        status, report = self.run_main(data, merge)
        self.assertEqual(status, 1)
        self.assertEqual(report["summary"]["new_violations"], 0)
        self.assertEqual(report["integration"]["status"], "scanned_verified_parents")
        self.assertEqual(report["integration"]["summary"]["new_violations"], 1)

    def test_unavailable_or_stale_merge_is_explicit_head_only(self):
        stale = self.merge_commit(self.files, [self.base, self.base])
        data = api_database(self.repo, [self.base, self.head, stale])
        for merge in ("a" * 40, stale):
            with self.subTest(merge=merge):
                status, report = self.run_main(data, merge)
                self.assertEqual(status, 0)
                self.assertEqual(report["integration"]["status"], "not_available")
                self.assertEqual(report["integration"]["scope"], "head-only scan")

    def test_verified_merge_config_error_never_downgrades_to_green(self):
        files = dict(self.files); files[gate.POLICY_PATH] = b"{}"
        merge = self.merge_commit(files)
        status, report = self.run_main(api_database(self.repo, [self.base, self.head, merge]), merge)
        self.assertEqual(status, 2)
        self.assertEqual(report["gate"], "incomplete")

    def test_redirects_and_untrusted_repository_strings_rejected(self):
        for value in ("https://evil.invalid/x", "owner/../repo", "../repo", "owner/repo?x=y"):
            with self.subTest(value=value), self.assertRaises((core.AuditError, boot.BootstrapError)):
                github.checked_repo(value)
        with self.assertRaises(core.AuditError):
            github.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.invalid")
        with self.assertRaises(boot.BootstrapError):
            boot.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.invalid")


if __name__ == "__main__":
    unittest.main(verbosity=2)
