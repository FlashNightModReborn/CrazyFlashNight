import contextlib
import csv
import io
import json
import tempfile
import unittest
import zipfile
from dataclasses import asdict, replace
from pathlib import Path
from unittest import mock

import path_budget as pb


def manifest(paths, **changes):
    value = {"schema_version": 1,
             "source": {"kind": "git", "commit": "8" * 40, "root_tree_sha": "9" * 40, "method": "unit fixture"},
             "completeness": {"complete": True, "truncated": False, "expected_entries": len(paths)},
             "entries": [{"path": p, "type": "blob", "mode": "100644", "sha": "a" * 40} if isinstance(p, str) else p for p in paths]}
    value.update(changes)
    return value


def baseline(policy, path, rules=None):
    return {"schema_version": 1, "policy": asdict(policy), "exceptions": [
        {"path": path, "category": "historical-test", "reason": "Reviewed preexisting long fixture",
         "rules": rules or ["relative_utf16"]}]}


class UnicodeAndInputTests(unittest.TestCase):
    def test_chinese_non_bmp_and_no_normalization(self):
        self.assertEqual(pb.utf16_units("中文😀"), 4)
        self.assertEqual(len("中文😀".encode("utf-8")), 10)
        self.assertEqual(pb.utf16_units("é"), 1)
        self.assertEqual(pb.utf16_units("e\u0301"), 2)
        report = pb.audit(manifest(["中文😀/e\u0301.txt"]))
        row = report["entries"][0]
        self.assertEqual(row["path"], "中文😀/e\u0301.txt")
        self.assertEqual(row["relative_utf16"], 11)

    def test_nul_git_preserves_spaces_quotes_tabs_newlines(self):
        names = ['a b/"quoted".txt', "tab\tname\nline", "中文😀.txt", r'literal\"123"']
        data = b"".join(b"100644 blob " + b"a" * 40 + b"\t" + p.encode() + b"\0" for p in names)
        entries = pb.parse_git_ls_tree_nul(data)
        self.assertEqual([e["path"] for e in entries], names)
        self.assertEqual(pb.audit(manifest(entries))["summary"]["entries"], 4)

    def test_non_nul_git_display_rejected(self):
        with self.assertRaisesRegex(pb.AuditError, "NUL"):
            pb.parse_git_ls_tree_nul(b'100644 blob ' + b'a' * 40 + b'\t"\\344\\270\\255.txt"\n')

    def test_non_utf8_git_is_explicitly_unsupported(self):
        with self.assertRaisesRegex(pb.AuditError, "UTF-8"):
            pb.parse_git_ls_tree_nul(b"100644 blob " + b"a" * 40 + b"\t\xff\0")

    def test_invalid_object_id_rejected(self):
        with self.assertRaises(pb.AuditError):
            pb.parse_git_ls_tree_nul(b"100644 blob invalid\tfile\0")

    def test_symlinks_and_directories_are_counted(self):
        values = [{"path": "dir", "type": "tree", "mode": "040000", "sha": "a" * 40},
                  {"path": "dir/link", "type": "blob", "mode": "120000", "sha": "b" * 40}]
        result = pb.audit(manifest(values))
        self.assertEqual(result["summary"]["types"], {"directory": 1, "symlink": 1})
        self.assertEqual(result["entries"][0]["directory_depth"], 1)
        self.assertEqual(result["entries"][1]["directory_depth"], 1)

    def test_invalid_unicode_surrogate_rejected(self):
        with self.assertRaisesRegex(pb.AuditError, "surrogate"):
            pb.audit(manifest(["bad\ud800"]))

    def test_unsafe_relative_paths_rejected(self):
        for path in ("/root", "../escape", "dir/../escape", "C:/abs", "a//b", "a/./b", "bad\0x"):
            with self.subTest(path=path), self.assertRaises(pb.AuditError):
                pb.audit(manifest([path]))

    def test_duplicate_paths_rejected(self):
        with self.assertRaisesRegex(pb.AuditError, "Duplicate"):
            pb.audit(manifest(["same", "same"]))

    def test_archive_list_json_can_preserve_newline(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "list.json"
            path.write_text(json.dumps(["space name", "line\nname"]), encoding="utf-8")
            metadata = manifest([])
            del metadata["entries"]
            metadata["completeness"]["expected_entries"] = 2
            result = pb.audit(pb.load_manifest(path, "archive-list", metadata))
            self.assertEqual(result["gate"], "pass")
            self.assertEqual(result["entries"][1]["path"], "line\nname")


class BoundaryAndProjectionTests(unittest.TestCase):
    def test_relative_budget_before_equal_after(self):
        policy = pb.Policy(relative_limit=180, root_units=0, full_visible_limit=1000)
        result = pb.audit(manifest(["x" * n for n in (179, 180, 181)]), policy)
        self.assertEqual([r["status"] for r in result["entries"]], ["within_budget", "within_budget", "new_violation"])

    def test_full_budget_before_equal_after_with_separator(self):
        policy = pb.Policy(relative_limit=999, root_units=60, full_visible_limit=240)
        result = pb.audit(manifest(["x" * n for n in (178, 179, 180)]), policy)
        self.assertEqual([r["full_visible_utf16"] for r in result["entries"]], [239, 240, 241])
        self.assertEqual([r["status"] for r in result["entries"]], ["within_budget", "within_budget", "new_violation"])

    def test_actual_root_trailing_separator_is_not_doubled(self):
        a = pb.audit(manifest(["file"]), pb.Policy(root="C:\\short"))
        b = pb.audit(manifest(["file"]), pb.Policy(root="C:\\short\\"))
        self.assertEqual(a["entries"][0]["full_visible_utf16"], b["entries"][0]["full_visible_utf16"])
        self.assertEqual(a["root_separator_utf16"], 1)
        self.assertEqual(b["root_separator_utf16"], 0)
        self.assertEqual(pb.audit(manifest(["f"]), pb.Policy(root="C:\\"))["entries"][0]["full_visible_utf16"], 4)

    def test_non_bmp_root_units(self):
        result = pb.audit(manifest(["f"]), pb.Policy(root="C:/😀"))
        self.assertEqual(result["root_utf16"], 5)
        self.assertEqual(result["entries"][0]["full_visible_utf16"], 7)

    def test_segment_before_equal_after(self):
        policy = pb.Policy(relative_limit=999, full_visible_limit=2000)
        result = pb.audit(manifest(["x" * n for n in (254, 255, 256)]), policy)
        self.assertEqual([r["status"] for r in result["entries"]], ["within_budget", "within_budget", "new_violation"])
        self.assertEqual(result["entries"][-1]["violations"][0]["rule"], "segment_utf16")

    def test_deep_short_names(self):
        path = "/".join(["a"] * 100) + "/x.txt"
        row = pb.audit(manifest([path]))["entries"][0]
        self.assertEqual(row["max_segment_utf16"], 5)
        self.assertEqual(row["directory_depth"], 100)
        self.assertEqual(row["segment_count"], 101)
        self.assertEqual(row["status"], "new_violation")

    def test_prefix_and_build_suffix(self):
        policy = pb.Policy(prefix="obj/候选/", suffix=".runtimeconfig.json")
        row = pb.audit(manifest(["Launcher"]), policy)["entries"][0]
        self.assertEqual(row["projected_path"], "obj/候选/Launcher.runtimeconfig.json")
        self.assertEqual(row["full_visible_utf16"], 61 + pb.utf16_units(row["projected_path"]))

    def test_full_projection_is_not_appended_twice(self):
        path = "obj/候选/Launcher.runtimeconfig.json"
        policy = pb.Policy(prefix="obj/候选", suffix=".runtimeconfig.json", already_projected=True)
        row = pb.audit(manifest([path]), policy)["entries"][0]
        self.assertEqual(row["projected_path"], path)
        entry = {"path": path, "type": "file", "already_projected": True}
        row = pb.audit(manifest([entry]), replace(policy, already_projected=False))["entries"][0]
        self.assertEqual(row["projected_path"], path)

    def test_budget_matrix_accounts_for_root_separator(self):
        matrix = pb.audit(manifest(["x" * 180]))["impact_matrix"]
        self.assertEqual(len(matrix), 6)
        row = [r for r in matrix if r["root_units"] == 60 and r["relative_limit"] == 200][0]
        self.assertEqual(row["effective_relative_limit"], 179)
        self.assertEqual(row["relative_exceeded"], 0)
        self.assertEqual(row["full_exceeded"], 1)

    def test_negative_budget_rejected(self):
        with self.assertRaises(pb.AuditError):
            pb.audit(manifest(["a"]), pb.Policy(root_units=-1))


class BaselineLifecycleTests(unittest.TestCase):
    policy = pb.Policy(relative_limit=10, root_units=0, full_visible_limit=1000)
    old_path = "old_directory/file.txt"

    def test_content_only_change_is_retained(self):
        base = baseline(self.policy, self.old_path)
        current = manifest([{"path": self.old_path, "type": "blob", "mode": "100644", "sha": "f" * 40}])
        result = pb.audit(current, self.policy, base)
        self.assertEqual(result["gate"], "pass")
        self.assertEqual(result["summary"]["historical_exceptions"], 1)

    def test_new_violation_fails(self):
        result = pb.audit(manifest([self.old_path, "new_directory/file.txt"]), self.policy, baseline(self.policy, self.old_path))
        self.assertEqual(result["gate"], "fail")
        self.assertEqual(result["summary"]["new_violations"], 1)

    def test_directory_rename_affects_every_descendant(self):
        old = ["long_old/a.txt", "long_old/b.txt"]
        base = baseline(self.policy, old[0])
        base["exceptions"].append(dict(base["exceptions"][0], path=old[1]))
        result = pb.audit(manifest(["long_new/a.txt", "long_new/b.txt"]), self.policy, base)
        self.assertEqual(result["summary"]["new_violations"], 2)
        self.assertEqual(result["summary"]["stale_exceptions"], 2)

    def test_shortened_exception_must_be_removed(self):
        base = baseline(self.policy, self.old_path)
        result = pb.audit(manifest(["short.txt"]), self.policy, base)
        self.assertEqual(result["summary"]["new_violations"], 0)
        self.assertEqual(result["baseline"]["stale_requires_removal"][0]["reason"], "removed_or_renamed")
        self.assertEqual(result["gate"], "fail")
        candidate = dict(base, exceptions=[])
        self.assertEqual(pb.audit(manifest(["short.txt"]), self.policy, candidate, base)["gate"], "pass")
        self.assertEqual(len(base["exceptions"]), 1)  # Read-only, never prunes input silently.

    def test_within_budget_exception_is_stale(self):
        result = pb.audit(manifest(["short"]), self.policy, baseline(self.policy, "short"))
        self.assertEqual(result["summary"]["stale_exceptions"], 1)

    def test_silent_baseline_addition_is_rejected(self):
        reference = baseline(self.policy, self.old_path)
        candidate = json.loads(json.dumps(reference))
        candidate["exceptions"].append(dict(reference["exceptions"][0], path="new_directory/file.txt"))
        with self.assertRaisesRegex(pb.AuditError, "addition"):
            pb.audit(manifest([self.old_path, "new_directory/file.txt"]), self.policy, candidate, reference)

    def test_silent_rule_expansion_is_rejected(self):
        reference = baseline(self.policy, self.old_path)
        candidate = json.loads(json.dumps(reference))
        candidate["exceptions"][0]["rules"].append("full_visible_utf16")
        with self.assertRaisesRegex(pb.AuditError, "modified/expanded"):
            pb.audit(manifest([self.old_path]), self.policy, candidate, reference)

    def test_silent_policy_widening_is_rejected(self):
        base = baseline(self.policy, self.old_path)
        with self.assertRaisesRegex(pb.AuditError, "policy"):
            pb.audit(manifest([self.old_path]), replace(self.policy, relative_limit=100), base)

    def test_new_rule_on_old_path_is_not_grandfathered(self):
        policy = replace(self.policy, full_visible_limit=15)
        result = pb.audit(manifest([self.old_path]), policy, baseline(policy, self.old_path))
        self.assertEqual(result["summary"]["new_violations"], 1)

    def test_unreviewed_reason_rejected(self):
        base = baseline(self.policy, self.old_path)
        base["exceptions"][0]["reason"] = "REVIEW_REQUIRED"
        with self.assertRaisesRegex(pb.AuditError, "reviewed"):
            pb.audit(manifest([self.old_path]), self.policy, base)


class CoverageZipAndOutputTests(unittest.TestCase):
    def test_empty_tree_not_a_pass(self):
        result = pb.audit(manifest([]))
        self.assertEqual(result["gate"], "incomplete")
        self.assertIsNone(result["summary"]["max_relative_utf16"])

    def test_missing_completeness_not_a_pass(self):
        source = manifest(["file"])
        del source["completeness"]
        self.assertEqual(pb.audit(source)["gate"], "incomplete")

    def test_truncated_uncovered_and_count_mismatch(self):
        for completeness in ({"complete": True, "truncated": True},
                             {"complete": True, "truncated": False, "uncovered": ["assets"]},
                             {"complete": True, "truncated": False, "expected_entries": 10}):
            with self.subTest(completeness=completeness):
                self.assertEqual(pb.audit(manifest(["file"], completeness=completeness))["gate"], "incomplete")

    def test_gitlinks_explicit_and_not_counted_as_audited_contents(self):
        value = manifest([{"path": "module", "type": "commit", "mode": "160000", "sha": "b" * 40}])
        value["completeness"]["gitlinks_expanded"] = True
        report = pb.audit(value)
        self.assertEqual(report["gate"], "incomplete")
        self.assertEqual(report["coverage"]["unexpanded_gitlinks"], ["module"])
        self.assertEqual(report["summary"]["types"], {"gitlink": 1})
        value["entries"][0]["gitlink_expanded"] = True
        self.assertEqual(pb.audit(value)["gate"], "pass")

    def test_zip_top_directory_and_no_extraction_or_full_read(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "candidate.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("Version-123/", b"")
                archive.writestr("Version-123/中文😀 file.txt", b"payload")
                archive.writestr("Version-123/nested.zip", b"not actually expanded")
            with mock.patch.object(Path, "read_bytes", side_effect=AssertionError("must not read entire zip")), \
                    mock.patch.object(zipfile.ZipFile, "extractall", side_effect=AssertionError("must not extract")), \
                    mock.patch.object(zipfile.ZipFile, "read", side_effect=AssertionError("must not decompress")):
                source = pb.load_manifest(path, "zip")
                result = pb.audit(source, pb.Policy(root_units=80))
            row = result["entries"][1]
            self.assertEqual(row["path"], "Version-123/中文😀 file.txt")
            self.assertEqual(row["full_visible_utf16"], 81 + pb.utf16_units(row["path"]))
            self.assertEqual(result["entries"][0]["relative_utf16"], len("Version-123"))
            self.assertEqual(result["summary"]["entries"], 3)
            self.assertIsNone(result["input_sha256"])
            self.assertTrue(result["source"]["central_directory_only"])

    def test_csv_roundtrip_special_names(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "out.csv"
            names = ['a b/"quoted",中文😀', "newline\nfile"]
            pb.write_csv(pb.audit(manifest(names)), path)
            with path.open(encoding="utf-8", newline="") as source:
                self.assertEqual([r["path"] for r in csv.DictReader(source)], names)

    def test_cli_json_and_exit_status(self):
        with tempfile.TemporaryDirectory() as td:
            source, output, csvout = [Path(td) / name for name in ("manifest.json", "result.json", "result.csv")]
            source.write_text(json.dumps(manifest(["file"])), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()):
                status = pb.main([str(source), "--json", str(output), "--csv", str(csvout)])
            self.assertEqual(status, 0)
            self.assertEqual(json.loads(output.read_text())["gate"], "pass")
            source.write_text(json.dumps(manifest(["a" * 201])), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(pb.main([str(source)]), 1)
            source.write_text(json.dumps(manifest([])), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(pb.main([str(source)]), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
