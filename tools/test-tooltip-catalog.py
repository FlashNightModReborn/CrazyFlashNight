#!/usr/bin/env python3
"""Source-derived catalog checks, not a claim of live AVM1 equivalence."""
import copy
import importlib.util
import json
import re
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

SPEC = importlib.util.spec_from_file_location("tooltip_catalog", Path(__file__).with_name("build-tooltip-catalog.py"))
catalog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(catalog)


class CatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data, cls.manifest = catalog.build()

    def test_xml_scalar_and_repeated_nodes(self):
        raw = '<r a="007"><x>0</x><x>-3.5</x><empty/><flag>TRUE</flag><word>tRuE</word><attr key="2"/></r>'
        self.assertEqual(catalog.xml_value(ET.fromstring(raw)),
                         {"a": 7, "x": [0, -3.5], "empty": "", "flag": True,
                          "word": "tRuE", "attr": {"key": 2}})
        self.assertEqual(catalog.scalar(" "), " ")
        self.assertEqual(catalog.xml_value(ET.fromstring('<r><x>  </x></r>')), {"x": ""})

    def test_description_decode_and_linebreaks(self):
        raw = '<r><Description>&amp;lt;b&amp;gt;甲&amp;lt;/b&amp;gt;\n乙</Description><description>&amp;lt;b&amp;gt;</description></r>'
        self.assertEqual(catalog.xml_value(ET.fromstring(raw)),
                         {"Description": "<b>甲</b>\n乙", "description": "&lt;b&gt;"})
        self.assertEqual(catalog.decode_html("&nbsp;&NewLine;&euro;&AMP;&amp;lt;&#65;&#x41;&#0;&#65536;"),
                         " \n&euro;&AMP;&lt;AA")
        source = (catalog.ROOT / "scripts/类定义/org/flashNight/gesh/string/StringUtils.as").read_text("utf-8-sig")
        authored = {name: json.loads(value) for name, value in re.findall(
            r'htmlEntities\["&([^";]+);"\]\s*=\s*("(?:\\.|[^"\\])*")', source)}
        self.assertEqual(catalog.HTML_ENTITIES, authored)

    def test_runtime_expression_cannot_become_static_fact(self):
        with self.assertRaisesRegex(ValueError, "CaseSwitch"):
            catalog.xml_value(ET.fromstring('<r><CaseSwitch expression="x"><Case value="1"/></CaseSwitch></r>'))

    def test_item_clone_view_reverses_objects_but_preserves_arrays(self):
        source = {"one": {"a": 1, "b": 2, "__cache": 9}, "two": [{"x": 3, "y": 4}, 5]}
        value = catalog.item_data_view(source)
        self.assertEqual(list(value), ["two", "one"])
        self.assertEqual(list(value["one"]), ["b", "a"])
        self.assertEqual(list(value["two"][0]), ["y", "x"])
        self.assertEqual(value["two"][1], 5)
        self.assertEqual(list(source["one"]), ["a", "b", "__cache"])
        self.assertEqual(list(self.data["items"]["金蛇剑"]["data"]["skillmultipliers"]),
                         ["龙斩", "瞬步斩", "拔刀术", "凶斩"])

    def test_mod_normalization_is_non_mutating_and_no_branch_selection(self):
        raw = {"name": "test", "provideTags": "电力, 导轨", "stats": {
            "percentage": {"power": 5}, "multiplier": {"damage": -20},
            "useSwitch": {"use": [{"name": "长枪", "percentage": {"power": 15}},
                                    {"flat": {"power": 9}}]}}}
        before = copy.deepcopy(raw)
        normalized = catalog.normalize_mod(raw)
        self.assertEqual(raw, before)
        self.assertEqual(normalized["stats"]["percentage"], {"power": 0.05})
        self.assertEqual(normalized["stats"]["multiplier"], {"damage": -0.2})
        cases = normalized["stats"]["useSwitch"]["useCases"]
        self.assertEqual(len(cases), 2)
        self.assertEqual(cases[0]["percentage"], {"power": 0.15})
        self.assertTrue(cases[1]["_isDefault"])
        self.assertEqual(normalized["provideTagDict"], {"电力": True, "导轨": True})

    def test_non_finite_or_non_numeric_percent_is_rejected(self):
        with self.assertRaises(ValueError):
            catalog.scalar("1e999")
        with self.assertRaises(ValueError):
            catalog.normalize_mod({"name": "bad", "stats": {"percentage": {"power": "oops"}}})

    def test_current_gray_goo_profiles_survive_normalization(self):
        mods = self.data["mods"]
        etch = mods["灰蛊蚀刻霰弹"]["stats"]["override"]["hitBehavior"]
        self.assertEqual((etch["type"], etch["delayFrames"], etch["detonationCrumble"]),
                         ("grayGooEtch", 54, 1))
        primer = mods["灰蛊裂隙弹"]["stats"]
        self.assertEqual(primer["override"]["hitBehavior"]["maxStacks"], 18)
        self.assertEqual([c["override"]["hitBehavior"]["profileId"]
                          for c in primer["useSwitch"]["useCases"]],
                         ["highPowerHandgun", "handgun"])

    def test_no_discovery_or_equipment_authority_is_baked(self):
        self.assertEqual(self.data["obtainRecords"], {})
        for item in self.data["items"].values():
            self.assertNotIn("balance", item)
            self.assertNotIn("id", item)
        self.assertNotIn("calculated", self.data)

    def test_duplicate_resolution_is_exposed_for_windows_confirmation(self):
        self.assertEqual({r["name"] for r in self.manifest["duplicateItems"]},
                         {"小F头部", "TheGirl头-NPC", "三戈戟二型"})
        self.assertEqual(self.data["items"]["小F头部"]["data"]["level"], 10)

    def test_reverse_recipe_index_is_distinct_and_utf16_sorted(self):
        for names in self.data["recipesUsing"].values():
            self.assertEqual(names, sorted(set(names), key=lambda s: s.encode("utf-16-be")))

    def test_manifest_binds_current_sources_and_bytes(self):
        self.assertEqual(self.manifest["outputSha256"], catalog.sha256(catalog.json_bytes(self.data)))
        self.assertGreater(len(self.manifest["sourceFiles"]), 100)
        for rel, digest in self.manifest["sourceFiles"].items():
            self.assertEqual(catalog.sha256((catalog.ROOT / rel).read_bytes()), digest, rel)
        self.assertEqual(json.loads((catalog.ROOT / catalog.OUTPUT).read_bytes()), self.data)


if __name__ == "__main__":
    unittest.main()
