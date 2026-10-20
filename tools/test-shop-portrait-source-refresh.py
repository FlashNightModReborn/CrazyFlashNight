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


class DialogueBaselineProofTests(unittest.TestCase):
    def setUp(self):
        self.old = {"dialogueManifest": {"sha256": "bound"},
                    "toolchain": {"dialogueBaker": {"sha256": "baker"}},
                    "dialogueMetadataRefresh": {"mode": "unconsumed-dialogue-metadata-only",
                        "previousManifestSha256": "baseline", "previousBakerSha256": "baker",
                        "tool": {"sha256": "tool"}, "consumedModuleAstSha256": "ast",
                        "unchangedShopEntries": 39}}

    def test_exact_baseline_remains_valid_without_prior_receipt(self):
        del self.old["dialogueMetadataRefresh"]
        self.assertIsNone(refresh.validate_dialogue_baseline(self.old, "bound", "ast", {"tool"}, 39))

    def test_validated_metadata_hop_preserves_original_baseline(self):
        proof = refresh.validate_dialogue_baseline(self.old, "baseline", "ast", {"tool"}, 39)
        self.assertEqual(proof["boundManifestSha256"], "bound")
        self.assertEqual(proof["baselineManifestSha256"], "baseline")

    def test_unknown_or_changed_proof_is_rejected(self):
        for field, value in (("mode", "other"), ("previousManifestSha256", "foreign"),
                             ("previousBakerSha256", "foreign"), ("consumedModuleAstSha256", "foreign"),
                             ("unchangedShopEntries", 38), ("tool", {"sha256": "foreign"})):
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                altered = copy.deepcopy(self.old)
                altered["dialogueMetadataRefresh"][field] = value
                refresh.validate_dialogue_baseline(altered, "baseline", "ast", {"tool"}, 39)

    def test_missing_receipt_cannot_bridge_an_unknown_baseline(self):
        del self.old["dialogueMetadataRefresh"]
        with self.assertRaises(RuntimeError):
            refresh.validate_dialogue_baseline(self.old, "baseline", "ast", {"tool"}, 39)

    def test_chained_baseline_still_requires_matching_consumed_helpers(self):
        self.old["dialogueMetadataRefresh"]["baselineManifestSha256"] = "baseline"
        self.old["dialogueMetadataRefresh"]["previousManifestSha256"] = "intermediate"
        self.assertIsNotNone(refresh.validate_dialogue_baseline(self.old, "baseline", "ast", {"tool"}, 39))
        with self.assertRaises(RuntimeError):
            refresh.validate_dialogue_baseline(self.old, "baseline", "changed-ast", {"tool"}, 39)


if __name__ == "__main__":
    unittest.main(verbosity=2)
