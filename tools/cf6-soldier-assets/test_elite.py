"""Read-only contracts for Alter-authored elite/instructor motion, equipment and ownership."""
from pathlib import Path
import copy
import json
import tempfile
import unittest
from lxml import etree as E
import elite

ROOT = Path(__file__).resolve().parents[2]
NS = elite.NS


class EliteContracts(unittest.TestCase):
    def test_script_sources_have_utf8_bom(self):
        sources = [
            'tools/cf6-soldier-assets/EliteAI.as',
            'tools/cf6-soldier-assets/SoldierAI.as',
            'tools/cf6-soldier-assets/SoldierRoles.as',
            'tools/cf6-soldier-assets/TacticalAI.as',
            'tools/cf6-soldier-assets/FixedActionAdapter.as',
            'tools/cf6-soldier-assets/FixedActionWeapons.as',
            'scripts/run-cf6-soldier-asset-tests.ps1',
            'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6SoldierAssetTest.as',
            'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ShootCore.as',
            'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/FireEventComponent.as',
            'scripts/逻辑/单位函数/单位函数_lsy_主角射击函数.as',
        ]
        for source in sources:
            with self.subTest(source=source):
                self.assertEqual((ROOT/source).read_bytes()[:3], b'\xef\xbb\xbf', source)

    def test_alter_motion_timeline_and_weapon_ownership(self):
        profile = elite.load_profile()
        poses = elite.motion_frames()
        self.assertEqual(len(poses), elite.TOTAL_FRAMES)
        self.assertEqual(elite.TOTAL_FRAMES, 216)

        retreat = profile['actions']['retreat']
        self.assertEqual((retreat['first'], retreat['last'], retreat['loopFirst'], retreat['loopLast'],
                          retreat['drawnFirst'], retreat['drawnLast']), (1, 89, 28, 51, 15, 75))
        self.assertEqual([e['frame'] for e in retreat['fireEvents']], [28, 29, 34, 35, 40, 41, 46, 47])

        run = profile['actions']['run']
        slide = profile['actions']['slide']
        self.assertEqual((run['first'], run['last'], run['loopFirst'], run['loopLast']), (90, 129, 100, 124))
        self.assertEqual((slide['first'], slide['last'], slide['slideStartFrame'], slide['slideEndFrame']),
                         (90, 180, 133, 165))
        self.assertEqual(len(run['fireEvents']), 8)
        self.assertEqual(len(slide['fireEvents']), 5)
        self.assertIn('fireEvents', elite.as2_literal(profile))

        # Drawn pistols appear ONLY during retreat f15-75; slung rifle covers f1-89 without colliding with man.枪.
        for idx, pose in enumerate(poses):
            frame = idx + 1
            ids = [row['id'] for row in pose.values()]
            if 1 <= frame <= 89:
                self.assertEqual(ids.count('slungRifle'), 1, f'frame {frame} slungRifle')
                self.assertNotIn(492, ids, f'frame {frame} must not mount active rifle')
                drawn = 15 <= frame <= 75
                self.assertEqual(ids.count('primaryPistol'), 1 if drawn else 0, f'frame {frame} primaryPistol')
                self.assertEqual(ids.count(506), 1 if drawn else 0, f'frame {frame} sidearm')
            else:
                self.assertNotIn('slungRifle', ids, f'frame {frame} slungRifle')
                self.assertNotIn('primaryPistol', ids, f'frame {frame} primaryPistol')
                self.assertNotIn(506, ids, f'frame {frame} preview pistol leaked')
                self.assertEqual(ids.count(492), 1, f'frame {frame} active rifle')

        # Embedded slide FX appear on exact authored ranges with smoke17 firstFrame progression.
        smoke_frames = [i + 1 for i, pose in enumerate(poses) if any(r['id'] == 'smoke17' for r in pose.values())]
        speed_frames = [i + 1 for i, pose in enumerate(poses) if any(r['id'] == 'speedLines' for r in pose.values())]
        self.assertEqual(smoke_frames, list(range(134, 172)))
        self.assertEqual(speed_frames, list(range(133, 153)))
        smoke_firsts = [next(r['firstFrame'] for r in poses[f - 1].values() if r['id'] == 'smoke17') for f in smoke_frames]
        self.assertEqual(smoke_firsts[:18], list(range(18)))
        self.assertEqual(smoke_firsts[18:], list(range(20)))

    def test_review_contact_sheet_executes(self):
        import render_elite_review
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            for name, color in [('46.png', '#ff0000'), ('21.png', '#00ff00')]:
                render_elite_review.Image.new('RGB', (40, 60), color).save(source/name)
            output = Path(directory)/'contact.png'
            render_elite_review.contact_sheet('contact', [source/'46.png', source/'21.png'], output)
            with render_elite_review.Image.open(output) as image:
                self.assertEqual(image.size, (1600, 155))

    def test_panels_and_explicit_sidearm_module(self):
        units = json.loads((ROOT/'data/units/units.json').read_text(encoding='utf-8-sig'))
        tuning = json.loads((Path(__file__).parent/'elite-tuning.json').read_text(encoding='utf-8-sig'))
        self.assertEqual(tuning['inheritedPanelExcept'], ['韧性系数'])
        self.assertIn(tuning['toughnessCoefficient'], range(50, 101))
        self.assertEqual(tuning['sidearmModule']['item'], 'FR506')
        self.assertEqual(len({u['id'] for u in units}), len(units))
        properties = E.parse(str(ROOT/'data/enemy_properties/CF6重制敌人.xml'))
        for old, new in ((466, 478), (467, 479)):
            base = next(u for u in units if u['id'] == old)
            derived = next(u for u in units if u['id'] == new)
            for key in ('level', 'height', 'is_hostile'):
                self.assertEqual(base[key], derived[key], key)
            expected = copy.deepcopy(base['data'])
            expected['secondary'] = expected['secondary2'] = 'FR506'
            self.assertEqual(derived['data'], expected)
            a = copy.deepcopy(properties.getroot().find(base['spritename']))
            b = copy.deepcopy(properties.getroot().find(derived['spritename']))
            a.tag = b.tag = 'unit'; a.tail = b.tail = None
            a.find('displayname').text = b.find('displayname').text = 'name'
            self.assertEqual(float(b.find('韧性系数').text), tuning['toughnessCoefficient'])
            self.assertEqual(float(a.find('韧性系数').text), 5)
            b.find('韧性系数').text = a.find('韧性系数').text
            self.assertEqual(E.tostring(a), E.tostring(b))

    def test_shared_reactions_and_receivers_with_separate_attacks(self):
        owner = ROOT/'flashswf/arts/new/Codex特种兵素材/LIBRARY'
        for source, derived in zip(('敌人-CF6特种兵', '敌人-CF6持盾特种兵'), elite.LINKAGES):
            a = E.parse(str(owner/('Codex/特种兵/'+source+'.xml')))
            b = E.parse(str(owner/('Codex/特种兵/'+derived+'.xml')))
            receiver = './/x:DOMLayer[@name="受击包围盒"]'
            self.assertEqual(E.tostring(a.find(receiver, NS)), E.tostring(b.find(receiver, NS)))
            for frame in a.findall('.//x:DOMLayer[@name="动作"]/x:frames/x:DOMFrame', NS):
                index = frame.get('index')
                if index in ('41', '180'):
                    continue
                other = b.find('.//x:DOMLayer[@name="动作"]/x:frames/x:DOMFrame[@index="'+index+'"]', NS)
                if index == '202':
                    self.assertEqual(E.tostring(frame.find('x:elements', NS)), E.tostring(other.find('x:elements', NS)), 'ordinary appearance state 202')
                else:
                    self.assertEqual(E.tostring(frame), E.tostring(other), 'ordinary appearance state '+index)
            for index in ('130', '140', '160', '190', '194', '202'):
                frame = './/x:DOMLayer[@name="动作"]/x:frames/x:DOMFrame[@index="'+index+'"]'
                if index == '202':
                    self.assertEqual(E.tostring(a.find(frame+'/x:elements', NS)), E.tostring(b.find(frame+'/x:elements', NS)))
                else:
                    self.assertEqual(E.tostring(a.find(frame, NS)), E.tostring(b.find(frame, NS)))

    def test_legacy_art_cannot_execute_legacy_combat(self):
        library = ROOT/'flashswf/arts/new/Codex特种兵素材/LIBRARY'
        self.assertFalse(list((library/'Codex/特种兵/精英/原生').rglob('*.xml')))
        action = E.parse(str(library/'Codex/特种兵/精英/动作/CF6战术长枪.xml'))
        refs = {x.get('libraryItemName') for x in action.findall('.//x:DOMSymbolInstance', NS)}
        self.assertTrue(all(
            x.startswith('Codex/特种兵/分件/') or x.startswith('Codex/特种兵/武器/')
            or x.startswith('Codex/特种兵/精英/武器/')
            or x.startswith('Codex/特种兵/特效/')
            or x == 'Codex/特种兵/装备/腿挂匕首' for x in refs
        ), refs)
        knife = E.parse(str(library/'Codex/特种兵/装备/腿挂匕首.xml'))
        self.assertEqual({x.get('libraryItemName') for x in knife.findall('.//x:DOMSymbolInstance', NS)},
                         {'Codex/特种兵/分件/484'})
        self.assertNotIn('FR-506 12.7MM', refs)
        root = E.parse(str(library/'Codex/特种兵/敌人-CF6特种精英.xml'))
        text = '\n'.join(s.text or '' for s in root.findall('.//x:script', NS))
        self.assertNotIn('空手攻击力 * 2.5', text)
        self.assertNotIn('空手攻击力 * 5', text)
        self.assertNotIn('刚体=true', text)
        self.assertNotIn('开始混合手枪换弹', text)
        self.assertIn('清理射击任务(this,true)', text)
        self.assertIn('手枪射击=function', text)
        self.assertIn('初始化混合双枪', text)
        self.assertIn('手枪2射击=function', text)
        self.assertIn('eliteMotionConfig', text)

    def test_instructor_toughness_and_mirrored_sfx(self):
        tuning = json.loads((Path(__file__).parent/'instructor-tuning.json').read_text(encoding='utf-8-sig'))
        self.assertEqual(tuning['toughnessCoefficient'], 50)
        properties = E.parse(str(ROOT/'data/enemy_properties/CF6重制敌人.xml'))
        for link in ('敌人-CF6特种教官', '敌人-CF6持盾特种教官'):
            node = properties.getroot().find(link)
            self.assertEqual(float(node.find('韧性系数').text), 50.0, link)
        library = ROOT/'flashswf/arts/new/Codex特种兵素材/LIBRARY'
        mirrored = 0
        for src in sorted((library/'Codex/特种兵/动作').glob('*.xml')):
            src_layer = E.parse(str(src)).find('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer[@name="原生SFX调用"]', NS)
            if src_layer is None:
                continue
            dst = library/'Codex/教官/动作'/('教官_'+src.name)
            dst_layer = E.parse(str(dst)).find('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer[@name="原生SFX调用"]', NS)
            self.assertIsNotNone(dst_layer, dst.name)
            self.assertEqual(E.tostring(src_layer), E.tostring(dst_layer), dst.name)
            mirrored += sum(1 for n in dst_layer.findall('.//x:script', NS) if n.text)
        self.assertEqual(mirrored, 9)


if __name__ == '__main__':
    unittest.main()
