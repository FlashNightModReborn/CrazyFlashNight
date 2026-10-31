"""Chapter-only quantity/ownership/placement tests; no Flash or player-save activity."""
from pathlib import Path
import collections
import copy
import importlib.util
import json
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def module(name, path):
    spec=importlib.util.spec_from_file_location(name,path)
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result)
    return result


fragments=module('difficulty_fragments_test',ROOT/'tools/cf6-roguelike-content/build-sting-fragments.py')
plan=module('difficulty_plan_test',ROOT/'tools/cf6-roguelike-content/difficulty_plan.py')
spawn=module('difficulty_spawn_test',ROOT/'tools/cf6-prototype/spawn-assembly.py')
builder=module('difficulty_chapter_test',ROOT/'tools/cf6-prototype/build-chapter.py')


class DifficultyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.item_index=fragments.load_item_index()
        cls.facts=fragments.load_json(ROOT/'data/stages/books/cf6-sting-source/encounter-facts.v1.json')
        cls.baseline=fragments.build_maps(cls.facts,cls.item_index,fragments.load_turret_block())
        cls.document,cls.audit=plan.adapt(cls.baseline,vars(fragments))
        cls.nodes={n['id']:n for n in cls.document['maps']}
        cls.original={n['id']:n for n in cls.baseline['maps']}

    def test_original_fact_checks_still_run_before_design_adaptation(self):
        actor=fragments.load_json(fragments.ACTOR)
        skills={s.findtext('Name') for s in ET.parse(fragments.SKILLS_XML).findall('Skill') if s.findtext('Name')}
        errors,_=fragments.check(self.baseline,fragments.build_economy(actor['actor']['skills'],self.item_index),
            fragments.build_shops(self.item_index,skills),fragments.build_choice_fragment(self.item_index,skills,[]),
            self.item_index,fragments.load_json(fragments.UNITS),actor,skills,fragments.load_turret_block())
        self.assertEqual(errors,[])

    def test_primary_wave_totals_are_explicit_and_not_successor_double_counts(self):
        expected={'A01':66,'A02':42,'A03':48,'A04':62,'A05':47,'A06':37,'A09':41,
                  'A10':12,'A11':33,'A12':53,'A13':12,'A14':52,'A15':38,'A17':61,
                  'A18':42,'A19':54,'A20':73,'A22':1}
        self.assertEqual({r['mapId']:r['mandatoryPrimary'] for r in self.audit['maps']},expected)
        self.assertEqual(self.audit['mergedFinale']['mandatoryPrimary'],74)
        self.assertEqual(self.audit['mergedFinale']['optionalSupport'],10)
        self.assertEqual(self.audit['mergedFinale']['totalPrimary'],84)

    def test_breathing_rooms_tutorial_and_original_document_remain_unchanged(self):
        for mid in ('TUTORIAL','A08','A16'): self.assertEqual(self.nodes[mid],self.original[mid])
        self.assertNotIn('A07',self.nodes)
        again,audit=plan.adapt(self.baseline,vars(fragments))
        self.assertEqual(again,self.document);self.assertEqual(audit,self.audit)
        with self.assertRaises(ValueError): plan.adapt(self.document,vars(fragments))

    def test_bosses_are_only_in_final_wave_with_native_identity_preserved(self):
        for mid,count in [('A06',3),('A17',4),('A20',6),('A22',1)]:
            node=self.nodes[mid];self.assertEqual(len(plan.waves(node)),count)
            self.assertEqual(plan.waves(node)[-1],plan.waves(self.original[mid])[0])
            for wave in plan.waves(node)[:-1]:
                for enemy in wave['EnemyGroup']['Enemy']:
                    self.assertNotIn('InstanceName',enemy)
                    self.assertFalse(plan.PRIVATE & set(enemy.get('Parameters',{})))

    def test_elite_quota_is_one_original_instance_and_e4_is_mandatory(self):
        before=plan.quota_rows(self.baseline['maps']);after=plan.quota_rows(self.document['maps'])
        self.assertEqual({k:plan.quota_authority(v) for k,v in before.items()},
                         {k:plan.quota_authority(v) for k,v in after.items()})
        e4=[e for e in plan.wave_enemies(self.nodes['A17']) if e.get('Parameters',{}).get('cf6EliteQuota')=='E4']
        self.assertEqual(len(e4),1);self.assertEqual(e4[0]['Quantity'],1)
        self.assertFalse(any(e.get('Parameters',{}).get('cf6EliteQuota') for e in plan.supports(self.nodes['A17'])))

    def test_original_transport_and_pod_budgets_are_not_duplicated(self):
        for mid in ('A09','A14','A18'):
            self.assertEqual(plan.waves(self.nodes[mid])[1],plan.waves(self.original[mid])[1])
            self.assertEqual(self.nodes[mid]['stage']['SpawnPoint']['Point'][0],self.original[mid]['stage']['SpawnPoint']['Point'][0])
        self.assertEqual(plan.waves(self.nodes['A15'])[0],plan.waves(self.original['A15'])[0])
        a17=self.nodes['A17']['bossEncounter']
        self.assertEqual((a17['maxAlive'],a17['intervalFrames']),(4,45))
        self.assertEqual(sum(e['Quantity'] for e in plan.supports(self.nodes['A17']) if plan.REGISTRY.resolve_id(e['Type'])==460),5)

    def test_special_producers_cannot_lose_or_duplicate_units_after_adaptation(self):
        for mid,field in [('A09','transport'),('A15','pods'),('A17','support')]:
            value=copy.deepcopy(self.document);node=next(n for n in value['maps'] if n['id']==mid)
            if field=='transport':plan.waves(node)[1]['EnemyGroup']['Enemy'][0]['Quantity']+=1
            elif field=='pods':plan.waves(node)[0]['EnemyGroup']['Enemy'][0]['Quantity']-=1
            else:next(e for e in plan.supports(node) if plan.REGISTRY.resolve_id(e['Type'])==460)['Quantity']-=1
            with self.assertRaises(ValueError):plan.validate(value)

    def test_turret_compatibility_stays_exactly_twenty_not_the_whole_new_horde(self):
        enemies=plan.wave_enemies(self.nodes['A01'])
        tagged=[e for e in enemies if e.get('Parameters',{}).get('目标标记')=='cf6-a01-turret-zombie']
        self.assertEqual(sum(e['Quantity'] for e in tagged),20)
        self.assertTrue(all(plan.REGISTRY.resolve_id(e['Type'])==461 for e in tagged))
        self.assertEqual(sum(e['Quantity'] for e in enemies),66)

    def test_caps_deduplicate_shared_points_and_include_static_map_bucket(self):
        wave={'EnemyGroup':{'Enemy':[dict(Quantity=7,SpawnIndex=0),dict(Quantity=5,SpawnIndex=0),dict(Quantity=2)]}}
        bound=plan.wave_bound(wave,[dict(QuantityMax=4)])
        self.assertEqual(bound['upperBound'],6)
        self.assertEqual(len(bound['indexedPoints']),1)
        self.assertEqual(bound['mapBucketOrStatic'],2)
        self.assertTrue(all(r['peakAliveUpperBound']<=r['configuredRoomLimit'] for r in self.audit['maps']))
        self.assertEqual(next(r['peakAliveUpperBound'] for r in self.audit['maps'] if r['mapId']=='A14'),12)

    def test_original_timeline_ignores_dormant_templates_and_distinguishes_boss_copies(self):
        progression=plan.original_progression()
        expected={'zombie':'A01','zombie_f':'A02','thug':'A02','specop':'A06',
                  'specop_shield':'A09','thug_tf':'A10','alien':'A15','robot_sword':'A17',
                  'wings':'A18','manman':'A18','robot_big':'A22'}
        self.assertEqual({k:progression[k]['ordinary']['mapId'] for k in expected},expected)
        self.assertEqual(progression['manman']['boss']['mapId'],'A06')
        self.assertEqual(progression['robot_big']['boss']['mapId'],'A17')
        self.assertNotIn('ordinary',progression['oldman_human'])

    def test_early_future_enemies_fail_even_when_the_authored_plan_requests_them(self):
        for mid,unit in [('A01','zombie_f'),('A02','specop'),('A06','specop_shield'),
                         ('A09','thug_tf'),('A12','robot_sword'),('A17','wings'),
                         ('A09','manman'),('A20','robot_big'),('A05','alien')]:
            config=plan.load();group=config['maps'][mid]['waves'][0]['groups'][0]
            group.clear();group.update(unit=unit,count=1)
            with self.subTest(mid=mid,unit=unit),self.assertRaisesRegex(ValueError,'precedes original'):
                plan.adapt(self.baseline,vars(fragments),config)

    def test_elevators_have_one_preplaced_formation_and_no_reinforcement_queue(self):
        for mid in ('A10','A13'):
            node=self.nodes[mid];self.assertEqual(len(plan.waves(node)),1)
            enemies=plan.wave_enemies(node);self.assertEqual(len(enemies),12)
            self.assertEqual(len({(e['x'],e['y']) for e in enemies}),12)
            for enemy in enemies:
                self.assertEqual(enemy['Quantity'],1)
                self.assertFalse({'SpawnIndex','Delay','Interval','TriggerEvent'} & set(enemy))
            for field in ('SpawnIndex','Delay','Interval'):
                value=copy.deepcopy(self.document)
                target=next(n for n in value['maps'] if n['id']==mid)
                plan.wave_enemies(target)[0][field]=1
                with self.assertRaises(ValueError): plan.validate(value)

    def test_malformed_budget_composition_and_nocount_are_rejected(self):
        for mutate in [lambda d:d['maps'][1]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0].update(Quantity=99),
                       lambda d:d['maps'][1]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0].update(Type='cf6.大头机器人'),
                       lambda d:d['maps'][1]['stage']['Wave']['SubWave'][0]['WaveInformation'].update(FinishRequirement=5),
                       lambda d:d['maps'][1]['stage']['BasicInformation'].update(MapNoCount=True),
                       lambda d:d['maps'][1]['stage']['SpawnPoint']['Point'][-1].update(NoCount=True)]:
            value=copy.deepcopy(self.document);mutate(value)
            with self.assertRaises(ValueError):plan.validate(value)
        value=copy.deepcopy(self.baseline);value['maps'][1]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0]['Quantity']+=1
        with self.assertRaises(ValueError):plan.adapt(value,vars(fragments))

    def test_full_memory_assembly_preserves_real_triggers_and_collision_safe_points(self):
        original_read=builder.read
        target=ROOT/'data/stages/books/cf6-sting-source/maps.fragment.json'
        builder.read=lambda path:copy.deepcopy(self.document) if Path(path).resolve()==target.resolve() else original_read(path)
        try: outputs=builder.build(require_swfs=False)
        finally: builder.read=original_read
        chapter=json.loads(outputs[builder.OUTPUT]);nodes={n['id']:n for n in chapter['maps']}
        self.assertEqual(nodes['A07']['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'],[])
        env={e.findtext('BackgroundURL'):e for e in ET.fromstring(outputs[builder.ENVIRONMENT]).findall('Environment')}
        for node in chapter['maps']:
            meta=node.get('sourceNote',{}).get(plan.META)
            if not meta:continue
            for role in meta['spawnPointRoles']:
                p=node['stage']['SpawnPoint']['Point'][role['index']]
                self.assertTrue(spawn.safe_box(env[node['background'].split('/')[-1]],[p['x']-12,p['y']-6,p['x']+12,p['y']+6]))
                doors={(door['spawnX'],door['spawnY']) for door in node['mechanism'].get('layers',[]) if door.get('role')=='door-spawn-sequence'}
                if (p['x'],p['y']) in doors:
                    self.assertTrue(all(e.get('Parameters',{}).get('publishStageEvent') is True for e in plan.wave_enemies(node) if e.get('SpawnIndex')==role['index']))
        for mid in ('A10','A13'):
            node=nodes[mid];environment=env[node['background'].split('/')[-1]]
            self.assertEqual(len(plan.waves(node)),1)
            self.assertEqual(sum(e['Quantity'] for e in plan.wave_enemies(node)),12)
            arrival=node['mechanism']['traversal']['arrive']['samples'][-1]
            for enemy in plan.wave_enemies(node):
                x,y=enemy['x'],enemy['y']
                self.assertTrue(spawn.safe_box(environment,[x-12,y-6,x+12,y+6]))
                self.assertGreater(x-arrival['x'],80)
        for mid,quantity in [('A09',5),('A14',7),('A18',5)]:
            enemy=nodes[mid]['stage']['Wave']['SubWave'][1]['EnemyGroup']['Enemy'][0]
            self.assertEqual(enemy['Quantity'],quantity)
            self.assertEqual(enemy['TriggerEvent']['EventName'],'Cf6TransportReady')
            self.assertEqual(nodes[mid]['mechanism']['transport']['subWaveIndex'],1)
        pods=nodes['A15']['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy']
        self.assertEqual(len(pods),5);self.assertEqual(len({e['Parameters']['cf6PodId'] for e in pods}),5)
        self.assertTrue(all(e['TriggerEvent']['EventName']=='Cf6PodReady' for e in pods))
        self.assertEqual(nodes['A20']['stage']['Wave']['SubWave'][-1]['EnemyGroup']['Enemy'][0]['Parameters']['老头变身'],True)
        self.assertEqual(nodes['A20']['bossEncounter']['nextPhase']['instanceName'],'cf6Boss_A20__elderbot')
        self.assertNotIn('A22',nodes)


if __name__=='__main__': unittest.main(verbosity=2)
