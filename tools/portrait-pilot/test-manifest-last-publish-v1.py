#!/usr/bin/env python3
"""Fault-injection tests for manifest-last portrait publication."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = Path(__file__).with_name("promote-enemy-portraits-v1.py")
SPEC = importlib.util.spec_from_file_location("cf7_manifest_last_publish_test", CONTROLLER)
assert SPEC is not None and SPEC.loader is not None
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class InjectedCrash(BaseException):
    pass


def write_pack(root: Path, label: str, subject_names: list[str]) -> None:
    subjects = root / "subjects"
    subjects.mkdir(parents=True)
    for name in subject_names:
        (subjects / name).write_bytes(f"{label}:{name}".encode("utf-8"))
    (root / "manifest.json").write_text(
        json.dumps({"manifestDigest": label, "runtimeSubjects": subject_names}),
        encoding="utf-8",
    )
    (root / "promotion-receipt.json").write_text(
        json.dumps({"manifestDigest": label}),
        encoding="utf-8",
    )


def fake_check(manifest_path: Path, *, logical_output: Path | None = None) -> dict[str, Any]:
    del logical_output
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    subject_root = manifest_path.parent / "subjects"
    for name in manifest["runtimeSubjects"]:
        if not (subject_root / name).is_file():
            raise AssertionError(f"active manifest references missing subject: {name}")
    return manifest


def assert_runtime_closure(test: unittest.TestCase, output: Path) -> dict[str, Any]:
    manifest = fake_check(output / "manifest.json")
    test.assertTrue(all((output / "subjects" / name).is_file() for name in manifest["runtimeSubjects"]))
    return manifest


class ManifestLastPublishTests(unittest.TestCase):
    def run_crash_case(self, checkpoint: str) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as temporary:
            root = Path(temporary)
            output = root / "live"
            staging = root / "staging"
            backup = root / "backup"
            write_pack(output, "OLD", ["old.svg"])
            write_pack(staging, "NEW", ["new.svg"])

            def crash(name: str) -> None:
                if name == checkpoint:
                    raise InjectedCrash(name)

            with mock.patch.object(P, "check_manifest", side_effect=fake_check):
                with self.assertRaises(InjectedCrash):
                    P.publish_staged_pack(staging, output, backup, fault_hook=crash)
                assert_runtime_closure(self, output)
                P.publish_staged_pack(staging, output, backup)

            manifest = assert_runtime_closure(self, output)
            self.assertEqual(manifest["manifestDigest"], "NEW")
            self.assertEqual({path.name for path in (output / "subjects").iterdir()}, {"new.svg"})
            receipt = json.loads((output / "promotion-receipt.json").read_text(encoding="utf-8"))
            self.assertEqual(receipt["manifestDigest"], "NEW")

    def test_crash_after_subjects_converges(self) -> None:
        self.run_crash_case("subjects_published")

    def test_crash_after_receipt_before_manifest_converges(self) -> None:
        self.run_crash_case("receipt_published")

    def test_crash_after_manifest_before_stale_cleanup_converges(self) -> None:
        self.run_crash_case("manifest_published")

    def test_cleanup_or_check_exception_rolls_back_then_converges(self) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as temporary:
            root = Path(temporary)
            output = root / "live"
            staging = root / "staging"
            backup = root / "backup"
            write_pack(output, "OLD", ["old.svg"])
            write_pack(staging, "NEW", ["new.svg"])

            def fail(name: str) -> None:
                if name == "before_final_check":
                    raise RuntimeError("injected final-check failure")

            with mock.patch.object(P, "check_manifest", side_effect=fake_check):
                with self.assertRaisesRegex(RuntimeError, "injected"):
                    P.publish_staged_pack(staging, output, backup, fault_hook=fail)
                manifest = assert_runtime_closure(self, output)
                self.assertEqual(manifest["manifestDigest"], "OLD")
                self.assertEqual({path.name for path in (output / "subjects").iterdir()}, {"old.svg"})
                P.publish_staged_pack(staging, output, backup)

            self.assertEqual(assert_runtime_closure(self, output)["manifestDigest"], "NEW")

    def test_first_publish_failure_after_manifest_keeps_new_runtime_complete(self) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as temporary:
            root = Path(temporary)
            output = root / "live"
            staging = root / "staging"
            write_pack(staging, "NEW", ["new.svg"])

            def fail(name: str) -> None:
                if name == "before_final_check":
                    raise RuntimeError("injected first-publish final-check failure")

            with mock.patch.object(P, "check_manifest", side_effect=fake_check):
                with self.assertRaisesRegex(RuntimeError, "first-publish"):
                    P.publish_staged_pack(staging, output, None, fault_hook=fail)
                self.assertEqual(assert_runtime_closure(self, output)["manifestDigest"], "NEW")
                self.assertTrue((output / "subjects" / "new.svg").is_file())
                P.publish_staged_pack(staging, output, None)

            self.assertEqual(assert_runtime_closure(self, output)["manifestDigest"], "NEW")


if __name__ == "__main__":
    unittest.main()
