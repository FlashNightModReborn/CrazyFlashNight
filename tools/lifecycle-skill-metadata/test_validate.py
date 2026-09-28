import tempfile
from pathlib import Path
import subprocess
import unittest

from validate import validate, verify_baseline, without_metadata


class MetadataValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write("data/items/list.xml", "<root><items>test.xml</items></root>")
        self.write("data/items/equipment_mods/list.xml", "<root><items>test.xml</items></root>")
        self.write("data/items/equipment_mods/test.xml", "<root><mod><name>mod</name></mod></root>")
        self.item("<lifecycle><attr_0><skillInteraction>independent</skillInteraction>"
                  "<init><initRoutines>AnimationInit</initRoutines></init></attr_0></lifecycle>")

    def write(self, source, content):
        path = self.root / source
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def item(self, body):
        self.write("data/items/test.xml", f"<root><item><name>gun</name>{body}</item></root>")

    def test_root_skill_and_subweapon_do_not_reclassify_independent_animation(self):
        self.item("<skill><skillname>BuiltIn</skillname><skillLocked>true</skillLocked></skill>"
                  "<subweapon/><lifecycle><attr_0><skillInteraction>independent</skillInteraction>"
                  "<cycle><cycleRoutines>Animation</cycleRoutines></cycle></attr_0></lifecycle>")
        result = validate(self.root)
        self.assertTrue(result["ok"], result["errors"])
        self.assertEqual(result["counts"], {"independent": 1})

    def test_missing_tier_metadata_fails_even_when_base_is_complete(self):
        self.item("<lifecycle><attr_0><skillInteraction>independent</skillInteraction></attr_0></lifecycle>"
                  "<data_ice_gold_stolen><lifecycle><attr_0><init/></attr_0></lifecycle></data_ice_gold_stolen>")
        result = validate(self.root)
        self.assertFalse(result["ok"])
        self.assertEqual(result["bindingCount"], 2)
        self.assertTrue(any("data_ice_gold_stolen" in error for error in result["errors"]))

    def test_each_attr_and_registered_mod_is_checked(self):
        self.write("data/items/equipment_mods/test.xml", "<root><mod><name>mod</name><lifecycle>"
                   "<attr_0><skillInteraction>independent</skillInteraction></attr_0>"
                   "<attr_1><init/></attr_1></lifecycle></mod></root>")
        result = validate(self.root)
        self.assertFalse(result["ok"])
        self.assertEqual(result["bindingCount"], 3)
        self.assertTrue(any("mod/root/lifecycle/attr_1" in error for error in result["errors"]))

    def test_unknown_duplicate_and_misplaced_values_fail(self):
        cases = ["<skillInteraction>unknown</skillInteraction>",
                 "<skillInteraction>independent</skillInteraction><skillInteraction>managed</skillInteraction>",
                 "<init><skillInteraction>independent</skillInteraction></init>",
                 "<skillInteraction extra='x'>independent</skillInteraction>",
                 "<skillInteraction> independent </skillInteraction>"]
        for case in cases:
            with self.subTest(case=case):
                self.item(f"<lifecycle><attr_0>{case}</attr_0></lifecycle>")
                self.assertFalse(validate(self.root)["ok"])

    def test_fallback_requires_direct_skill_and_independent_cannot_provide_it(self):
        for value, skill, valid in [("fallback", "<skill><skillname>Default</skillname></skill>", True),
                                    ("fallback", "", False), ("independent", "<skill/>", False)]:
            with self.subTest(value=value, skill=skill):
                self.item(f"<lifecycle><attr_0><skillInteraction>{value}</skillInteraction>"
                          f"{skill}</attr_0></lifecycle>")
                self.assertEqual(validate(self.root)["ok"], valid)

    def test_only_registered_sources_are_in_scope(self):
        self.write("data/items/unregistered.xml", "not XML")
        self.assertTrue(validate(self.root)["ok"])
        self.write("data/items/list.xml", "<root><items>absent.xml</items></root>")
        self.assertFalse(validate(self.root)["ok"])

    def test_mod_composition_requires_an_independent_executable_binding(self):
        valid = ("<skillInteraction>independent</skillInteraction>"
                 "<init><initRoutines>LightInit</initRoutines></init>")
        cases = [(valid, True), (valid.replace("independent", "managed"), False),
                 (valid + "<setGate/>", False), ("<skillInteraction>independent</skillInteraction>", False),
                 (valid + "<init><initRoutines>OtherInit</initRoutines></init>", False)]
        for body, expected in cases:
            with self.subTest(body=body):
                self.write("data/items/equipment_mods/test.xml", "<root><mod><name>mod</name>"
                           f"<lifecycle><attr_0>{body}</attr_0></lifecycle></mod></root>")
                self.assertEqual(validate(self.root)["ok"], expected)

    def test_nested_mod_lifecycle_cannot_silently_pass_as_supported(self):
        self.write("data/items/equipment_mods/test.xml", "<root><mod><name>mod</name><stats><useSwitch>"
                   "<use><lifecycle><attr_0><skillInteraction>independent</skillInteraction>"
                   "<cycle><cycleRoutines>LightTick</cycleRoutines></cycle></attr_0></lifecycle></use>"
                   "</useSwitch></stats></mod></root>")
        self.assertTrue(any("top-level" in error for error in validate(self.root)["errors"]))

    def test_malformed_xml_and_duplicate_registry_fail(self):
        self.write("data/items/test.xml", "<root>")
        self.assertFalse(validate(self.root)["ok"])
        self.write("data/items/list.xml", "<root><items>test.xml</items><items>test.xml</items></root>")
        self.assertTrue(any("duplicate" in error for error in validate(self.root)["errors"]))

    def test_metadata_removal_preserves_bom_comments_eol_and_other_values(self):
        before = b'\xef\xbb\xbf<root>\r\n  <!-- retained -->\r\n  <power>3</power>\r\n</root>\r\n'
        after = before.replace(b'  <power>', b'  <skillInteraction>independent</skillInteraction>\r\n  <power>')
        self.assertEqual(without_metadata(after), before)
        self.assertNotEqual(without_metadata(after.replace(b'>3<', b'>4<')), before)
        self.assertNotEqual(without_metadata(after.replace(b'\r\n', b'\n')), before)

    def test_git_baseline_rejects_gameplay_and_registry_changes(self):
        def git(*args):
            subprocess.run(["git", *args], cwd=self.root, check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        git("init", "-q")
        git("config", "core.autocrlf", "false")
        original = b'<root>\r\n  <power>3</power>\r\n</root>\r\n'
        path = self.root / "data/items/test.xml"
        path.write_bytes(original)
        git("add", "data")
        git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture")
        changed = original.replace(b'  <power>', b'  <skillInteraction>independent</skillInteraction>\r\n  <power>')
        path.write_bytes(changed)
        self.assertEqual(verify_baseline(self.root, "HEAD", ["data/items/test.xml"]), [])
        path.write_bytes(changed.replace(b'>3<', b'>4<'))
        self.assertTrue(verify_baseline(self.root, "HEAD", ["data/items/test.xml"]))
        path.write_bytes(changed)
        self.write("data/items/list.xml", "<root><items>removed.xml</items></root>")
        self.assertTrue(verify_baseline(self.root, "HEAD", ["data/items/test.xml"]))


if __name__ == "__main__":
    unittest.main()
