import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
sys.path.insert(0,str(HERE))
import build

class ActorTemplateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.output=build.build()
        cls.actor=cls.output['actor.fragment.json']['actor']
        cls.audit=cls.output['source-audit.json']

    def test_exact_source_npc_and_player_level(self):
        actor=self.actor
        self.assertEqual(('Andy',185,60,157526193,''),(actor['name'],actor['height'],actor['level'],actor['experience'],actor['hair']))
        self.assertEqual(213,self.audit['npcUnitId'])
        self.assertEqual(275,self.audit['hostileMirrorId'])

    def test_fixed_union_and_cost_are_not_sp_cash(self):
        self.assertEqual(35,len(self.actor['skills']))
        self.assertEqual(35,len({entry['name'] for entry in self.actor['skills']}))
        self.assertEqual(24,self.audit['teacherCount'])
        self.assertEqual((9900,12310),(self.audit['teacherSpEquivalent'],self.audit['totalSpEquivalent']))
        self.assertFalse(self.audit['spIsSpendableGrant'])
        self.assertNotIn('驾驶',{entry['name'] for entry in self.actor['skills']})
        catalog={entry.findtext('Name'):int(entry.findtext('MaxLevel')) for entry in ET.parse(ROOT/'data/skills/skills.xml').findall('Skill')}
        for grant in self.actor['skills']:self.assertEqual(catalog[grant['name']],grant['level'])

    def test_full_armor_and_explicit_weapon_candidate(self):
        equipment={entry['slot']:entry for entry in self.actor['equipment']}
        self.assertEqual(8,len(equipment))
        self.assertTrue(all(entry['enhancement']==11 for entry in equipment.values()))
        self.assertEqual('镜之虎彻',equipment['刀']['name'])
        self.assertEqual('M4A1战术版',equipment['长枪']['name'])
        self.assertEqual(70,self.audit['originalNpcGun']['requiredLevel'])
        self.assertFalse(self.audit['originalNpcGun']['inherited'])
        self.assertEqual(35,next(entry['requiredLevel'] for entry in self.audit['equipment'] if entry['slot']=='长枪'))

    def test_ammo_and_no_double_initial_weapon(self):
        supply=self.output['initial-supply-requirements.json']
        self.assertTrue(supply['alreadyEquippedByActor'])
        self.assertFalse(supply['grantAdditionalFreeCopy'])
        self.assertEqual(['突击步枪通用弹药','榴弹弹药'],[entry['name'] for entry in supply['ammo']])
        self.assertTrue(all(entry['count'] is None for entry in supply['ammo']))
        self.assertEqual('onLoadGroup',supply['authoredSubweapon']['consumeMode'])
        self.assertEqual('onReloadCommit',supply['authoredSubweapon']['consumeTiming'])

    def test_generation_is_not_display_name_dependent(self):
        source=build.NPC_SKILL_SOURCE.read_text('utf-8-sig')
        andy,_=build.npc_selection(source,'Andy',60,True,True)
        law,_=build.npc_selection(source,'Andy Law',60,True,True)
        self.assertNotEqual(andy,law)
        self.assertEqual(andy,self.audit['npcSelected'])
        self.assertTrue(self.audit['model']['sourceModelOnly'])
        self.assertFalse(self.audit['model']['actualAvm1Executed'])

    def test_algorithm_drift_is_not_silently_regenerated(self):
        selection=json.loads((HERE/'selection.json').read_text('utf-8'))
        selection['npcSkillAlgorithmSha256']='0'*64
        with self.assertRaisesRegex(ValueError,'algorithm drift'):build.build(selection=selection)

    def test_fragment_satisfies_real_cf6_actor_consumer_schema(self):
        sys.path.insert(0,str(ROOT/'tools'))
        spec=importlib.util.spec_from_file_location('book_builder',ROOT/'tools/build-book-definition.py')
        builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
        items={item.findtext('name'):item for path in (ROOT/'data/items').glob('*.xml') for item in ET.parse(path).findall('.//item')}
        data=dict(schema='playable-book.v1',id='cf6-sting',routeId='historical',stageName='书中历险-毒刺行动',title='TEST ONLY',
            actor=copy.deepcopy(self.actor),startingMoney=0,startingSkillPoints=0,maps=[dict(id='TUTORIAL',title='TEST ONLY',
            background='gk1_1_BG.swf',dialogue=[],stage={'Wave':{'SubWave':[{'EnemyGroup':{'Enemy':[]}}]}})])
        units={unit['id'] for unit in json.loads((ROOT/'data/units/units.json').read_text('utf-8-sig'))}
        builder.validate_cf6(data,items,ET.parse(ROOT/'data/skills/skills.xml').findall('Skill'),units,require_backgrounds=False)

    def test_outputs_are_current(self):
        for name,value in self.output.items():
            self.assertEqual((json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode(),(HERE/name).read_bytes())

if __name__=='__main__':unittest.main()
