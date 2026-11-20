"""Regression coverage for the reviewed A-Corps animated placement."""
import copy
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image


spec = importlib.util.spec_from_file_location("dressup_test_baker", Path(__file__).with_name("bake-dressup-offline.py"))
baker = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = baker
spec.loader.exec_module(baker)

IDENTITY = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]


class PlacementTests(unittest.TestCase):
    def setUp(self):
        self.target = ET.fromstring('<item type="PlaceObject3Tag" characterId="77" depth="1" '
            'placeFlagHasCharacter="true" placeFlagHasFilterList="true"><surfaceFilterList>'
            '<item type="COLORMATRIXFILTER"><matrix/></item></surfaceFilterList></item>')
        self.matrix = self.target.find("./surfaceFilterList/item/matrix")
        for value in IDENTITY:
            ET.SubElement(self.matrix, "item").text = str(value)
        self.matrix[0].text = "0"
        self.other = ET.fromstring('<item type="PlaceObject2Tag" characterId="88" depth="8" placeFlagHasCharacter="true"/>')
        self.tags = [self.target, self.other, ET.fromstring('<item type="ShowFrameTag"/>')]
        self.layer = {"characterId": 77, "path": [50, 77], "layers": []}

    def effect(self, parent=50, controls=None):
        self.layer["path"] = [parent, 77]
        return baker.reviewed_body_effect({parent: {"frameCount": 1, "placementTags": self.tags,
                                                   "children": [77, 88]}},
                                         parent, [self.layer], "a" * 64, controls or {})

    def test_no_effect_and_identity(self):
        self.matrix[0].text = "1"
        self.assertIsNone(self.effect())
        self.target.remove(self.target.find("surfaceFilterList"))
        self.target.set("placeFlagHasFilterList", "false")
        self.assertIsNone(self.effect())

    def test_pixel_alpha_and_uri_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            original = root / "original.png"
            Image.new("RGBA", (3, 2), (20, 30, 40, 77)).save(original)

            def render(effect):
                return baker.exported_frame_entries([original, original], root, "skins", "body_layer77",
                                                     False, placement_effect=effect)

            first = render(self.effect())
            self.assertEqual(first, render(self.effect()))
            self.assertEqual(first[0]["uri"], first[1]["uri"])
            self.assertEqual(first[1]["duplicateOfFrame"], 1)
            with Image.open(root / Path(first[0]["uri"]).name) as image:
                self.assertEqual(image.getpixel((0, 0)), (0, 30, 40, 77))
            self.assertNotEqual(first[0]["uri"], render(self.effect(51))[0]["uri"])
            self.assertNotEqual(first[0]["uri"], render(dict(self.effect(), sourceSha256="b" * 64))[0]["uri"])
            self.matrix[4].text = "5"
            self.assertNotEqual(first[0]["uri"], render(self.effect())[0]["uri"])
            untouched = render(None)
            self.assertEqual((root / Path(untouched[0]["uri"]).name).read_bytes(), original.read_bytes())

    def test_rejects_unknown_or_multiple_filters(self):
        filters = self.target.find("surfaceFilterList")
        extra = ET.SubElement(filters, "item", {"type": "GLOWFILTER"})
        with self.assertRaisesRegex(ValueError, "one ColorMatrix"):
            self.effect()
        filters.remove(extra)
        filters[0].set("type", "BLURFILTER")
        with self.assertRaisesRegex(ValueError, "one ColorMatrix"):
            self.effect()

    def test_rejects_alpha_or_malformed_matrix(self):
        for index in (3, 8, 13, 15, 16, 17, 18, 19):
            old = self.matrix[index].text
            self.matrix[index].text = "3"
            with self.subTest(index=index), self.assertRaisesRegex(ValueError, "alpha"):
                self.effect()
            self.matrix[index].text = old
        self.matrix[2].text = "NaN"
        with self.assertRaisesRegex(ValueError, "invalid SWF"):
            self.effect()
        self.matrix.remove(self.matrix[2])
        with self.assertRaisesRegex(ValueError, "invalid SWF"):
            self.effect()

    def test_rejects_masks_moves_and_repeated_instances(self):
        with self.assertRaisesRegex(ValueError, "script-controlled sprite 77"):
            self.effect(controls={77: {"clipActions": [{"script": "this._visible = false;"}]}})
        for flag in ("placeFlagHasColorTransform", "placeFlagHasClipDepth", "placeFlagHasVisible",
                     "placeFlagHasClipActions", "placeFlagHasBlendMode", "placeFlagMove"):
            self.target.set(flag, "true")
            with self.subTest(flag=flag), self.assertRaises(ValueError):
                self.effect()
            self.target.attrib.pop(flag)
        self.other.set("placeFlagHasClipDepth", "true")
        with self.assertRaisesRegex(ValueError, "ClipDepth"):
            self.effect()
        self.other.attrib.pop("placeFlagHasClipDepth")
        extra = copy.deepcopy(self.target)
        extra.set("depth", "9")
        self.tags.insert(1, extra)
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            self.effect()
        self.tags[1] = ET.fromstring('<item type="RemoveObject2Tag" depth="1"/>')
        with self.assertRaisesRegex(ValueError, "control tag"):
            self.effect()


class PublishedBodyTests(unittest.TestCase):
    def test_source_fingerprint_and_blue_grey_ribbon_hold(self):
        root = Path(__file__).resolve().parents[1]
        assets = root / "launcher/web/assets/dressup"
        skins = json.loads((assets / "manifest.json").read_bytes())["skinKeys"]
        for key in sorted(baker.REVIEWED_BODY_EFFECT_KEYS):
            with self.subTest(key=key):
                entry = skins[key]
                layer, = entry["export"]["nestedAnimation"]["layers"]
                effect = layer["bakedPlacementEffect"]
                self.assertEqual(effect["sourceSha256"], hashlib.sha256((root / entry["asset"]["swf"]).read_bytes()).hexdigest())
                self.assertEqual(effect["path"], layer["path"])
                self.assertEqual([f["durationFrames"] for f in layer["timelineFrames"]], [3] * 6)
                self.assertEqual(len(layer["frames"]), 18)
                for frame in layer["timelineFrames"]:
                    self.assertRegex(frame["uri"], r"__[a-f0-9]{20}\.png$")
                    with Image.open(assets / frame["uri"]) as image:
                        colors = image.convert("RGBA").getcolors(image.width * image.height)
                    opaque = sorted(((n, p[:3]) for n, p in colors if p[3] == 255), reverse=True)
                    self.assertEqual([rgb for _, rgb in opaque[:2]], [(40, 49, 61), (3, 8, 14)])


if __name__ == "__main__":
    unittest.main()
