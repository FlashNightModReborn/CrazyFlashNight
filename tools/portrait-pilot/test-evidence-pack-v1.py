#!/usr/bin/env python3
"""Fail-closed tests for the immutable enemy-portrait evidence pack."""

from __future__ import annotations

import base64
import copy
import hashlib
import importlib.util
import json
import lzma
import os
import tempfile
import unittest
from unittest import mock
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = Path(__file__).with_name("promote-team-portraits-v1.py")
SPEC = importlib.util.spec_from_file_location("cf7_portrait_evidence_test", CONTROLLER)
assert SPEC is not None and SPEC.loader is not None
T = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(T)


def stable_digest(value: dict[str, Any]) -> str:
    clone = copy.deepcopy(value)
    clone.pop("packDigest", None)
    return hashlib.sha256(
        json.dumps(clone, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest().upper()


class EvidencePackTests(unittest.TestCase):
    def setUp(self) -> None:
        self.original_pack_path = T.EVIDENCE_PACK
        self.original_pack = json.loads(T.EVIDENCE_PACK.read_text(encoding="utf-8"))
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / "tmp")

    def tearDown(self) -> None:
        T.EVIDENCE_PACK = self.original_pack_path
        T._EVIDENCE_STATE = None
        self.temp.cleanup()

    def load_mutation(self, pack: dict[str, Any]) -> None:
        pack["packDigest"] = stable_digest(pack)
        path = Path(self.temp.name) / "evidence-pack.json"
        path.write_text(json.dumps(pack, ensure_ascii=False), encoding="utf-8")
        T.EVIDENCE_PACK = path
        T._EVIDENCE_STATE = None
        T._load_evidence_state()

    def test_pack_closes_every_record(self) -> None:
        state = T._load_evidence_state()
        self.assertEqual(len(state["recordsByPath"]), 353)
        for record in state["recordsByPath"].values():
            blob = T._evidence_bytes(record)
            self.assertIsNotNone(blob)
            self.assertEqual(len(blob), record["bytes"])
            self.assertEqual(T.sha256_bytes(blob), record["sha256"])
        self.assertEqual(len(state["derivedMasterRecords"]), 211)
        for record in state["derivedMasterRecords"].values():
            blob = T._evidence_bytes(record)
            self.assertIsNotNone(blob)
            self.assertEqual(len(blob), record["bytes"])
            self.assertEqual(T.sha256_bytes(blob), record["sha256"])

    def test_duplicate_path_is_rejected_even_when_identical(self) -> None:
        pack = copy.deepcopy(self.original_pack)
        pack["records"].append(copy.deepcopy(pack["records"][0]))
        with self.assertRaisesRegex(T.PromotionError, "路径重复"):
            self.load_mutation(pack)

    def test_tampered_record_bytes_is_rejected(self) -> None:
        pack = copy.deepcopy(self.original_pack)
        pack["records"][0]["bytes"] += 1
        with self.assertRaisesRegex(T.PromotionError, "逐条闭合"):
            self.load_mutation(pack)

    def test_orphan_raw_blob_is_rejected(self) -> None:
        pack = copy.deepcopy(self.original_pack)
        archive = pack["rawArchive"]
        compressed = base64.b64decode("".join(archive["dataChunks"]), validate=True)
        blobs = json.loads(lzma.decompress(compressed).decode("utf-8"))
        orphan = b"orphan-evidence-blob"
        blobs[hashlib.sha256(orphan).hexdigest().upper()] = base64.b64encode(orphan).decode("ascii")
        plain = json.dumps(blobs, sort_keys=True, separators=(",", ":")).encode("utf-8")
        compressed = lzma.compress(plain, format=lzma.FORMAT_XZ, preset=9)
        encoded = base64.b64encode(compressed).decode("ascii")
        archive.update({
            "uncompressedBytes": len(plain),
            "compressedBytes": len(compressed),
            "compressedSha256": hashlib.sha256(compressed).hexdigest().upper(),
            "dataChunks": [encoded[index : index + 512] for index in range(0, len(encoded), 512)],
        })
        with self.assertRaisesRegex(T.PromotionError, "raw blob exact-set"):
            self.load_mutation(pack)

    def test_orphan_svg_reconstruction_is_rejected(self) -> None:
        pack = copy.deepcopy(self.original_pack)
        digest, descriptor = next(iter(pack["svgReconstructions"].items()))
        orphan_digest = "0" * 64 if digest != "0" * 64 else "1" * 64
        pack["svgReconstructions"][orphan_digest] = copy.deepcopy(descriptor)
        with self.assertRaisesRegex(T.PromotionError, "SVG reconstruction exact-set"):
            self.load_mutation(pack)

    def test_tampered_inline_artifact_is_rejected(self) -> None:
        pack = copy.deepcopy(self.original_pack)
        descriptor = next(iter(pack["inlineArtifacts"].values()))
        descriptor["bytes"] += 1
        with self.assertRaisesRegex(T.PromotionError, "inline artifact 原始字节漂移"):
            self.load_mutation(pack)

    def test_evidence_only_rejects_unpacked_tmp_artifact(self) -> None:
        with tempfile.TemporaryDirectory(dir=T.PILOT_ROOT) as directory:
            path = Path(directory) / "unpacked.json"
            path.write_text("{}\n", encoding="utf-8")
            record = T.artifact(path)
            with mock.patch.dict(os.environ, {"CF7_PORTRAIT_EVIDENCE_ONLY": "1"}):
                with self.assertRaisesRegex(T.PromotionError, "未进入 immutable evidence pack"):
                    T.resolve_input_path(path, "负例")
                with self.assertRaisesRegex(T.PromotionError, "未进入 immutable evidence pack"):
                    T.verify_artifact_record(record, "负例")
                with self.assertRaisesRegex(T.PromotionError, "未进入 immutable evidence pack"):
                    T.artifact(path)

    def test_evidence_only_artifact_prefers_frozen_record_over_live_tmp(self) -> None:
        state = T._load_evidence_state()
        record = state["recordsByPath"][
            "tmp/portrait-pilot/team-gap-render-r174-final3-large-20260808T071000Z/"
            "portrait-pilot-review-decisions.json"
        ]
        path = ROOT / record["path"]
        self.assertTrue(path.is_file())
        with mock.patch.dict(os.environ, {"CF7_PORTRAIT_EVIDENCE_ONLY": "1"}):
            with mock.patch.object(T, "sha256_file", side_effect=AssertionError("live tmp must not be read")):
                self.assertEqual(T.artifact(path), record)

    def test_evidence_only_materializes_selected_master_without_reading_live_tmp(self) -> None:
        state = T._load_evidence_state()
        record = next(
            record
            for record in state["derivedMasterRecords"].values()
            if (ROOT / record["path"]).is_file()
        )
        live_path = (ROOT / record["path"]).resolve()
        original_sha256_file = T.sha256_file
        original_path_open = Path.open

        def guarded_sha256_file(path: Path) -> str:
            if path.resolve() == live_path:
                raise AssertionError("live derived master must not be hashed")
            return original_sha256_file(path)

        def guarded_path_open(path: Path, *args: Any, **kwargs: Any) -> Any:
            if path.resolve() == live_path:
                raise AssertionError("live derived master must not be opened")
            return original_path_open(path, *args, **kwargs)

        with mock.patch.dict(os.environ, {"CF7_PORTRAIT_EVIDENCE_ONLY": "1"}):
            with mock.patch.object(T, "sha256_file", side_effect=guarded_sha256_file):
                with mock.patch.object(Path, "open", guarded_path_open):
                    materialized = T.resolve_input_path(live_path, "selected master")
                    self.assertNotEqual(materialized.resolve(), live_path)
                    self.assertEqual(T.artifact(materialized), record)
                    self.assertEqual(materialized.stat().st_size, record["bytes"])


if __name__ == "__main__":
    unittest.main()
