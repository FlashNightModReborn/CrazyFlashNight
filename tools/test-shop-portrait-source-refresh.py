#!/usr/bin/env python3
"""Exact source-list byte proof for metadata-only portrait refreshes."""
import copy
import hashlib
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("shop_refresh", Path(__file__).with_name("refresh-shop-portrait-sources.py"))
refresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refresh)


def source(raw):
    return {"listedCount": 2, "activeCount": 2, "excludedShopIds": [],
            "list": {"path": "data/shops/list.xml", "bytes": len(raw),
                     "sha256": hashlib.sha256(raw).hexdigest()}}


class ListSourceProofTests(unittest.TestCase):
    def setUp(self):
        self.raw = b"<root>\n<shops>a.json</shops>\n<shops>b.json</shops>\n</root>\n"
        self.previous = source(self.raw.replace(b"\n", b"\r\n"))
        self.current = source(self.raw)

    def test_unchanged_source_needs_no_override(self):
        self.assertIsNone(refresh.validate_list_identity(self.current, self.current, self.raw))

    def test_changed_list_is_rejected_by_default(self):
        with self.assertRaises(RuntimeError):
            refresh.validate_list_identity(self.previous, self.current, self.raw)

    def test_exact_crlf_reconstruction_returns_auditable_proof(self):
        proof = refresh.validate_list_identity(self.previous, self.current, self.raw, True)
        self.assertEqual("crlf-to-lf-byte-equivalence", proof["mode"])
        self.assertEqual(self.previous["list"]["sha256"], proof["previousSha256"])
        self.assertEqual(self.current["list"]["sha256"], proof["canonicalSha256"])

    def test_identity_or_artifact_mutations_are_rejected(self):
        for field, value in (("listedCount", 3), ("activeCount", 1), ("excludedShopIds", ["a"])):
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                mutated = copy.deepcopy(self.current)
                mutated[field] = value
                refresh.validate_list_identity(self.previous, mutated, self.raw, True)
        for field, value in (("path", "other.xml"), ("bytes", 0), ("sha256", "0" * 64)):
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                mutated = copy.deepcopy(self.current)
                mutated["list"][field] = value
                refresh.validate_list_identity(self.previous, mutated, self.raw, True)

    def test_semantic_order_and_whitespace_changes_are_not_eol_equivalence(self):
        for raw in (self.raw.replace(b"a.json", b"c.json"),
                    self.raw.replace(b"a.json", b"x.json").replace(b"b.json", b"a.json").replace(b"x.json", b"b.json"),
                    self.raw.replace(b"<shops>", b" <shops>"), b"<root/>"):
            with self.subTest(raw=raw), self.assertRaises(RuntimeError):
                refresh.validate_list_identity(self.previous, source(raw), raw, True)

    def test_reverse_normalization_is_rejected(self):
        raw = self.raw.replace(b"\n", b"\r\n")
        with self.assertRaises(RuntimeError):
            refresh.validate_list_identity(self.current, source(raw), raw, True)

    def test_old_digest_size_and_mixed_eol_are_not_accepted(self):
        for field, value in (("bytes", 0), ("sha256", "0" * 64)):
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                previous = copy.deepcopy(self.previous)
                previous["list"][field] = value
                refresh.validate_list_identity(previous, self.current, self.raw, True)
        with self.assertRaises(RuntimeError):
            previous = source(self.raw.replace(b"\n", b"\r\n", 1))
            refresh.validate_list_identity(previous, self.current, self.raw, True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
