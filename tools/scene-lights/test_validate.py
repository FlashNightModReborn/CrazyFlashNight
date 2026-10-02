import copy
import importlib.util
import json
from pathlib import Path
import unittest

SPEC=importlib.util.spec_from_file_location('scene_validate',Path(__file__).with_name('validate.py'))
V=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(V)
PRESETS=json.loads((V.ROOT/'data/environment/scene_lights.v1.json').read_text(encoding='utf-8-sig'))['presets']

class SceneLightValidationTests(unittest.TestCase):
    def test_live_candidate_references(self):
        rows=V.validate_tree();self.assertEqual(len(rows),7)
        self.assertIn(9,[r['lights'] for r in rows])
    def test_zero_energy_and_explicit_false_are_preserved(self):
        value=V.validate_record({'Key':'zero','Energy':0,'Enabled':False,'FollowScale':False},PRESETS)
        self.assertEqual(value['Energy'],0);self.assertFalse(value['Enabled'])
    def test_hybrid_requires_valid_constant_base(self):
        with self.assertRaises(ValueError):V.validate_record({'Key':'bad','Preset':'fire','BaseEnergy':2},PRESETS)
    def test_cached_cannot_animate(self):
        with self.assertRaises(ValueError):V.validate_record({'Key':'bad','Animation':'pulse'},PRESETS)
    def test_nonfinite_unknown_and_fractional_priority(self):
        for field,value in [('Energy',float('nan')),('Unexpected',1),('Priority',1.5)]:
            with self.subTest(field=field),self.assertRaises(ValueError):V.validate_record({'Key':'bad',field:value},PRESETS)
    def test_curve_must_be_ordered_and_bound(self):
        for curve in ['2:1,1:0','1:2','1:0,1:1']:
            with self.subTest(curve=curve),self.assertRaises(ValueError):V.validate_record({'Key':'bad','AttachTo':'lamp','FrameCurve':curve},PRESETS)
        with self.assertRaises(ValueError):V.validate_record({'Key':'bad','FrameCurve':'1:0'},PRESETS)
    def test_reference_paths_stay_in_bound_instance(self):
        with self.assertRaises(ValueError):V.validate_record({'Key':'bad','AttachTo':'lamp','Anchor':'_parent.lamp'},PRESETS)
    def test_color_formats_and_limits(self):
        self.assertEqual(V.color('#FFD39A'),0xffd39a);self.assertEqual(V.color('0xFFD39A'),0xffd39a)
        for value in ['#123','white',0x1000000]:
            with self.subTest(value=value),self.assertRaises(ValueError):V.color(value)

if __name__=='__main__':unittest.main()
