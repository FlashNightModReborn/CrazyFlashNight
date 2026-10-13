#!/usr/bin/env python3
"""Exercise preservation and image tamper rejection on the actual shared pack."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import os
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("direct_portrait_preservation", Path(__file__).with_name("promote-direct-portraits-v1.py"))
D = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(D)


class DirectPortraitPreservationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="direct-portrait-test-", dir=ROOT / "tmp")
        self.pack = Path(self.temporary.name).resolve()
        self.assertTrue(self.pack.is_relative_to((ROOT / "tmp").resolve()))
        self.addCleanup(self.temporary.cleanup)
        (self.pack / "subjects").mkdir()
        for asset in (D.OUTPUT / "subjects").iterdir():
            os.link(asset, self.pack / "subjects" / asset.name)
        for filename in ("manifest.json", "promotion-receipt.json"):
            shutil.copyfile(D.OUTPUT / filename, self.pack / filename)
        self.manifest = D.read(self.pack / "manifest.json")

    def reseal(self):
        self.manifest = D.seal(self.manifest, "manifestDigest")
        D.write(self.pack / "manifest.json", self.manifest)
        receipt = D.read(self.pack / "promotion-receipt.json")
        receipt.update(manifestDigest=self.manifest["manifestDigest"], counts=self.manifest["counts"],
            manifest={"path":(D.OUTPUT / "manifest.json").relative_to(ROOT).as_posix(),
                "bytes":(self.pack / "manifest.json").stat().st_size,
                "sha256":D.sha((self.pack / "manifest.json").read_bytes())})
        D.write(self.pack / "promotion-receipt.json", D.seal(receipt, "receiptDigest"))

    def check(self):
        return D.check_manifest(self.pack / "manifest.json", logical_output=D.OUTPUT)

    def test_actual_pack_passes(self):
        self.assertEqual(self.check()["manifestDigest"], self.manifest["manifestDigest"])

    def test_resealed_change_to_prior_identity_is_rejected(self):
        base = D.read(D.EVIDENCE / "base-manifest.json")
        ref = next(iter(base["entries"]))
        self.manifest["entries"][ref]["portraitRef"] = "tampered-prior-identity"
        self.reseal()
        with self.assertRaisesRegex(ValueError, "prior accepted identity changed"):
            self.check()

    def test_resealed_unreviewed_new_variant_is_rejected(self):
        self.manifest["entries"]["敌人-前治安官"]["variants"]["default"]["status"] = "pending_human_review"
        self.reseal()
        with self.assertRaises(ValueError):
            self.check()

    def test_corrupted_approved_png_is_rejected(self):
        record = self.manifest["entries"]["敌人-Codex黑仔"]["variants"]["default"]["subject"]["pngFallback"]
        asset = self.pack / "subjects" / Path(record["url"]).name
        # Break the test's hard link before changing bytes; never mutate live art.
        asset.unlink()
        asset.write_bytes(b"corrupted portrait")
        with self.assertRaisesRegex(ValueError, "subject bytes drift"):
            self.check()

    def test_missing_approved_png_is_rejected(self):
        record = self.manifest["entries"]["敌人-前治安官"]["variants"]["default"]["subject"]["pngFallback"]
        (self.pack / "subjects" / Path(record["url"]).name).unlink()
        with self.assertRaisesRegex(ValueError, "live subject fileset drift"):
            self.check()


if __name__ == "__main__":
    unittest.main()
