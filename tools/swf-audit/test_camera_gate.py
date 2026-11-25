"""Focused regression tests for the bounded ScreenShake audit gates."""

from collections import Counter
import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import camera_write_gate as gate
import camera_write_scan as scanner
import verify_published_swfs as publish
from swfscan import avm1_container


def scan(script, path="fixture.as"):
    return scanner.scan_blocks(path, [scanner.make_block(script)])


def inventory(script, path="fixture.as"):
    return scan(script, path)[0]


def rule(row, category="archived_fla"):
    return dict(row, category=category, fingerprint=gate.fingerprint(row), maxCount=1)


def coverage(rows, **extra):
    return dict(dict(scope="full", head="fixture-head", toolVersion=scanner.TOOL_VERSION,
                     writeExpressions=len(rows), parseFailures=[], dynamicReview=[],
                     unsupportedSourceContainers=[]), **extra)


def policy(**extra):
    return dict(dict(policyVersion="fixture-policy", allow=[], liveClosureFiles=[],
                     removedLiveLegacy=[], repositoryLegacyDebt=[]), **extra)


class ScannerTests(unittest.TestCase):
    def test_audit_lexical_smoke(self):
        cases = {
            "comments": ('// _root._y += 5;\n/* _root.gameworld._x++; */\ntrace("_root._x = 1;");', 0),
            "alias": ('var g:MovieClip = _root.gameworld; g["_"+"y"] += 5;', 1),
            "inc": ('++_root.gameworld._x; _root["天空盒"]._rotation--;', 2),
            "setprop": ('setProperty("_root.gameworld",1,9); setProperty("/天空盒","_x",2);'
                        'setProperty(_root.collisionLayer,10,3);', 3),
            "rootpublication": ("_root.gameworld = g; g._y=8;", 1),
            "aliasfailure": ("var g = _root.gameworld.someChild; g._y=8;", 0),
        }
        for name, (script, expected) in cases.items():
            with self.subTest(name=name):
                self.assertEqual(expected, len(inventory(script)))

        xml = b'''<DOMSymbolItem name="fixture"><DOMFrame index="32">
          <script><![CDATA[_root.gameworld._y += 5;]]></script>
          <DOMSymbolInstance><script><![CDATA[onClipEvent(enterFrame) { _root._x=1; }]]></script>
          </DOMSymbolInstance></DOMFrame></DOMSymbolItem>'''
        hits, _, _ = scanner.scan_blocks("fixture.xml", scanner.blocks_xml(xml, "fixture.xml"))
        self.assertEqual([33, 33], [row["frameOrClipEvent"] for row in hits])
        self.assertEqual(["script", "clip_or_button_actions"], [row["scriptKind"] for row in hits])

    def test_constant_brackets_and_pre_post_increment(self):
        rows = inventory('_root["game" + "world"]["_y"] += 5;\n'
                         '++_root.gameworld._y;\n_root.gameworld._y--;')
        self.assertEqual(["+=", "++", "--"], [row["operator"] for row in rows])
        self.assertEqual({("_root.gameworld", "_y")}, {(row["target"], row["property"]) for row in rows})

    def test_clip_event_script(self):
        rows = inventory("onClipEvent(enterFrame) { _root.gameworld._y += 1; }")
        self.assertEqual(1, len(rows))
        self.assertEqual("_root.gameworld._y += 1;", rows[0]["writeExpression"])

    def test_scoped_xml_and_fla_coverage_keeps_parse_failure_and_dynamic_review(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(scanner, "git_head", return_value="live-head"):
            repo = Path(temp)
            malformed = b"<x><script><![CDATA[with (_root.gameworld) { _y+=1; }]]></script>"
            (repo / "bad.xml").write_bytes(malformed)
            (repo / "binary.fla").write_bytes(b"Fla binary")
            with zipfile.ZipFile(repo / "archive.fla", "w") as archive:
                archive.writestr("LIBRARY/Symbol.xml",
                                 "<DOMSymbolItem><script>_root._x=1;</script></DOMSymbolItem>")
            rows, report, flas = scanner.scan_sources(repo, [Path("bad.xml"), Path("binary.fla"), Path("archive.fla")])
        self.assertEqual("live-head", report["head"])
        self.assertEqual("scoped", report["scope"])
        self.assertEqual({"files_.xml": 1, "files_.fla": 2},
                         {key: report["statistics"][key] for key in ("files_.xml", "files_.fla")})
        self.assertEqual(1, report["parseFailures"][0]["rawCdataScanned"])
        self.assertEqual("bad.xml", report["dynamicReview"][0]["sourcePath"])
        self.assertEqual("binary.fla", report["unsupportedSourceContainers"][0]["sourcePath"])
        self.assertEqual("archive.fla::LIBRARY/Symbol.xml", rows[0]["sourcePath"])
        self.assertEqual(2, len(flas))


class GateTests(unittest.TestCase):
    def test_audit_gate_smoke(self):
        rows = inventory("_root.gameworld._y += 5;")
        frozen = policy(repositoryLegacyDebt=[rule(rows[0])])
        cases = (
            ("baseline_debt_reported", rows, "new", True, 1),
            ("baseline_clean_rejected", rows, "clean", False, 1),
            ("reviewed_legacy_removed", [], "clean", True, 0),
            ("unreviewed_writer_rejected", inventory("_root._x = 8;"), "new", False, 0),
        )
        for name, hits, mode, expected, debt in cases:
            with self.subTest(name=name):
                report = gate.evaluate(hits, frozen, mode, coverage(hits))
                self.assertEqual(expected, report["boundedWriterGatePassed"])
                self.assertEqual(debt, report["repositoryLegacyRemaining"])

    def test_same_name_symbol_in_a_different_library_is_unreviewed(self):
        xml = b'<DOMSymbolItem name="Same"><DOMFrame index="0"><script>_root._x=1;</script></DOMFrame></DOMSymbolItem>'
        first, second = "first/LIBRARY/Same.xml", "second/LIBRARY/Same.xml"
        permitted, _, _ = scanner.scan_blocks(first, scanner.blocks_xml(xml, first))
        other, _, _ = scanner.scan_blocks(second, scanner.blocks_xml(xml, second))
        frozen = policy(allow=[rule(permitted[0], "camera_authority")])
        rows = permitted + other
        report = gate.evaluate(rows, frozen, "new", coverage(rows))
        self.assertEqual(1, report["authorityPreserved"])
        self.assertEqual(second, report["violations"][0]["sourcePath"])

    def test_duplicate_allowed_and_legacy_expressions_exceed_exact_max(self):
        rows = inventory("_root._x = 8;\n_root._x = 8;")
        self.assertEqual(2, len(rows))
        for ledger, expected in (("allow", "allowed_writer_count_increased"),
                                 ("repositoryLegacyDebt", "repository_legacy_count_increased")):
            with self.subTest(ledger=ledger):
                frozen = policy(**{ledger: [rule(rows[0])]})
                report = gate.evaluate(rows, frozen, "new", coverage(rows))
                self.assertFalse(report["gatePassed"])
                self.assertEqual(expected, report["violations"][0]["reason"])

    def test_every_removed_fingerprint_fails_in_new_and_live_clean(self):
        frozen = json.loads(gate.POLICY.read_text(encoding="utf-8"))
        self.assertEqual(30, len(frozen["removedLiveLegacy"]))
        categories = Counter()
        for entry in frozen["allow"] + frozen["repositoryLegacyDebt"]:
            categories[entry["category"]] += entry["maxCount"]
        self.assertEqual(dict(camera_authority=23, test_fixture=97, tool_sample=4,
                              lady_source_only=4, archived_fla=22), categories)
        for mode in ("new", "live-clean"):
            rows = frozen["removedLiveLegacy"]
            report = gate.evaluate(rows, frozen, mode, coverage(rows))
            self.assertFalse(report["gatePassed"])
            self.assertEqual(30, report["liveLegacyRemaining"])
            self.assertEqual(0, report["liveLegacyRemoved"])
            self.assertEqual(Counter(removed_live_writer_reappeared=30),
                             Counter(row["reason"] for row in report["violations"]))

    def test_new_writer_inside_live_closure_fails(self):
        rows = inventory("_root.collisionLayer._y += 1;", "live.xml")
        report = gate.evaluate(rows, policy(liveClosureFiles=["live.xml"]), "live-clean", coverage(rows))
        self.assertFalse(report["gatePassed"])
        self.assertEqual("unauthorized_live_closure_writer", report["violations"][0]["reason"])

    def test_require_complete_coverage_uses_exit_3_and_retains_all_items(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            rows = root / "source-writes.json"
            report = root / "report.json"
            scanner.write_json(rows, [])
            scanner.write_json(root / "source-scan-coverage.json", coverage(
                [], inventorySha256=scanner.sha256(rows), parseFailures=[dict(sourcePath="bad.xml")],
                dynamicReview=[dict(sourcePath="unknown.as")],
                unsupportedSourceContainers=[dict(sourcePath="binary.fla")]))
            args = ["gate", "--inventory", str(rows), "--report", str(report), "--require-complete-coverage"]
            stdout = io.StringIO()
            with patch.object(sys, "argv", args), contextlib.redirect_stdout(stdout):
                self.assertEqual(3, gate.main())
            receipt = json.loads(report.read_text(encoding="utf-8"))
        self.assertTrue(receipt["boundedWriterGatePassed"])
        self.assertFalse(receipt["strictCoveragePassed"])
        self.assertEqual(3, receipt["coverageUnresolved"])
        self.assertEqual(3, json.loads(stdout.getvalue())["coverageUnresolved"])
        for field in gate.COVERAGE_FIELDS:
            self.assertEqual(1, len(receipt["coverage"][field]))


def minimal_swf():
    def tag(code, body):
        return struct.pack("<H", code * 64 + len(body)) + body

    body = b"\0" + struct.pack("<HH", 30 * 256, 1)
    body += tag(56, b"\x01\0\x01\0anchor\0")
    body += tag(57, b"parent.swf\0\x01\0\x02\0imported\0")
    body += tag(12, b"\x07\0")  # Stop
    body += tag(0, b"")
    return b"FWS\x08" + struct.pack("<I", len(body) + 8) + body


class PublishTests(unittest.TestCase):
    def test_binary_export_import_names_and_script_count(self):
        container = avm1_container(minimal_swf())
        self.assertEqual(1, container["actionBlocks"])
        self.assertEqual([dict(characterId=1, name="anchor")], container["exports"])
        self.assertEqual([dict(characterId=2, name="imported", url="parent.swf")], container["imports"])
        with self.assertRaises(ValueError):
            avm1_container(minimal_swf()[:-1])

    def test_source_edited_and_swf_stale_or_disagreeing(self):
        swf = "library.swf"
        source = "library/LIBRARY/anchor.xml"
        target = dict(sourceFiles=[source], anchors=["anchor"], preCleanupSha256="other",
                      exportNamesSha256=publish.names_hash(["anchor"]),
                      importNamesSha256=publish.names_hash([["parent.swf", "imported"]]))
        options = dict(java="java", jar=Path("ffdec.jar"))

        def export_fixture(java, jar, snapshot, directory, fmt):
            exports = directory / "export" / "unreviewed_sprite"
            exports.mkdir(parents=True)
            body = "stop();" if fmt == "as" else "Stop"
            (exports / ("script." + fmt)).write_text(body, encoding="utf-8")
            return dict(format=fmt)

        with tempfile.TemporaryDirectory() as temp, patch.object(publish, "export_scripts", export_fixture):
            root = Path(temp)
            (root / source).parent.mkdir(parents=True)
            (root / source).write_text("<x><script>_root.gameworld._y += 5;</script></x>", encoding="utf-8")
            (root / swf).write_bytes(minimal_swf())
            os.utime(root / swf, ns=(1_000_000_000, 1_000_000_000))
            work = root / "stale"
            work.mkdir()
            first = publish.verify_target(root, swf, target, work, **options)
            (root / source).write_text("<x><script>stop();</script></x>", encoding="utf-8")
            os.utime(root / source, ns=(1_000_000_000, 1_000_000_000))
            clean = root / "clean"
            clean.mkdir()
            passed = publish.verify_target(root, swf, target, clean, **options)
        self.assertEqual({"source_newer_than_swf", "source_global_transform_writes",
                          "source_and_swf_camera_scan_disagree"}, {row["reason"] for row in first["failures"]})
        self.assertEqual([], passed["failures"])

    def test_all_exports_include_unlisted_source_only_symbol_and_pcode(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            for fmt, script in (
                ("as", "_root.gameworld._y += 5;"),
                ("pcode", 'ConstantPool "_root", "gameworld", "_y"\nPush constant0\nGetVariable\n'
                          'Push constant1\nGetMember\nPush constant2, 5\nSetMember'),
            ):
                directory = folder / fmt / "export" / "DefineSprite_99999_source_only"
                directory.mkdir(parents=True)
                (directory / ("clip." + fmt)).write_text(script, encoding="utf-8")
            writes, _, failures = publish.inspect_exports("lady.swf", folder,
                [dict(format=fmt) for fmt in publish.FORMATS], 1)
        self.assertEqual([], failures)
        self.assertEqual({"as": 1, "pcode": 1}, {fmt: len(rows) for fmt, rows in writes.items()})
        self.assertEqual("source_and_swf_camera_scan_disagree", publish.write_failures([], writes)[-1]["reason"])

    def test_long_clip_export_paths_are_included_in_both_formats(self):
        with tempfile.TemporaryDirectory() as temp, contextlib.ExitStack() as cleanup:
            folder = Path(temp)
            for fmt in publish.FORMATS:
                root = publish.windows_long_path(folder / fmt / "export")
                directory = root / ("sprite_" + "a" * 95) / ("frame_" + "b" * 95) / ("clip_" + "c" * 75)
                directory.mkdir(parents=True)
                cleanup.callback(shutil.rmtree, root)
                (directory / ("action." + fmt)).write_text("Stop", encoding="utf-8")
            _, _, failures = publish.inspect_exports("library.swf", folder,
                [dict(format=fmt) for fmt in publish.FORMATS], 1)
        self.assertEqual([], failures)


if __name__ == "__main__":
    unittest.main()
