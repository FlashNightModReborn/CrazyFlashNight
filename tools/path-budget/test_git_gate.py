import contextlib
import io
import json
import subprocess
import tempfile
import unittest
from dataclasses import asdict
from pathlib import Path
from unittest import mock

import git_gate as gate
import path_budget as core


def config(policy=None, prefixes=None):
    return {"schema_version": 1, "policy": asdict(policy or core.Policy()),
            "forbidden_new_prefixes": prefixes or []}


def baseline(policy=None, paths=()):
    return {"schema_version": 1, "policy": asdict(policy or core.Policy()),
            "exceptions": [{"path": p, "category": "historical-evidence", "reason": "Reviewed exact historical path",
                            "rules": ["relative_utf16"]} for p in paths]}


class ObjectRepo:
    def __init__(self, root, sha256=False):
        self.root = Path(root)
        args = ["git", "init", "--bare", "--quiet"]
        if sha256:
            args.append("--object-format=sha256")
        subprocess.run(args + [str(root)], check=True, capture_output=True)

    def put(self, kind, data):
        return subprocess.run(["git", "-C", str(self.root), "hash-object", "-t", kind, "-w", "--stdin"],
                              input=data, check=True, capture_output=True).stdout.decode().strip()

    def tree(self, files):
        nodes = {}
        for path, body in files.items():
            node = nodes
            bits = path.split("/")
            for bit in bits[:-1]:
                node = node.setdefault(bit, {})
            node[bits[-1]] = body

        def build(node):
            entries = []
            for name, value in node.items():
                if isinstance(value, dict):
                    mode, kind, oid = "40000", "tree", build(value)
                elif isinstance(value, tuple):
                    mode, kind, oid = value
                else:
                    mode, kind, oid = "100644", "blob", self.put("blob", value)
                entries.append((name, mode, kind, oid))
            entries.sort(key=lambda item: item[0].encode() + (b"/" if item[2] == "tree" else b""))
            raw = b"".join(mode.encode() + b" " + name.encode() + b"\0" + bytes.fromhex(oid)
                           for name, mode, kind, oid in entries)
            return self.put("tree", raw)
        return build(nodes)

    def commit(self, files, parent=None):
        tree = self.tree(files)
        data = ("tree %s\n%s author A <a@example.invalid> 0 +0000\ncommitter A <a@example.invalid> 0 +0000\n\nfixture\n" %
                (tree, "parent %s\n" % parent if parent else "")).replace("\n author", "\nauthor").encode()
        return self.put("commit", data)

    def project(self, policy=None, exceptions=(), prefixes=None, **files):
        value = {gate.POLICY_PATH: json.dumps(config(policy, prefixes)).encode(),
                 gate.BASELINE_PATH: json.dumps(baseline(policy, exceptions)).encode()}
        value.update(files)
        return value


class GitObjectIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = ObjectRepo(Path(self.temp.name) / "objects.git")
        self.reader = gate.GitObjects(self.repo.root)
        self.policy = core.Policy(relative_limit=10, root_units=0, full_visible_limit=1000)
        # Config paths themselves exceed a tiny test policy; use normal source
        # policy for integration fixtures, and length 181 for historical names.
        self.policy = core.Policy()
        self.old = "old/" + "x" * 180

    def tearDown(self):
        self.temp.cleanup()

    def files(self, exceptions=(), prefixes=None, **files):
        result = self.repo.project(self.policy, (), prefixes, **files)
        base = baseline(self.policy)
        base["exceptions"] = [{"path": p, "category": "historical-evidence", "reason": "Reviewed exact historical path",
                               "rules": ["full_visible_utf16"]} for p in exceptions]
        result[gate.BASELINE_PATH] = json.dumps(base).encode()
        return result

    def test_complete_object_inventory_and_special_names(self):
        names = ['dir/中文😀 file', 'dir/quote"tab\tline\nfile', "a.c", "a/file", "a0"]
        commit = self.repo.commit(self.files(**{name: b"x" for name in names}))
        manifest = self.reader.manifest(commit)
        self.assertTrue(manifest["completeness"]["complete"])
        self.assertTrue(set(names) <= set(e["path"] for e in manifest["entries"]))
        self.assertEqual(core.audit(manifest)["gate"], "pass")
        self.assertFalse((self.repo.root / "tools").exists())

    def test_content_only_update_and_candidate_code_never_runs(self):
        files = self.files([self.old], **{self.old: b"old"})
        before = self.repo.commit(files)
        marker = Path(self.temp.name) / "executed"
        files[self.old] = b"changed"
        files["tools/path-budget/path_budget.py"] = ("raise RuntimeError('do not execute')\n" +
            "open(%r, 'w').write('bad')\n" % str(marker)).encode()
        head = self.repo.commit(files, before)
        report = gate.audit_objects(self.reader, before, head)
        self.assertEqual(report["gate"], "pass")
        self.assertFalse(marker.exists())
        self.assertFalse(report["comparison"]["candidate_code_executed"])
        self.assertEqual(report["comparison"]["changes"][0]["boundary"], "implementation")

    def test_new_long_path_and_removed_still_active_exception_fail(self):
        base = self.repo.commit(self.files([self.old], **{self.old: b"a"}))
        head = self.repo.commit(self.files(**{self.old: b"a", "new/" + "x" * 180: b"x"}))
        result = gate.audit_objects(self.reader, base, head)
        self.assertEqual(result["gate"], "fail")
        self.assertEqual(result["summary"]["new_violations"], 2)

    def test_shortening_and_pruning_exception_pass(self):
        base = self.repo.commit(self.files([self.old], **{self.old: b"a"}))
        stale = self.repo.commit(self.files([self.old], short=b"a"))
        self.assertEqual(gate.audit_objects(self.reader, base, stale)["gate"], "fail")
        clean = self.repo.commit(self.files(short=b"a"))
        self.assertEqual(gate.audit_objects(self.reader, base, clean)["gate"], "pass")

    def test_renamed_directory_blocks_every_descendant(self):
        names = ["old/" + "a" * 175 + "/a", "old/" + "a" * 175 + "/b"]
        base = self.repo.commit(self.files(names, **{p: b"x" for p in names}))
        head = self.repo.commit(self.files(**{p.replace("old/", "new/", 1): b"x" for p in names}))
        report = gate.audit_objects(self.reader, base, head)
        self.assertEqual(report["gate"], "fail")
        self.assertEqual(report["summary"]["new_violations"], 2)

    def test_candidate_policy_and_prefix_widening_rejected(self):
        files = self.files(prefixes=["retired/root"], okay=b"x")
        base = self.repo.commit(files)
        for mutate in (lambda x: x["policy"].update(full_visible_limit=999),
                       lambda x: x.update(forbidden_new_prefixes=[])):
            values = json.loads(files[gate.POLICY_PATH])
            mutate(values)
            candidate = dict(files, **{gate.POLICY_PATH: json.dumps(values).encode()})
            with self.subTest(values=values), self.assertRaisesRegex(core.AuditError, "policy changed"):
                gate.audit_objects(self.reader, base, self.repo.commit(candidate))

    def test_new_or_expanded_candidate_exception_rejected(self):
        files = self.files([self.old], **{self.old: b"x"})
        base = self.repo.commit(files)
        for mutate in (lambda x: x["exceptions"].append(dict(x["exceptions"][0], path="extra")),
                       lambda x: x["exceptions"][0]["rules"].append("relative_utf16"),
                       lambda x: x["exceptions"][0].update(reason="Changed reason")):
            values = json.loads(files[gate.BASELINE_PATH]); mutate(values)
            candidate = dict(files, **{gate.BASELINE_PATH: json.dumps(values).encode()})
            with self.subTest(values=values), self.assertRaises(core.AuditError):
                gate.audit_objects(self.reader, base, self.repo.commit(candidate))

    def test_retired_prefix_only_blocks_new_exact_paths(self):
        prefixes = ["retired/root"]
        before = self.files(prefixes=prefixes, **{"retired/root/existing": b"x"})
        base = self.repo.commit(before)
        before["retired/root/existing"] = b"content changed"
        before["other/evidence/new"] = b"allowed"
        okay = self.repo.commit(before)
        self.assertEqual(gate.audit_objects(self.reader, base, okay)["gate"], "pass")
        before["retired/root/new"] = b"recreated"
        report = gate.audit_objects(self.reader, base, self.repo.commit(before))
        self.assertEqual(report["gate"], "fail")
        self.assertEqual([r["path"] for r in report["boundary_violations"]], ["retired/root/new"])

    def test_retired_prefix_casefold_prevents_windows_case_bypass(self):
        files = self.files(prefixes=["tools/evidence/retired"], okay=b"x")
        base = self.repo.commit(files)
        files["TOOLS/Evidence/Retired/new"] = b"x"
        report = gate.audit_objects(self.reader, base, self.repo.commit(files))
        self.assertEqual(report["gate"], "fail")
        self.assertTrue(any(row["path"] == "TOOLS/Evidence/Retired/new" for row in report["boundary_violations"]))

    def test_missing_malformed_duplicate_and_oversized_config_fail(self):
        base_files = self.files(okay=b"x")
        base = self.repo.commit(base_files)
        for content in (None, b"{", b'{"schema_version":1,"schema_version":1}', b" " * (gate.MAX_SMALL_BLOB + 1)):
            files = dict(base_files)
            if content is None:
                del files[gate.BASELINE_PATH]
            else:
                files[gate.BASELINE_PATH] = content
            with self.subTest(content=repr(content)[:80]), self.assertRaises(core.AuditError):
                gate.audit_objects(self.reader, base, self.repo.commit(files))

    def test_symlink_config_cannot_be_read_as_regular_data(self):
        files = self.files(okay=b"x"); base = self.repo.commit(files)
        files[gate.POLICY_PATH] = ("120000", "blob", self.repo.put("blob", b"/tmp/policy.json"))
        with self.assertRaisesRegex(core.AuditError, "regular data"):
            gate.audit_objects(self.reader, base, self.repo.commit(files))

    def test_gitlink_is_incomplete_without_fetch_or_expansion(self):
        files = self.files(okay=b"x"); base = self.repo.commit(files)
        files["module"] = ("160000", "commit", base)
        result = gate.audit_objects(self.reader, base, self.repo.commit(files))
        self.assertEqual(result["gate"], "incomplete")
        self.assertEqual(result["coverage"]["unexpanded_gitlinks"], ["module"])

    def test_non_main_base_cannot_expand_against_trust_anchor(self):
        files = self.files(okay=b"x"); anchor = self.repo.commit(files)
        changed = json.loads(files[gate.POLICY_PATH]); changed["policy"]["relative_limit"] = 999
        files[gate.POLICY_PATH] = json.dumps(changed).encode()
        files[gate.BASELINE_PATH] = json.dumps(baseline(core.Policy(relative_limit=999))).encode()
        branch = self.repo.commit(files)
        with self.assertRaisesRegex(core.AuditError, "trust anchor"):
            gate.audit_objects(self.reader, branch, branch, anchor)

    def test_cli_gate_and_error_exit_codes(self):
        files = self.files(okay=b"x"); base = self.repo.commit(files)
        output = Path(self.temp.name) / "report.json"
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(gate.main(["--repo", str(self.repo.root), "--base", base, "--head", base, "--json", str(output)]), 0)
            self.assertEqual(json.loads(output.read_text())["gate"], "pass")
            self.assertEqual(gate.main(["--repo", str(self.repo.root), "--base", "HEAD", "--head", base, "--json", str(output)]), 2)
            self.assertEqual(json.loads(output.read_text())["gate"], "incomplete")

    def test_no_lazy_fetch_no_checkout_and_ambient_git_env_scrubbed(self):
        with mock.patch.dict("os.environ", {"GIT_DIR": "/bad", "GIT_CONFIG_COUNT": "1", "GIT_OBJECT_DIRECTORY": "/bad"}):
            reader = gate.GitObjects(self.repo.root)
        self.assertNotIn("GIT_DIR", reader.env)
        self.assertNotIn("GIT_CONFIG_COUNT", reader.env)
        self.assertEqual(reader.env["GIT_NO_LAZY_FETCH"], "1")
        commit = self.repo.commit(self.files(okay=b"x"))
        self.assertTrue(reader.manifest(commit)["entries"])

    def test_isolated_cli_ignores_candidate_cwd_python_modules(self):
        commit = self.repo.commit(self.files(okay=b"x"))
        candidate = Path(self.temp.name) / "candidate-cwd"
        candidate.mkdir()
        marker = candidate / "executed"
        for filename in ("json.py", "sitecustomize.py", "path_budget.py"):
            (candidate / filename).write_text("open(%r, 'w').write('bad')\nraise RuntimeError('candidate executed')\n" % str(marker))
        import sys
        result = subprocess.run([sys.executable, "-I", "-S", str(Path(gate.__file__).resolve()),
                                 "--repo", str(self.repo.root), "--base", commit, "--head", commit],
                                cwd=candidate, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())

    def test_illegal_utf8_git_name_is_explicit_error(self):
        blob = self.repo.put("blob", b"x")
        tree = self.repo.put("tree", b"100644 \xff\0" + bytes.fromhex(blob))
        commit = self.repo.put("commit", ("tree %s\nauthor A <a@b> 0 +0000\ncommitter A <a@b> 0 +0000\n\nx\n" % tree).encode())
        with self.assertRaisesRegex(core.AuditError, "UTF-8"):
            self.reader.manifest(commit)


