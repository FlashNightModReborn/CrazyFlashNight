#!/usr/bin/env python3
import hashlib
import html
import json
import math
import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

import build_cf6_web_content as build


class Cf6WebContentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = build.read_json(build.CONTENT_JSON)
        cls.fragment = build.read_json(build.FRAGMENT)
        cls.manifest = build.read_json(build.MIRROR / "manifest.json")
        cls.audit = build.read_json(build.MIRROR / "integrity-audit.json")
        cls.pages = {page["id"]: page for page in cls.content["pages"]}
        cls.segments = {segment["id"]: segment for segment in cls.fragment["segments"]}

    def test_all_segments_pages_and_original_text_are_present(self):
        self.assertEqual(list(self.pages), [f"cf6-s{i}" for i in range(1, 8)] + ["cf6-end"])
        self.assertEqual(sum(len(page["panels"]) for page in self.pages.values()), 44)
        self.assertEqual(sum(len(self.pages[f"cf6-s{i}"]["panels"]) for i in range(1, 8)), 43)
        for page_id, page in self.pages.items():
            for panel in page["panels"]:
                self.assertTrue(panel["texts"], f"{page_id}/{panel['id']} has no visible original text")
                self.assertTrue(all(item["text"].strip() for item in panel["texts"]))
        self.assertEqual([len(panel["texts"]) for panel in self.pages["cf6-s2"]["panels"]], [7] * 8)
        self.assertEqual([len(panel["texts"]) for panel in self.pages["cf6-s1"]["panels"]], [1] * 4)
        self.assertEqual(len(self.pages["cf6-end"]["panels"][0]["texts"]), 19)
        self.assertTrue(self.pages["cf6-end"]["manual"])
        self.assertIsNone(self.pages["cf6-end"]["timeline"]["durationSec"])

    def test_vehicle_story_boundaries_and_finale_source_runtime_are_separate(self):
        self.assertEqual(self.fragment["routeMaps"],["TUTORIAL"]+[f"A{i:02d}" for i in range(1,21)])
        self.assertEqual(self.fragment["routeExclusions"],[])
        self.assertEqual(self.segments["cf6-s4"]["route"]["after"]["map"],"A07")
        self.assertEqual(self.segments["cf6-s5"]["route"]["before"]["map"],"A07")
        self.assertEqual(self.segments["cf6-s5"]["route"]["after"]["map"],"A08")
        self.assertEqual(self.segments["cf6-s6"]["route"]["after"]["map"],"A18")
        finale=self.segments["cf6-s7"]["route"]["before"]
        self.assertEqual((finale["sourceMap"],finale["runtimeRoom"],finale["runtimePhase"]),("A22","A20","second-form"))
        self.assertEqual(self.segments["cf6-s7"]["original"]["transition"]["targetLabel"],"end")
        self.assertIn("only actual A07 vehicle-tail completion",self.content["vehicleAdaptation"])
        self.assertNotIn("excluded",self.content["vehicleAdaptation"])

    def test_svg_text_viewports_and_references_match_sources(self):
        svg_ns = "{http://www.w3.org/2000/svg}"
        xlink = "{http://www.w3.org/1999/xlink}href"
        for segment_id, segment in self.segments.items():
            page = self.pages[segment_id]
            source_records = json.loads((build.ASSETS / segment_id / "texts.json").read_text(encoding="utf-8"))
            source_by_id = {record["charId"]: record for record in source_records}
            svg_path = build.MIRROR / segment_id / "comic.svg"
            root = ET.parse(svg_path).getroot()
            first_canvas = segment["pages"][0]["canvasPx"]
            self.assertEqual(root.get("viewBox"), f"0 0 {first_canvas[0]:g} {first_canvas[1]:g}")
            ids = {element.get("id") for element in root.iter() if element.get("id")}
            for element in root.iter():
                reference = element.get(xlink, "")
                if reference.startswith("#"):
                    self.assertIn(reference[1:], ids)
                elif reference:
                    self.assertTrue(reference.startswith("data:image/"), reference[:100])
                for value in element.attrib.values():
                    for target in re.findall(r"url\(#([^\)]+)\)", value):
                        self.assertIn(target, ids)
            text_nodes = {}
            for element in root.iter(svg_ns + "text"):
                char_id = int(element.get("data-cf6-char-id"))
                lines = [(node.text or "") for node in element.findall(svg_ns + "tspan")]
                text_nodes.setdefault(char_id, []).append(lines)
            self.assertEqual(set(text_nodes), set(source_by_id))
            for char_id, placements in text_nodes.items():
                expected_lines, _ = build.parse_edit_text(source_by_id[char_id])
                self.assertTrue(all(lines == expected_lines for lines in placements), f"text layout changed: {char_id}")
            self.assertEqual(len(segment["pages"]), len(page["panels"]))
            for source_panel, panel in zip(segment["pages"], page["panels"]):
                self.assertEqual(panel["rect"], source_panel["viewportRect"])
                self.assertEqual(panel["sourceVisual"], source_panel["visual"])
                self.assertEqual(panel["sourcePanPx"], source_panel["panPx"])
                self.assertEqual(panel["textTiming"], "unknown")
                self.assertEqual(len(panel["lines"]), 1)
                self.assertEqual(panel["lines"][0]["text"], "")
                rect = panel["rect"]
                self.assertTrue(0 <= rect[0] < 1 and 0 <= rect[1] < 1)
                self.assertTrue(0 < rect[2] <= 1 and 0 < rect[3] <= 1)
                for placed in panel["texts"]:
                    record = source_by_id[placed["charId"]]
                    self.assertEqual(placed["text"], html.unescape(record["plainText"]))
        credits = self.pages["cf6-end"]["panels"][0]["texts"]
        source_credits = json.loads((build.ASSETS / "cf6-end" / "texts.json").read_text(encoding="utf-8"))
        expected = [html.unescape(record["ffdecFormatted"][record["ffdecFormatted"].rfind("]") + 1:].strip()) for record in source_credits]
        self.assertEqual([record["text"] for record in credits], expected)
        credit_root = ET.parse(build.MIRROR / "cf6-end" / "credits.svg").getroot()
        self.assertEqual([node.text for node in credit_root.iter(svg_ns + "text")], expected)

    def test_frame_clock_and_narration_tail(self):
        for segment_id, segment in self.segments.items():
            page = self.pages[segment_id]
            original = segment["original"]
            advances = original["advance"]["stripFrames"]
            fps = original["fps"]
            expected = []
            for index in range(len(advances)):
                start = 0 if index == 0 else advances[index - 1]
                end = advances[index] if index < len(advances) - 1 else original["stripFrames"]
                expected.append(round((end - start) / fps, 4))
            self.assertEqual([panel["duration"] for panel in page["panels"]], expected)
            self.assertEqual(page["timeline"]["advanceFrames"], advances)
            self.assertEqual(page["timeline"]["stripFrames"], original["stripFrames"])
            self.assertAlmostEqual(sum(expected), original["stripFrames"] / fps, places=3)
            self.assertAlmostEqual(page["timeline"]["durationSec"], original["stripFrames"] / fps, places=3)
            self.assertGreaterEqual(expected[-1], page["panels"][-1]["fragmentDurationSec"])
            self.assertEqual(page["audio"]["textTiming"], "unknown")
            self.assertEqual(page["audio"]["synchronization"], "original-frame-clock-with-narration-start-offset")

    def test_original_narration_start_and_looping_music(self):
        for segment_id, segment in self.segments.items():
            expected_frame = 110 if segment_id == "cf6-s3" else 1
            narration = segment["audio"]["narration"]
            self.assertEqual(narration["firstAudioFrame"], expected_frame)
            self.assertAlmostEqual(narration["startSec"], (expected_frame - 1) / 30)
            self.assertAlmostEqual(self.pages[segment_id]["audio"]["narrationStartSec"], narration["startSec"])
            self.assertTrue(self.pages[segment_id]["audio"]["musicLoop"])
        self.assertTrue(self.pages["cf6-end"]["audio"]["musicLoop"])

    def test_fragment_preserves_same_frame_text_replacement_order(self):
        self.assertEqual([[text["charId"] for text in page["texts"]]
                          for page in self.segments["cf6-s1"]["pages"]],
                         [[1285], [1286], [1287], [1288]])

    def test_manifest_integrity_size_and_byte_exact_audio(self):
        files = self.manifest["files"]
        self.assertEqual(self.manifest["fileCount"], 18)
        self.assertEqual(len(files), 18)
        self.assertEqual(self.manifest["totalBytes"], sum(record["bytes"] for record in files))
        self.assertGreater(self.manifest["totalBytes"], 0)
        self.assertEqual(self.audit["totalBytes"], self.manifest["totalBytes"])
        actual_payload = {path.relative_to(build.MIRROR).as_posix(): path for path in build.MIRROR.rglob("*")
                          if path.is_file() and path.name not in ("manifest.json", "integrity-audit.json")}
        self.assertEqual(set(actual_payload), {record["path"] for record in files})
        for record in files:
            data = actual_payload[record["path"]].read_bytes()
            self.assertEqual(len(data), record["bytes"])
            self.assertEqual(hashlib.sha256(data).hexdigest(), record["sha256"])
        self.assertEqual(self.audit["maxFileBytes"], max(record["bytes"] for record in files))
        for copied in self.audit["byteExactCopies"]:
            source = (build.ASSETS / copied["source"]).read_bytes()
            mirror = (build.MIRROR / copied["mirror"]).read_bytes()
            self.assertEqual(mirror, source)
            self.assertEqual(hashlib.sha256(mirror).hexdigest(), copied["sha256"])
        for output in self.audit["generatedOutputs"]:
            path = build.REPO / output["path"]
            data = path.read_bytes()
            self.assertEqual(len(data), output["bytes"])
            self.assertEqual(hashlib.sha256(data).hexdigest(), output["sha256"])
        binding = self.manifest["sourceBinding"]
        for record in binding["scripts"]:
            self.assertEqual(hashlib.sha256((build.REPO / record["path"]).read_bytes()).hexdigest(), record["sha256"])
        for record in binding["assets"]:
            self.assertEqual(hashlib.sha256((build.ASSETS / record["path"]).read_bytes()).hexdigest(), record["sha256"])
        self.assertEqual(binding["originalSwfSha256"], self.fragment["source"]["sha256"])

    def test_illegal_paths_are_rejected(self):
        illegal = [None, "", ".", "..", "../outside", "a/../../outside", "/absolute", "C:/absolute",
                   "a\\..\\outside", "a//b", "a/./b", "a/", "a\x00b"]
        for value in illegal:
            with self.subTest(value=value), self.assertRaises(build.BuildError):
                build.safe_relative(value)
        self.assertEqual(build.safe_relative("cf6-s1/comic.svg").as_posix(), "cf6-s1/comic.svg")
        with self.assertRaises(build.BuildError):
            build.contained(build.MIRROR, "../outside")

    def test_as2_source_contract_is_static_only_not_avm1(self):
        scene = build.REPO / "scripts" / "类定义" / "org" / "flashNight" / "arki" / "scene"
        names = ["BookComicService.as", "BookComicServiceTest.as", "Cf6StoryService.as", "Cf6StoryServiceTest.as", "BookRunService.as"]
        sources = {}
        for name in names:
            data = (scene / name).read_bytes()
            self.assertTrue(data.startswith(b"\xef\xbb\xbf"), f"UTF-8 BOM missing: {name}")
            sources[name] = data.decode("utf-8-sig").replace("\r\n", "\n")
        router = sources["Cf6StoryService.as"]
        self.assertNotIn("_root.gameCommands", router)
        self.assertNotIn("book_comic_response", router)
        self.assertNotIn("PauseManager.lease", router)
        self.assertIn('if (index == 7) return ["cf6-s4"]', router)
        self.assertIn('if (index == 8) return ["cf6-s5"]', router)
        self.assertIn('if (index == 18) return ["cf6-s6"]', router)
        self.assertNotIn('if (index == 17)', router)
        self.assertIn('return beginSequence(["cf6-s7", "cf6-end"], continuation, interruption)', router)
        self.assertIn("BookComicService.begin", router)
        self.assertIn('finishSequence(state, "open_failed", "sequence", true)', router)
        shared = sources["BookComicService.as"]
        self.assertEqual(shared.count('sendTaskToNode("book_comic_response"'), 1)
        self.assertIn("BookRunRules.sameCf6Run", shared)
        self.assertIn("mayContinue", shared)
        self.assertIn("s.interruption", shared)
        run = sources["BookRunService.as"]
        self.assertIn("if (_ending.cf6Story) presentCf6Ending(); else persistOutcome();", run)
        self.assertIn("ending.cf6Story === true && ending.storyCompleted !== true", run)
        self.assertIn("BookRunRules.sameCf6Run(chapter.runIdentity", run)
        self.assertIn("chapter.started = true", run)
        self.assertIn("cf6ChapterInterruption(chapter)", run)
        self.assertIn("cf6EndingInterruption(ending)", run)
        self.assertIn("cf6EndingRetryCallback(ending)", run)
        self.assertIn("chapter.storyActive = true;\n                if (org.flashNight.arki.scene.Cf6StoryService.beginChapter", run)
        self.assertIn("ending.storyActive = true;\n        if (org.flashNight.arki.scene.Cf6StoryService.beginFinal", run)
        self.assertIn("|| _chapter !== chapter || chapter.started === true", run)
        self.assertNotIn("beginChapter(index, cf6Follow,\n                        cf6ChapterInterruption(chapter))) chapter.storyActive = true", run)
        tests = sources["Cf6StoryServiceTest.as"]
        self.assertIn("synchronous admission rejection cannot reactivate a retired chapter", tests)
        self.assertIn("synchronous ending expiry keeps victory unsettled and retryable", tests)
        self.assertIn("late old chapter continuation cannot delete the replacement watch or start its old room", tests)
        self.assertNotIn("SaveManager.getInstance().flushBeforeTransition", sources["Cf6StoryService.as"])


if __name__ == "__main__":
    print("CF6 static/source checks only; this is not AVM1, CS6, Host, or audible validation.")
    unittest.main(verbosity=2)
