from pathlib import Path
import copy
import unittest
import xml.etree.ElementTree as ET
from sky_filter import sky_effect

ROOT=Path(__file__).resolve().parents[3]
SOURCE=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图/A02-R3/cf6-stage2-redraw-r3/parts/bitmap-1595.svg'


class Contract(unittest.TestCase):
    def setUp(self):self.filters={n.get('id'):n for n in ET.parse(SOURCE).getroot().iter() if n.tag.split('}')[-1]=='filter'}
    def test_authored_cloud_graph_keeps_displacement_blur_and_disposal(self):
        script,report=sky_effect(self.filters['cloudsoft'])
        self.assertIn('DisplacementMapFilter',script);self.assertIn('BlurFilter(3.4,3.4,3)',script)
        self.assertIn('this.__cf6SkyNoise.dispose()',script);self.assertEqual(report['sourceSeed'],18)
    def test_authored_haze_uses_original_mask_and_bounded_runtime_surface(self):
        script,report=sky_effect(self.filters['haze'])
        self.assertIn('haze.setMask(content)',script);self.assertIn('width<=1024 && height<=512',script)
        self.assertEqual(report['sourceFrequency'],[.012,.045]);self.assertNotIn('_root',script)
    def test_changed_displacement_is_rejected(self):
        node=copy.deepcopy(self.filters['cloudsoft']);node[1].set('scale','11')
        with self.assertRaises(ValueError):sky_effect(node)
    def test_unreviewed_color_space_is_rejected(self):
        node=copy.deepcopy(self.filters['haze']);node.set('color-interpolation-filters','sRGB')
        with self.assertRaises(ValueError):sky_effect(node)


if __name__=='__main__':unittest.main()
