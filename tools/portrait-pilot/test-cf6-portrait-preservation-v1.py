#!/usr/bin/env python3
"""Verify the CF6 delta, JK repairs and rejection of tampered assets on the live pack."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("cf6_portrait_preservation", Path(__file__).with_name("produce-cf6-portraits-v1.py"))
D = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(D)


class Cf6PortraitPreservationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="cf6-portrait-test-", dir=ROOT / "tmp")
        self.pack = Path(self.temporary.name).resolve()
        self.assertTrue(self.pack.is_relative_to((ROOT / "tmp").resolve()))
        self.addCleanup(self.temporary.cleanup)
        (self.pack / "subjects").mkdir()
        for asset in (D.OUTPUT / "subjects").iterdir():
            os.link(asset, self.pack / "subjects" / asset.name)
        for name in ("manifest.json", "promotion-receipt.json"):
            shutil.copyfile(D.OUTPUT / name, self.pack / name)
        self.manifest = D.read(self.pack / "manifest.json")

    def check(self):
        return D.check_manifest(self.pack / "manifest.json", logical_output=D.OUTPUT)

    def reseal(self):
        self.manifest = D.seal(self.manifest, "manifestDigest")
        D.write(self.pack / "manifest.json", self.manifest)
        D.write(self.pack / "promotion-receipt.json", D.receipt_for(self.manifest, self.pack / "manifest.json", D.OUTPUT))

    def test_actual_pack_passes(self):
        self.assertEqual(self.check()["manifestDigest"], self.manifest["manifestDigest"])

    def test_jk_repairs_keep_png_preferred_and_orange_pixel_source(self):
        entry = self.manifest["entries"]["敌人-武装JK"]
        self.assertEqual(entry["defaultVariant"], "orange")
        for variant in ("orange", "white"):
            self.assertEqual(entry["variants"][variant]["subject"]["preferredFormat"], "png")
        self.assertEqual(entry["variants"]["orange"]["subject"]["pngFallback"]["sha256"],
                         "0E94E923F14EDDE37FF180999C605924C0808E9DD20E74069FA7CFAFC084CAFF")
        self.assertNotEqual(entry["variants"]["white"]["subject"]["pngFallback"]["sha256"],
                            "01296094A01D3E054E8B6FF5DA117E733ED7A14AE47B9EF1627FF3F186614D9F")

    def test_all_new_native_vectors_are_pure_svg(self):
        data, _ = D.render_data()
        variants = [row["variants"]["default"] for row in data["entries"].values()]
        variants += list(data["jkVariants"].values())
        self.assertEqual(len(variants), 16)
        for variant in variants:
            record = variant["subject"]["svg"]
            root = ET.fromstring((D.OUTPUT / "subjects" / Path(record["url"]).name).read_bytes())
            self.assertFalse(root.findall(".//{http://www.w3.org/2000/svg}image"))
            self.assertFalse(root.findall(".//{http://www.w3.org/2000/svg}feConvolveMatrix"))
            self.assertEqual(record["embeddedRasterCount"], 0)

    def test_resealed_change_to_prior_identity_is_rejected(self):
        self.manifest["entries"]["敌人-前治安官"]["portraitRef"] = "tampered-prior-identity"
        self.reseal()
        with self.assertRaisesRegex(ValueError, "prior accepted identity changed"):
            self.check()

    def test_resealed_change_to_jk_preferred_format_is_rejected(self):
        self.manifest["entries"]["敌人-武装JK"]["variants"]["orange"]["subject"]["preferredFormat"] = "svg"
        self.reseal()
        with self.assertRaisesRegex(ValueError, "JK corrected variant drift"):
            self.check()

    def test_corrupted_new_png_is_rejected(self):
        record = self.manifest["entries"]["敌人-延寿克隆兽"]["variants"]["default"]["subject"]["pngFallback"]
        asset = self.pack / "subjects" / Path(record["url"]).name
        asset.unlink()
        asset.write_bytes(b"corrupted portrait")
        with self.assertRaisesRegex(ValueError, "subject bytes drift"):
            self.check()

    def test_missing_new_png_is_rejected(self):
        record = self.manifest["entries"]["敌人-延寿克隆兽"]["variants"]["default"]["subject"]["pngFallback"]
        (self.pack / "subjects" / Path(record["url"]).name).unlink()
        with self.assertRaises(ValueError):
            self.check()

    def test_new_png_has_transparency(self):
        for ref in D.NEW_REFS:
            record = self.manifest["entries"][ref]["variants"]["default"]["subject"]["pngFallback"]
            with Image.open(D.OUTPUT / "subjects" / Path(record["url"]).name) as image:
                self.assertEqual(image.size, (512, 512))
                self.assertEqual(image.convert("RGBA").getchannel("A").getextrema(), (0, 255))


if __name__ == "__main__":
    unittest.main()
