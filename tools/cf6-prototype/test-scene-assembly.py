"""Coordinate and content boundaries; real Flash and character radius remain separate."""
import copy
import importlib.util
import json
import math
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


bc = module('cf6_chapter_under_test', HERE/'build-chapter.py')
scene = module('cf6_scene_under_test', HERE/'scene-assembly.py')
interactive = module('cf6_interactive_under_test', HERE/'interactive-assembly.py')
sys.path.insert(0, str(ROOT/'tools'))
book_validator = module('cf6_book_validator', ROOT/'tools/build-book-definition.py')
sys.path.insert(0, str(ROOT/'tools/cf6-map-runtime'))
import geometry


class SceneAssemblyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        assemble = bc.assemble_scenes
        def observed(chapter, environment_fragment, require_swfs):
            cls.before_scene = copy.deepcopy(chapter)
            result = assemble(chapter, environment_fragment, require_swfs)
            cls.after_scene = copy.deepcopy(chapter)
            return result
        with patch.object(bc, 'assemble_scenes', side_effect=observed):
            cls.outputs = bc.build(require_swfs=False)
        cls.chapter = json.loads(cls.outputs[bc.OUTPUT])
        cls.maps = {m['id']: m for m in cls.chapter['maps']}
        cls.envs = {e.findtext('BackgroundURL'): e for e in ET.fromstring(cls.outputs[bc.ENVIRONMENT])}
        cls.plan = scene.read(scene.PLAN)

    def test_original_timing_and_actor_release_survive(self):
        for source in self.plan['traversals']:
            actual = self.maps[source['mapId']]['mechanism']['traversal'][source['mode']]
            self.assertEqual(actual['durationFrames'], source['durationFrames'])
            self.assertEqual(actual['actorReleaseFrame'], source['actorReleaseFrame'])
            self.assertEqual([(r['frame'],r['action'],r['visible']) for r in actual['samples']],
                             [(r['frame'],r['action'],r['visible']) for r in source['samples']])

    def test_real_gate_is_standard_exit_not_remote_right_edge(self):
        for map_id in ('A03','A04','A05'):
            m = self.maps[map_id]
            gate = m['mechanism']['traversal']['depart']['gate']
            door = self.envs[Path(m['background']).name].find('Door')
            for value,low,high in ((gate['x'],'x0','x1'),(gate['z'],'y0','y1')):
                self.assertLess(float(door.findtext(low)), value)
                self.assertGreater(float(door.findtext(high)), value)
        self.assertLess(self.maps['A04']['mechanism']['traversal']['depart']['gate']['x'], 200)
        self.assertAlmostEqual(self.maps['A05']['mechanism']['traversal']['depart']['gate']['x'], 1119.8097)

    def test_post_elevator_original_exit_side_is_not_generic_right(self):
        a11=self.maps['A11'];a14=self.maps['A14']
        left=self.envs[Path(a11['background']).name].find('Door')
        right=self.envs[Path(a14['background']).name].find('Door')
        self.assertEqual(left.findtext('Direction'),'左')
        self.assertEqual(right.findtext('Direction'),'右')
        self.assertLess(float(left.findtext('x1')),a11['stage']['BasicInformation']['PlayerX'])
        self.assertGreater(float(right.findtext('x0')),a14['stage']['BasicInformation']['PlayerX'])
        self.assertLess(a11['mechanism']['guidePoint']['x'],a11['stage']['BasicInformation']['PlayerX'])
    def test_original_left_trigger_is_walkable_and_bound_to_source(self):
        stage=self.maps['A11'];env=self.envs[Path(stage['background']).name];door=env.find('Door')
        point=[(float(door.findtext('x0'))+float(door.findtext('x1')))/2,
               (float(door.findtext('y0'))+float(door.findtext('y1')))/2]
        polygons=[[[float(v) for v in p.text.split(',')] for p in col.findall('Point')] for col in env.findall('Collision')]
        self.assertFalse(any(geometry.point_inside(point,q) for q in polygons))
        self.assertAlmostEqual(float(door.findtext('x1')),91*stage['presentation']['scale'],places=3)
        source=scene.read(scene.ELEVATOR_EXIT_GEOMETRY)['geometry']
        self.assertEqual(next(p for p in source['display'] if p.get('id')==1617)['depth'],129)

    def test_control_return_points_are_in_actual_walkable_geometry(self):
        for m in self.chapter['maps']:
            if 'traversal' not in m['mechanism']:
                continue
            env = self.envs[Path(m['background']).name]
            bounds = [float(env.findtext(k)) for k in ('Xmin','Ymin','Xmax','Ymax')]
            polygons = [[list(map(float,p.text.split(','))) for p in col.findall('Point')]
                        for col in env.findall('Collision')]
            for mode,t in m['mechanism']['traversal'].items():
                # Source arrival releases before applying its invisible release-frame sample.
                p = [t['exit']['x'],t['exit']['z']] if mode=='depart' else [
                    t['samples'][(t['actorReleaseFrame']-2) if t['actorReleaseFrame'] else -1][key]
                    for key in ('x','z')]
                with self.subTest(map=m['id'],mode=mode):
                    self.assertTrue(bounds[0]<p[0]<bounds[2] and bounds[1]<p[1]<bounds[3])
                    self.assertFalse(any(geometry.point_inside(p,q) for q in polygons))

    def test_threshold_world_anchors_do_not_move_when_art_is_scaled(self):
        thresholds = {1720:87.55,1729:-26.45,1750:89.5}
        for source in self.plan['traversals']:
            m = self.maps[source['mapId']]
            layers = [l for l in m['mechanism']['layers'] if l.get('traversalMode')==source['mode']]
            for layer in layers:
                self.assertAlmostEqual(layer['y'],
                    (source['sourcePlacement'][5]+thresholds[source['sourceSprite']])*128/75, places=3)
                self.assertEqual(layer['pivot']['y'], thresholds[source['sourceSprite']])
                self.assertEqual(layer['visualScale'], 1.12 if source['sourceSprite']==1750 else 1)

    def test_cinematic_depth_is_separate_from_vertical_shoe_motion(self):
        for source in self.plan['traversals']:
            m = self.maps[source['mapId']]
            spec = m['mechanism']['traversal'][source['mode']]
            layers = [l for l in m['mechanism']['layers'] if l.get('traversalMode')==source['mode']]
            back = next(l for l in layers if l['id'].endswith('-back'))
            self.assertLess(back['sortY'],spec['actorSortY'])
            front = next((l for l in layers if l['id'].endswith('-front')),None)
            if front:
                self.assertGreater(front['sortY'],spec['actorSortY'])
            self.assertNotEqual(spec['samples'][0]['z'],spec['samples'][-1]['z'])

    def test_mask_activity_is_source_bound_and_empty_mask_is_absent(self):
        masks = [l for m in self.chapter['maps'] for l in m['mechanism']['layers'] if l['role']=='actor-mask']
        self.assertEqual(len(masks),4)
        for layer in masks:
            self.assertNotIn('1750',layer['url'])
            expected = list(range(136,175)) if '1720' in layer['url'] else list(range(1,40))
            self.assertEqual(layer['maskActiveFrames'],expected)

    def test_elevator_tracks_use_existing_standard_exit(self):
        for map_id in ('A10','A13'):
            m = self.maps[map_id]
            self.assertEqual(m['mechanism']['traversal']['arrive']['durationFrames'],30)
            d = m['mechanism']['traversal']['depart']
            self.assertEqual([d['samples'][-1]['x'],d['samples'][-1]['z']],[d['exit']['x'],d['exit']['z']])
            self.assertIn('adaptation',d['basis'])
            self.assertEqual([l['role'] for l in m['mechanism']['layers']],['elevator-scroll','foreground'])

    def test_choreography_rejects_duplicate_transform(self):
        with self.assertRaisesRegex(ValueError,'already assembled'):
            scene.adapt(copy.deepcopy(self.chapter),self.outputs[bc.ENVIRONMENT],False)

    def test_missing_mask_resource_cannot_pass_strict_asset_gate(self):
        asset = next(a for a in scene.read(scene.ART)['assets'] if a['name']=='CF6_Traversal1720_Mask')
        missing = ROOT/scene.art_url(asset)
        real_is_file = Path.is_file
        with patch.object(Path,'is_file',lambda p: False if p==missing else real_is_file(p)):
            with self.assertRaisesRegex(ValueError,'fresh CS6 traversal resource'):
                scene.require_asset(asset,True)

    def test_choreography_preserves_combat_budgets_and_economy(self):
        # Observe this adapter's actual input/output, independently of Git HEAD and
        # the later intentional pod/finale/spawn-timing adapters.
        original = self.before_scene
        before = {m['id']:m for m in original['maps']}
        observation_flags = []
        self.assertEqual([m['id'] for m in self.after_scene['maps']],list(before))
        for m in self.after_scene['maps']:
            previous = before[m['id']]
            for key in ('reward','rewards','economy','pickups','bossEncounter'):
                self.assertEqual(m.get(key),previous.get(key))
            self.assertEqual(m['stage'].get('SpawnPoint'),previous['stage'].get('SpawnPoint'))
            actual_wave = copy.deepcopy(m['stage']['Wave'])
            old_wave = previous['stage']['Wave']
            self.assertEqual(len(actual_wave['SubWave']),len(old_wave['SubWave']))
            for actual,old in zip(actual_wave['SubWave'],old_wave['SubWave']):
                self.assertEqual(len(actual['EnemyGroup']['Enemy']),len(old['EnemyGroup']['Enemy']))
                for enemy,prior in zip(actual['EnemyGroup']['Enemy'],old['EnemyGroup']['Enemy']):
                    if 'publishStageEvent' in enemy.get('Parameters',{}) and 'publishStageEvent' not in prior.get('Parameters',{}):
                        self.assertIs(enemy['Parameters'].pop('publishStageEvent'),True)
                        observation_flags.append((m['id'],enemy['SpawnIndex']))
                        if not enemy['Parameters']:
                            del enemy['Parameters']
            self.assertEqual(actual_wave,old_wave)
        self.assertEqual(sorted(observation_flags),[('A12',0),('A19',0),('A19',1)])
        for key in ('startingMoney','startingSkillPoints','externalRewards','actor'):
            self.assertEqual(self.after_scene[key],original[key])

    def test_interactive_instances_are_original_and_scaled_once(self):
        source=interactive.read(interactive.MANIFEST)
        props={p['id']:p for m in self.chapter['maps']
               for p in m['mechanism'].get('interactiveProps',{}).get('props',[])}
        self.assertEqual(len(props),24)
        self.assertEqual(sum(p['kind']=='barrel' for p in props.values()),14)
        self.assertEqual(sum(p['kind']=='pod' for p in props.values()),10)
        for row in source['placements']:
            kind='pod' if row['sourceSprite']==1939 else 'barrel'
            prop=props[f'{row["mapId"]}-{kind}-{row["sourceDepth"]}']
            self.assertEqual(prop['artMatrix'],row['nativeMatrix'][:4]+[0,0])
            for axis,index in (('x',4),('y',5)):
                self.assertAlmostEqual(prop[axis],row['nativeMatrix'][index]*128/75,places=3)
            self.assertEqual(prop['frames'],25 if kind=='pod' else 16)
            if kind=='barrel':
                self.assertAlmostEqual(prop['groundY']-prop['y'],44.5,places=3)
                self.assertAlmostEqual(prop['sortY'],prop['groundY'],places=4)
                self.assertAlmostEqual(prop['hitBounds'][1],21.5-90,places=4)
                self.assertAlmostEqual(prop['hitBounds'][3],45.5,places=4)
            else:
                self.assertNotIn('groundY',prop)
                # Independent original nested-marker corner, not the art footprint.
                self.assertAlmostEqual(prop['hitBounds'][0],-120.75011014658958*128/75,places=3)
                self.assertAlmostEqual(prop['hitBounds'][3],124.6032790184021*128/75,places=3)

    def test_pod_spawn_points_stay_inside_existing_walkable_geometry(self):
        for mid in ('A15','A17'):
            env=self.envs[f'CF6_{mid}_BG.swf']
            bounds=[float(env.findtext(k)) for k in ('Xmin','Ymin','Xmax','Ymax')]
            polygons=[[[float(v) for v in p.text.split(',')] for p in node.findall('Point')]
                      for node in env.findall('Collision')]
            for prop in self.maps[mid]['mechanism']['interactiveProps']['props']:
                p=[prop['x'],prop['y']]
                self.assertTrue(bounds[0]<p[0]<bounds[2] and bounds[1]<p[1]<bounds[3])
                self.assertFalse(any(geometry.point_inside(p,poly) for poly in polygons))

    def test_pod_budget_cannot_duplicate_or_lose_its_trigger(self):
        book_validator.validate_cf6_interactive_props(self.chapter)
        for change in ('duplicate-id','quantity','event','birth','position','boss-cap','boss-unbound'):
            with self.subTest(change=change):
                data=copy.deepcopy(self.chapter);maps={m['id']:m for m in data['maps']}
                a15=maps['A15']['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy']
                a17=maps['A17']['bossEncounter']
                if change=='duplicate-id':
                    maps['A15']['mechanism']['interactiveProps']['props'][1]['id']=maps['A15']['mechanism']['interactiveProps']['props'][0]['id']
                elif change=='quantity': a15[0]['Quantity']=2
                elif change=='event': del a15[0]['TriggerEvent']
                elif change=='birth': a15[0]['Parameters']['publishStageEvent']=False
                elif change=='position': a15[0]['x']+=1
                elif change=='boss-cap': a17['maxAlive']=5
                else: next(e for e in a17['groups'][0]['enemies'] if 'podId' in e)['podId']='foreign'
                with self.assertRaises(ValueError):book_validator.validate_cf6_interactive_props(data)

    def test_interactive_transform_cannot_repeat_or_skip_resource(self):
        with self.assertRaisesRegex(ValueError,'already assembled'):
            interactive.adapt(copy.deepcopy(self.chapter),False)
        asset=interactive.read(interactive.MANIFEST)['assets'][0]
        missing=ROOT/asset['swf'];real_is_file=Path.is_file
        with patch.object(Path,'is_file',lambda p:False if p==missing else real_is_file(p)):
            with self.assertRaisesRegex(ValueError,'fresh CS6 interactive resource'):
                bc.build(require_swfs=True)

    def test_auxiliary_side_wall_doors_keep_native_shear(self):
        side = [l for m in self.chapter['maps'] for l in m['mechanism']['layers']
                if 'AuxDoor1862' in l.get('url','') and abs(l['artMatrix'][1])>0.1]
        self.assertEqual(len(side),4)  # A22 now shares A20's same room/three side-wall doors.
        for layer in side:
            self.assertAlmostEqual(layer['artMatrix'][0],0.603057861328125*1.3,places=8)
            self.assertAlmostEqual(layer['artMatrix'][1],0.4695587158203125*1.3,places=8)
            self.assertEqual(layer['visualScale'],1)

    def test_auxiliary_source_timing_and_instance_tint(self):
        for map_id in ('A08','A09','A12'):
            mechanism=self.maps[map_id]['mechanism']
            self.assertEqual(mechanism['traversal']['depart']['durationFrames'],58)
            self.assertIs(mechanism['traversal']['depart']['preserveActorPosition'],True)
            layer=next(l for l in mechanism['layers'] if 'AuxDoor1430' in l['url'])
            self.assertEqual(layer['frames'],59)
            self.assertEqual(layer['colorMult'],[210,210,210,256])
        cameras=[l for m in self.chapter['maps'] for l in m['mechanism']['layers'] if l['role']=='ambient-loop']
        self.assertEqual(len(cameras),14)
        self.assertTrue(all(l['frames']==147 and 'spawnRadius' not in l for l in cameras))

    def test_spawn_pulses_are_bound_to_actual_declared_spawns(self):
        for m in self.chapter['maps']:
            for layer in m['mechanism']['layers']:
                if 'AuxDoor1862' not in layer.get('url',''):
                    continue
                if m['id']=='A09':
                    self.assertEqual(layer['role'],'depth-prop')
                    self.assertNotIn('spawnRadius',layer)
                    continue
                self.assertEqual(layer['role'],'door-spawn-sequence')
                self.assertLess(math.hypot(layer['spawnX']-layer['x'],layer['spawnY']-layer['y']),100)
                self.assertEqual(layer['spawnRadius'],96)


if __name__=='__main__':
    unittest.main()
