"""Scene coverage and coordinate contracts; no shared outputs or game saves are written."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


bc = module('viewport_book_builder', 'build-chapter.py')
vp = module('viewport_under_test', 'viewport-assembly.py')


class ViewportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # r15: the A01 turret asset SWF is still pending the CS6 chain, so the
        # assembly fixture runs in the explicitly authorized allow-missing mode.
        # Strict mode is covered by test_turret_asset_gate_tracks_real_file.
        cls.outputs = bc.build(require_swfs=False)
        cls.chapter = json.loads(cls.outputs[bc.OUTPUT])
        cls.maps = {m['id']: m for m in cls.chapter['maps']}
        cls.env = {n.findtext('BackgroundURL'): n for n in ET.fromstring(cls.outputs[bc.ENVIRONMENT]).findall('Environment')}
        cls.runtime = {m['id']: m for m in bc.read(bc.TOOLS/'cf6-map-runtime/generated/runtime-index.json')['maps']}
        cls.native = bc.read(bc.TOOLS/'cf6-map-source/generated/map-input.json')['maps']

    def test_default_viewport_covered_for_all_21_maps(self):
        self.assertEqual(list(self.maps), vp.ROUTE)
        for mid in vp.ROUTE:
            env = self.env[Path(self.maps[mid]['background']).name]
            self.assertGreaterEqual(float(env.findtext('Width')), 1024)
            self.assertGreaterEqual(float(env.findtext('Height')), 512)
            self.assertAlmostEqual(self.maps[mid]['presentation']['scale'], 128/75)

    def test_actor_dimensions_and_build_are_unchanged(self):
        self.assertEqual(self.chapter['actor'], bc.read(bc.TOOLS/'cf6-actor-template/actor.fragment.json')['actor'])
        self.assertEqual(bc.read(vp.POLICY)['cameraBaseScale'], 1)

    def test_a02_native_origin_and_canvas_remove_exposed_padding(self):
        row = self.maps['A02']; env = self.env['CF6_A02_BG.swf']
        self.assertAlmostEqual(row['stage']['BasicInformation']['PlayerX'], 156.16, places=4)
        self.assertAlmostEqual(row['stage']['BasicInformation']['PlayerY'], 603.648, places=4)
        self.assertAlmostEqual(row['presentation']['backgroundX'], -74.1547, places=4)
        self.assertAlmostEqual(float(env.findtext('Width')), 1250*128/75, places=4)
        self.assertAlmostEqual(float(env.findtext('Height')), 450*128/75, places=4)

    def test_lift_art_mask_and_world_origin_share_one_scale(self):
        for mid in ('A10', 'A13'):
            layer = next(l for l in self.maps[mid]['mechanism']['layers'] if l['role'] == 'elevator-scroll')
            self.assertAlmostEqual(layer['x']+layer['clip'][0], 0, places=4)
            self.assertAlmostEqual(layer['y']+layer['clip'][1], 0, places=4)
            self.assertAlmostEqual(layer['clip'][2], 1024, places=4)
            self.assertAlmostEqual(layer['clip'][3], 350*128/75, places=4)
            self.assertAlmostEqual(layer['loopHeight'], 541.95*128/75, places=4)
            env = self.env['CF6_'+mid+'_BG.swf']
            self.assertAlmostEqual(float(env.findtext('Height')), layer['clip'][3], places=4)

    def test_root_sky_coordinates_are_not_rebased_as_world_points(self):
        layers = self.maps['A02']['mechanism']['layers']
        city = next(l for l in layers if l['role'] == 'city-parallax')
        sky = next(l for l in layers if l['role'] == 'screen-fixed')
        self.assertEqual((city['x'], city['y']), (0, 109))
        self.assertEqual((sky['x'], sky['y'], sky['width']), (0, 0, 600))

    def test_collision_and_exit_keep_the_same_original_coordinate_space(self):
        before = ET.parse(bc.TOOLS/'cf6-map-runtime/generated/environment.fragment.xml')
        original = next(n for n in before.findall('Environment') if n.findtext('BackgroundURL') == 'CF6_A02_BG.swf')
        after = self.env['CF6_A02_BG.swf']
        a = [float(v) for v in original.findtext('Collision/Point').split(',')]
        b = [float(v) for v in after.findtext('Collision/Point').split(',')]
        self.assertAlmostEqual(b[0], (a[0]-43.45)*128/75, places=4)
        self.assertAlmostEqual(b[1], (a[1]+24.1)*128/75, places=4)
        self.assertAlmostEqual(float(after.findtext('Door/x0')), 1200*128/75, places=4)

    def test_repeat_transform_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'applied twice'):
            vp.adapt(copy.deepcopy(self.chapter), self.outputs[bc.ENVIRONMENT], self.native)

    def test_changed_original_camera_source_is_rejected(self):
        actual = vp.read; layout = actual(vp.LAYOUT)
        layout['maps'][0]['decodedLoadSha256'] = '0'*64
        with patch.object(vp, 'read', lambda p: layout if p == vp.LAYOUT else actual(p)):
            with self.assertRaisesRegex(ValueError, 'camera script changed'):
                vp.load()

    def test_a01_turrets_scaled_once_into_mechanism(self):
        for mid, node in self.maps.items():
            if mid != 'A01':
                self.assertNotIn('turrets', node['mechanism'], mid + ' must not carry turrets')
        spec = self.maps['A01']['mechanism']['turrets']
        self.assertEqual(spec['assetUrl'], 'flashswf/backgrounds/cf6/CF6_A01_Turret.swf')
        self.assertEqual(spec['linkage'], 'CF6教学炮塔-A01自动炮')
        self.assertEqual(spec['filterMarker'], 'cf6-a01-turret-zombie')
        self.assertEqual(spec['fireIntervalFrames'], 18)
        self.assertEqual(spec['fireFrameOffset'], 11)
        # 原生两点 (133.8,202.4)/(249.8,430.9) 乘装配倍率 128/75 恰一次;
        # 实例名只进装配审计,运行时规格不带 name(服务 load 模式自命名 holder)。
        self.assertEqual([list(t) for t in spec['turrets']], [['x', 'y', 'facing']]*2)
        self.assertAlmostEqual(spec['turrets'][0]['x'], 228.352, places=4)
        self.assertAlmostEqual(spec['turrets'][0]['y'], 345.4293, places=4)
        self.assertAlmostEqual(spec['turrets'][1]['x'], 426.3253, places=4)
        self.assertAlmostEqual(spec['turrets'][1]['y'], 735.4027, places=4)
        self.assertEqual([t['facing'] for t in spec['turrets']], ['right', 'right'])
        audit = json.loads(self.outputs[bc.HERE/'generated/assembly.json'])['turretAssembly']
        self.assertEqual(audit['A01']['instances'][0]['native'], [133.8, 202.4])
        self.assertEqual(audit['A01']['instances'][1]['native'], [249.8, 430.9])
        self.assertAlmostEqual(audit['A01']['scale'], 128/75, places=9)

    def test_turret_asset_gate_tracks_real_file(self):
        # 资产存在门不做伪:SWF 未编译时严格模式必须拒绝,编译落地后必须通过。
        swf = bc.ROOT/'flashswf/backgrounds/cf6/CF6_A01_Turret.swf'
        if swf.is_file():
            bc.build(require_swfs=True)
        else:
            with self.assertRaisesRegex(ValueError, 'missing turret asset SWF'):
                bc.build(require_swfs=True)

    def test_invalid_asset_transform_rejected_by_chapter_validator(self):
        spec = importlib.util.spec_from_file_location('viewport_validation', bc.TOOLS/'build-book-definition.py')
        validator = importlib.util.module_from_spec(spec); spec.loader.exec_module(validator)
        from choice_reward_catalog import item_catalog
        skills = ET.parse(bc.ROOT/'data/skills/skills.xml').findall('Skill')
        units = {int(u['id']) for u in bc.read(bc.ROOT/'data/units/units.json')}
        bad = copy.deepcopy(self.chapter); bad['maps'][0]['presentation']['scale'] = 0
        with self.assertRaisesRegex(ValueError, 'presentation transform'):
            validator.validate_cf6(bad, item_catalog(), skills, units)


if __name__ == '__main__':
    unittest.main()