class IntegrityAndSchemaTests(unittest.TestCase):
    def test_missing_child_or_directory_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            repo = ObjectRepo(Path(td) / "r.git")
            manifest = gate.GitObjects(repo.root).manifest(repo.commit({"a/b": b"x", "a/c": b"y"}))
            for path in ("a", "a/b"):
                with self.subTest(path=path), self.assertRaises(core.AuditError):
                    gate.verify_tree_inventory([e for e in manifest["entries"] if e["path"] != path], manifest["source"]["root_tree_sha"])

    def test_sha256_git_objects_if_supported(self):
        with tempfile.TemporaryDirectory() as td:
            try:
                repo = ObjectRepo(Path(td) / "r.git", sha256=True)
            except subprocess.CalledProcessError:
                self.skipTest("Git does not support SHA-256 repositories")
            manifest = gate.GitObjects(repo.root).manifest(repo.commit({"a/b": b"x"}))
            self.assertEqual(len(manifest["source"]["root_tree_sha"]), 64)
            self.assertEqual(len(manifest["entries"]), 2)

    def test_json_duplicates_nonstandard_numbers_and_unknown_policy_rejected(self):
        for data in ('{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}'):
            with self.subTest(data=data), self.assertRaises(core.AuditError):
                core.strict_json(data)
        for values in (dict(config(), bypass=True), {"schema_version": 1, "policy": {}},
                       dict(config(), forbidden_new_prefixes=["../escape"])):
            with self.subTest(values=values), self.assertRaises(core.AuditError):
                gate.policy_from_config(values)

    def test_nul_mode_type_mismatch_rejected(self):
        for mode, kind in (("040000", "blob"), ("100644", "tree"), ("160000", "blob")):
            with self.subTest(mode=mode), self.assertRaises(core.AuditError):
                core.parse_git_ls_tree_nul((mode + " " + kind + " " + "a" * 40 + "\tx\0").encode())

    def test_baseline_metadata_is_immutable(self):
        reference = baseline(); candidate = dict(reference, approved=True)
        with self.assertRaisesRegex(core.AuditError, "metadata"):
            core.validate_baseline_revision(candidate, reference)

    def test_workflow_change_is_separate_boundary(self):
        entry = {"path": gate.WORKFLOW_PATH, "mode": "100644", "type": "blob", "sha": "a" * 40}
        self.assertEqual(gate.implementation_changes([], [entry])[0]["boundary"], "workflow")


if __name__ == "__main__":
    unittest.main(verbosity=2)
