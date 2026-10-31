"""Validate book content against the real skill/item catalog; no player state is used."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('book_definition', ROOT / 'tools/build-book-definition.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class BookDefinitionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = builder.normalize_book_units(builder.resolve_book_choices(json.loads(builder.SOURCE.read_text(encoding='utf-8'))), builder.UnitRegistry.load(ROOT))
        cls.skills = ET.parse(ROOT / 'data/skills/skills.xml').findall('Skill')
        cls.items = {}
        for path in (ROOT / 'data/items').glob('*.xml'):
            cls.items.update((i.findtext('name'), i) for i in ET.parse(path).findall('.//item'))

    def setUp(self):
        self.data = copy.deepcopy(self.source)

    def validate(self):
        builder.validate_skills(self.data, self.skills)
        builder.validate_choices(self.data, self.items)
        builder.validate_loot(self.data, self.items)

    def test_current_content_and_shop_cover_all_choices(self):
        self.validate()
        shop = json.loads((ROOT / 'data/shops/npcs/书中-迷之盔甲君.json').read_text(encoding='utf-8'))
        catalog = set(shop['catalog'].values())
        for stage in self.data['maps']:
            self.assertTrue(set(stage['equipment'] + stage['armor']) <= catalog)
            self.assertIn(stage['healingItem'], catalog)
            self.assertIn(stage['manaItem'], catalog)
            self.assertTrue({entry['name'] for entry in stage['materials']} <= catalog)
        self.assertEqual(11, len(self.data['skills']))
        self.assertEqual({'小跳','兴奋剂','铁布衫','寸拳','气动波','移动射击','刀剑攻击','枪械攻击','拳脚攻击','口才','独行者'}, set(self.data['skills']))
        self.assertFalse({'重力场', '能量盾', '铁匠', '解密', '烹饪', '逆向', '驾驶'} & set(self.data['skills']))

    def test_fist_progression_has_drop_and_shop_access(self):
        shop = json.loads((ROOT / 'data/shops/npcs/书中-迷之盔甲君.json').read_text('utf-8'))
        for index, name, ceiling in [(0, '道钉手套', 6), (2, '小型拳套', 11), (3, '大型拳套', 13)]:
            item = self.items[name]
            self.assertIn(name, self.data['maps'][index]['armor'])
            self.assertIn(name, shop['catalog'].values())
            self.assertEqual(item.findtext('use'), '手部装备')
            self.assertGreater(int(item.findtext('data/punch', '0')), 0)
            self.assertLessEqual(int(item.findtext('data/level')), ceiling)

    def test_boss_reinforcements_are_bounded_and_supply_only(self):
        units = {u['id'] for u in json.loads((ROOT/'data/units/units.json').read_text('utf-8-sig'))}
        builder.validate_boss(self.data,units,self.items)
        self.assertEqual(sum(len(g['pools']) for g in self.data['bossEncounter']['groups']),8)
        for mutate in [lambda c:c.update(maxAlive=9),lambda c:c['groups'][1].update(hpRatio=0.9),
                       lambda c:c['supplies'][0].update(name='经验值'),lambda c:c['groups'][1]['pools'][0].append(44)]:
            data=copy.deepcopy(self.data);mutate(data['bossEncounter'])
            with self.assertRaises(ValueError):builder.validate_boss(data,units,self.items)
        for field,value in [('waves',2),('count',[1,2]),('enemies',[455,44])]:
            data=copy.deepcopy(self.data);data['maps'][-1][field]=value
            with self.assertRaises(ValueError):builder.validate_boss(data,units,self.items)

    def test_book_can_curate_a_subset_of_eligible_skills(self):
        self.data['skills'].remove('小跳')
        self.validate()

    def test_empty_skill_menu_is_rejected(self):
        self.data['skills'] = []
        with self.assertRaises(ValueError): self.validate()

    def test_above_ceiling_skill_is_rejected(self):
        self.data['skills'].append('一瞬千击')
        with self.assertRaises(ValueError): self.validate()

    def test_duplicate_and_blank_skills_are_rejected(self):
        for name in ['', '小跳', '不存在的技能']:
            with self.subTest(name=name):
                self.data = copy.deepcopy(self.source)
                self.data['skills'].append(name)
                with self.assertRaises(ValueError): self.validate()

    def test_weapon_cannot_take_guaranteed_armor_slot(self):
        self.data['maps'][0]['armor'][0] = 'PPK'
        with self.assertRaises(ValueError): self.validate()

    def test_two_armor_choices_cannot_be_identical(self):
        self.data['maps'][0]['armor'] = ['军绿防弹衣', '军绿防弹衣']
        with self.assertRaises(ValueError): self.validate()

    def test_armor_cannot_also_be_the_random_equipment_roll(self):
        self.data['maps'][0]['equipment'].append('军绿防弹衣')
        with self.assertRaises(ValueError): self.validate()

    def test_mana_only_potion_cannot_supply_health(self):
        self.data['maps'][2]['healingItem'] = '加强mp药剂'
        with self.assertRaises(ValueError): self.validate()

    def test_health_only_potion_cannot_supply_mana(self):
        self.data['maps'][2]['manaItem'] = '大HP药剂'
        with self.assertRaises(ValueError): self.validate()

    def test_instant_supply_cannot_replace_carried_potions(self):
        self.data['maps'][2]['healingItem'] = '战场复合急救包'
        with self.assertRaises(ValueError): self.validate()

    def test_fixed_heal_cannot_replace_scaling_emergency_pickup(self):
        self.data['loot']['medicalItem'] = '战场医疗包'
        with self.assertRaises(ValueError): self.validate()

    def test_missing_mana_cycle_is_rejected(self):
        self.data['loot']['support'][0]['kind'] = 'ammo'
        with self.assertRaises(ValueError): self.validate()

    def test_drop_density_cannot_expand_beyond_two_armor_waves(self):
        self.data['loot']['armorWaves'] = 3
        with self.assertRaises(ValueError): self.validate()

    def test_selected_recovery_is_effective_and_progressive(self):
        def healing(name, key):
            return sum(float(e.get(key, '0')) for e in self.items[name].findall('data/effects/effect')
                       if e.get('type') == 'heal' and e.get('target') == 'self')
        health = [healing(m['healingItem'], 'hp') for m in self.data['maps']]
        mana = [healing(m['manaItem'], 'mp') for m in self.data['maps']]
        self.assertEqual([150, 150, 800, 800, 1500, 1500, 1500], health)
        self.assertEqual([100, 100, 600, 600, 1500, 1500, 1500], mana)
        effects = self.items[self.data['loot']['medicalItem']].findall('data/effects/effect')
        self.assertTrue(any(e.get('type') == 'heal' and e.get('hp') == '25%' and e.get('mp') == '50%' for e in effects))
        self.assertTrue(any(e.get('type') == 'regen' and e.get('hp') == '200' and e.get('mode') == 'total' for e in effects))

    def test_military_is_after_both_student_factions_without_level_buff(self):
        self.assertEqual([[44, 45], [48, 49], [447, 448], [436, 437], [449, 450], [444, 446], [455]],
                         [stage['enemies'] for stage in self.data['maps']])
        self.assertEqual([5, 7], self.data['maps'][4]['level'])
        # Reordering the encounters must not delay the established gear unlock budget.
        self.assertEqual([9000, 45000, 77000, 140000, 110000, 120000, 160000],
                         [stage['experience'] for stage in self.data['maps']])

    def test_local_skill_points_use_real_currency_and_bounded_counts(self):
        self.assertEqual(360, sum(stage['skillPoints'] for stage in self.data['maps']))
        self.assertEqual(120, self.data['startingSkillPoints'])
        for name in ['SP', '金币']:
            self.data['loot']['skillPointItem'] = name
            with self.assertRaises(ValueError): self.validate()
        self.data = copy.deepcopy(self.source)
        for count in [-1, 101, True, 1.5]:
            self.data['maps'][0]['skillPoints'] = count
            with self.assertRaises(ValueError): self.validate()

    def test_materials_cannot_add_multiple_stacks_per_wave(self):
        self.data['maps'][0]['materials'].append({'name': '弹簧', 'count': 1})
        with self.assertRaises(ValueError): self.validate()

    def test_material_counts_must_be_positive_bounded_integers(self):
        for count in [0, -1, 101, True, 1.5]:
            self.data['maps'][0]['materials'][0]['count'] = count
            with self.assertRaises(ValueError): self.validate()

    def test_consumables_cannot_masquerade_as_tuning_materials(self):
        self.data['maps'][0]['materials'][0]['name'] = '普通hp药剂'
        with self.assertRaises(ValueError): self.validate()

    def test_unusable_high_tier_components_are_rejected(self):
        for name in ['三阶复合防御组件', '四阶复合防御组件']:
            self.data['maps'][3]['materials'][0]['name'] = name
            with self.assertRaises(ValueError): self.validate()

    def test_tier_components_and_mods_supply_actual_tuning_options(self):
        totals = {}
        for stage in self.data['maps']:
            for entry in stage['materials']:
                totals[entry['name']] = totals.get(entry['name'], 0) + entry['count']
        self.assertEqual(5, totals['二阶复合防御组件'])
        self.assertEqual(78, totals['强化石'])
        self.assertTrue({'弹簧', '螺丝套件', '绳扣穿孔片', '手柄皮', '战术背带', '高耐力橡胶'} <= totals.keys())
        self.assertFalse(any(entry['name'] == '二阶复合防御组件'
                             for stage in self.data['maps'][:3] for entry in stage['materials']))
        # The boss is the end of this temporary build, so no new build resources arrive after it.
        self.assertEqual([], self.data['maps'][6]['materials'])
        self.assertEqual(0, self.data['maps'][6]['skillPoints'])

    def test_vouchers_are_finite_and_not_sold_or_recycled(self):
        generated = builder.generated_deliveries(self.data)
        recipes = json.loads(generated[builder.RECIPE_OUTPUT])
        recipes = [r for r in recipes if r['recipeId'].startswith('craft.book-supply.')]
        generated_items = {i.findtext('name'): i for i in ET.fromstring(generated[builder.PACK_OUTPUT]).findall('item')}
        vouchers = {c['voucher'] for c in self.data['buildChoices']}
        self.assertEqual(8, len(recipes))
        for choice in self.data['buildChoices']:
            matches = [r for r in recipes if r['materials'] == [choice['voucher'] + '#1']]
            self.assertEqual(4, len(matches))
            self.assertEqual({o['name'] for o in choice['options']}, {r['name'] for r in matches})
            self.assertTrue(all(r['price'] == r['kprice'] == 0 and r['value'] == 1 for r in matches))
        for meta in generated_items.values():
            self.assertEqual('0', meta.findtext('price'))
            self.assertFalse(vouchers & {e.findtext('itemName') for e in meta.findall('data/rewardPack/entries/entry')})
        for path in (ROOT / 'data/shops/npcs').glob('*.json'):
            catalog = json.loads(path.read_text(encoding='utf-8'))['catalog']
            names = {v if isinstance(v, str) else v['name'] for v in catalog.values()}
            self.assertFalse(set(generated_items) & names, path.name)

    def test_generated_deliveries_are_current_and_registered(self):
        for path, content in builder.generated_deliveries(self.data).items():
            self.assertEqual(content, path.read_bytes(), path.name)
        self.assertIn(builder.PACK_OUTPUT.name, [e.text for e in ET.parse(ROOT / 'data/items/list.xml').findall('items')])
        self.assertIn('书中配给', [e.text for e in ET.parse(ROOT / 'data/crafting/list.xml').findall('list')])

    def test_build_pack_contents_are_fixed_and_complete(self):
        for checkpoint in self.data['buildChoices']:
            for option in checkpoint['options']:
                item = self.items[option['name']]
                self.assertEqual('fixed', item.findtext('data/rewardPack/mode'))
                actual = [(e.findtext('itemName'), int(e.findtext('quantityMin'))) for e in item.findall('data/rewardPack/entries/entry')]
                count = option.get('weaponCount', 1)
                expected = [(option['weapon'], 1)] * count + [(n, count) for n in option['mods']] + [(e['name'], e['count']) for e in option['consumables']]
                self.assertEqual(expected, actual)
                self.assertTrue(all(e.findtext('quantityMin') == e.findtext('quantityMax') for e in item.findall('data/rewardPack/entries/entry')))

    def test_underbarrel_without_grenade_ammo_is_rejected(self):
        option = self.data['buildChoices'][0]['options'][1]
        option['consumables'] = [e for e in option['consumables'] if e['name'] != '榴弹弹药']
        with self.assertRaises(ValueError): self.validate()

    def test_wrong_gun_mod_subtype_or_missing_rail_is_rejected(self):
        self.data['buildChoices'][0]['options'][0]['mods'] = ['水冷机构']
        with self.assertRaises(ValueError): self.validate()
        self.data = copy.deepcopy(self.source)
        original = self.items['AK47']
        try:
            self.items['AK47'] = copy.deepcopy(original)
            self.items['AK47'].remove(self.items['AK47'].find('inherentTags'))
            with self.assertRaises(ValueError): self.validate()
        finally:
            self.items['AK47'] = original

    def test_high_level_weapon_and_missing_melee_pivot_are_rejected(self):
        self.data['buildChoices'][0]['options'][0]['weapon'] = 'M249'
        with self.assertRaises(ValueError): self.validate()
        self.data = copy.deepcopy(self.source)
        self.data['buildChoices'][0]['options'][3] = copy.deepcopy(self.data['buildChoices'][0]['options'][0])
        self.data['buildChoices'][0]['options'][3]['name'] = '书中新选项'
        with self.assertRaises(ValueError): self.validate()

    def test_recurring_ammunition_covers_heavy_and_ordinary_guns(self):
        self.validate()
        for name in ['机枪通用弹药', '12号霰弹弹药', '冲锋枪通用弹药', '榴弹弹药']:
            with self.subTest(name=name):
                self.data = copy.deepcopy(self.source)
                self.data['ammoBundle']['contents'] = [e for e in self.data['ammoBundle']['contents'] if e['name'] != name]
                with self.assertRaises(ValueError): self.validate()

    def test_build_resources_do_not_raise_original_character_rewards(self):
        self.assertEqual((5, 0, 0, [30, 25, 20]),
                         (self.data['regularSp'], self.data['firstClearSp'], self.data['recordSpPerTier'], self.data['recordMinutes']))

    def test_record_bonus_is_a_total_not_an_extra_tier(self):
        self.assertEqual(self.data['recordSp'], 45)

    def test_checkpoint_xp_unlocks_every_loadout_before_next_map(self):
        # Current cumulative level gates from 引擎_lsy_等级与经验值.as (13 * previousLevel**4 + 500).
        for checkpoint, required_xp in zip(self.data['buildChoices'], [53748, 270068]):
            budget = sum(stage['experience'] for stage in self.data['maps'][:checkpoint['afterMap'] + 1])
            self.assertGreaterEqual(budget, required_xp)

    def test_runtime_json_carries_grade_once_as2_projection_lands(self):
        # The compiled BookDefinition.valid() shape-checks the runtime JSON against the
        # generated fallback; both carry grade since the AS2 projection was wired.
        runtime = json.loads((ROOT / 'data/stages/books/repair-campus.runtime.json').read_text(encoding='utf-8'))
        for checkpoint in runtime['buildChoices'] + runtime['minorChoices']:
            for option in checkpoint['options']:
                self.assertIn(option['grade'], ('low', 'medium', 'high', 'special'))

    # A01 教学炮塔挂接规格(r15):与装配产物逐字段一致;世界坐标=native×128/75。
    CF6_TURRET_SPEC = dict(assetUrl='flashswf/backgrounds/cf6/CF6_A01_Turret.swf',
                           linkage='CF6教学炮塔-A01自动炮', filterMarker='cf6-a01-turret-zombie',
                           fireIntervalFrames=18, fireFrameOffset=11,
                           turrets=[dict(x=228.352, y=345.4293, facing='right',ownFootprint=[97.28,279.8933,354.9867,348.16]),
                                    dict(x=426.3253, y=735.4027, facing='right',ownFootprint=[303.7867,658.7733,544.4267,767.9147])])

    def cf6_fixture(self):
        # Test-only single room: never installed as playable content.
        maximum = next(int(s.findtext('MaxLevel')) for s in self.skills if s.findtext('Name') == '小跳')
        return dict(schema='playable-book.v1',id='cf6-sting',routeId='historical',stageName='书中历险-毒刺行动',title='CF6 TEST ONLY',
                    startingMoney=0,startingSkillPoints=0,
                    actor=dict(name='Andy',gender='男',height=175,face='男变装-基本脸型',hair='发型-男式-Andy发型',level=60,experience=157526193,
                               equipment=[dict(slot='上装装备',name='白色中山上装',enhancement=11)],skills=[dict(name='小跳',level=maximum)]),
                    maps=[dict(id='A01',title='TEST ONLY',background='cf6/CF6_A01_BG.swf',dialogue=[],
                               presentation=dict(scale=1,backgroundX=0,backgroundY=0),
                               mechanism=dict(assetScale=1,layers=[],turrets=copy.deepcopy(self.CF6_TURRET_SPEC)),
                               stage={'Wave':{'SubWave':[{'EnemyGroup':{'Enemy':[{'Type':'兵种'+str(self.source['maps'][0]['enemies'][0]),'Level':35,'Quantity':1}]}}]}})])

    def validate_cf6(self, data):
        units={u['id'] for u in json.loads((ROOT/'data/units/units.json').read_text('utf-8-sig'))}
        builder.validate_cf6(data,self.items,self.skills,units,require_backgrounds=False)

    def test_type61_partial_loadout_is_independent_of_historical_actor(self):
        registry=builder.UnitRegistry.load(ROOT)
        data=builder.normalize_book_units(json.loads(builder.TYPE61_SOURCE.read_text('utf8')),registry)
        self.validate_cf6(data)
        self.assertEqual((35,17372868,1050),(data['actor']['level'],data['actor']['experience'],data['startingSkillPoints']))
        self.assertEqual(1,next(s['level'] for s in data['actor']['skills'] if s['name']=='铁匠'))
        self.assertEqual({1},{e['enhancement'] for e in data['actor']['equipment']})
        self.assertIn('移动射击',data['actor']['quickSkills'])
        self.assertEqual('cf6-type61.runtime.json',next(iter(builder.generated_cf6(data))).name)
        historical=builder.normalize_book_units(json.loads(builder.CF6_SOURCE.read_text('utf8')),registry)
        self.validate_cf6(historical)
        self.assertEqual(60,historical['actor']['level'])

    def test_type61_rejects_duplicate_sp_smith_upgrades_and_foreign_loadouts(self):
        original=builder.normalize_book_units(json.loads(builder.TYPE61_SOURCE.read_text('utf8')),builder.UnitRegistry.load(ROOT))
        mutations=[lambda d:d.update(startingSkillPoints=2560),
                   lambda d:d['actor'].update(experience=0),
                   lambda d:d['actor']['equipment'][0].update(enhancement=11),
                   lambda d:next(s for s in d['actor']['skills'] if s['name']=='铁匠').update(level=2),
                   lambda d:d['actor']['quickSkills'].append('移动射击'),
                   lambda d:d['actor']['quickSkills'].append('铁匠'),
                   lambda d:d.update(routeId='plan61')]
        for mutate in mutations:
            data=copy.deepcopy(original);mutate(data)
            with self.assertRaises(ValueError):self.validate_cf6(data)

    def test_cf6_authored_twenty_maps_plus_TUTORIAL(self):
        data=self.cf6_fixture()
        template=data['maps'][0]
        data['maps']=[]
        for identity in ['TUTORIAL']+['A%02d'%n for n in range(1,23) if n not in (7,21)]:
            stage=copy.deepcopy(template);stage['id']=identity;stage['background']='cf6/CF6_Tutorial_BG.swf' if identity=='TUTORIAL' else 'cf6/CF6_'+identity+'_BG.swf'
            if identity!='A01': stage['mechanism'].pop('turrets')  # 炮塔接线仅属A01
            data['maps'].append(stage)
        self.validate_cf6(data)
        self.assertEqual(21,len(data['maps']))
        output=json.loads(next(iter(builder.generated_cf6(data).values())))
        self.assertEqual(data,output)

    def test_cf6_background_allowlist_binds_exact_map(self):
        data=self.cf6_fixture();self.validate_cf6(data)
        for background in ['CF6_A01_BG.swf','cf6/CF6_A02_BG.swf','cf6/../CF6_A01_BG.swf','../cf6/CF6_A01_BG.swf','cf6\\CF6_A01_BG.swf','gk1_1_BG.swf']:
            data=self.cf6_fixture();data['maps'][0]['background']=background
            with self.subTest(background=background),self.assertRaises(ValueError):self.validate_cf6(data)
    def test_cf6_tutorial_background_requires_dedicated_asset(self):
        data=self.cf6_fixture();data['maps'][0].update(id='TUTORIAL',background='cf6/CF6_Tutorial_BG.swf')
        data['maps'][0]['mechanism'].pop('turrets')  # 炮塔接线仅属A01
        self.validate_cf6(data)
        for background in ['gk1_1_BG.swf','cf6/gk1_1_BG.swf','cf6/CF6_A01_BG.swf',
                           'CF6_Tutorial_BG.swf','cf6/Other.swf','cf6\\CF6_Tutorial_BG.swf','cf6/../CF6_Tutorial_BG.swf']:
            data['maps'][0]['background']=background
            with self.subTest(background=background),self.assertRaises(ValueError):self.validate_cf6(data)

    def cf6_boss_fixture(self):
        data=self.cf6_fixture();stage=data['maps'][0]
        stage.update(id='A06',background='cf6/CF6_A06_BG.swf')
        stage['mechanism'].pop('turrets')  # 炮塔接线仅属A01
        stage['stage']['Wave']['SubWave']=[{'EnemyGroup':{'Enemy':[{'Type':'兵种463','Level':60,'Quantity':1,'InstanceName':'cf6Boss_A06'}]}}]
        stage['bossEncounter']={'instanceName':'cf6Boss_A06','maxAlive':2,'maxRanged':1,'intervalFrames':60,
            'groups':[{'hpRatio':1,'enemies':[{'Type':'兵种461','Level':60,'Quantity':3,'ranged':False,'SpawnIndex':'left','Parameters':{}}]},
                      {'hpRatio':0.5,'enemies':[{'Type':'兵种466','Level':60,'Quantity':2,'ranged':True,'SpawnIndex':'right','Parameters':{}}]}]}
        return data

    def test_cf6_boss_finite_support_contract(self):
        self.validate_cf6(self.cf6_boss_fixture())

    def cf6_boss_prelude_fixture(self):
        data=self.cf6_boss_fixture()
        waves=data['maps'][0]['stage']['Wave']['SubWave']
        prelude={'WaveInformation':{'Duration':0,'FinishRequirement':0},
                 'EnemyGroup':{'Enemy':[{'Type':'兵种461','Level':40,'Quantity':4,
                                         'SpawnIndex':'left','Parameters':{}}]}}
        waves[0:0]=[copy.deepcopy(prelude),copy.deepcopy(prelude)]
        return data

    def test_cf6_boss_accepts_required_preludes_before_unique_boss(self):
        data=self.cf6_boss_prelude_fixture()
        self.validate_cf6(data)
        self.assertEqual('cf6Boss_A06',data['maps'][0]['stage']['Wave']['SubWave'][-1]['EnemyGroup']['Enemy'][0]['InstanceName'])

    def test_cf6_boss_preludes_reject_skip_and_ownership_drift(self):
        for case in ('timed','remaining','uncountedMap','uncountedPoint','malformedPoint','empty','tooMany',
                     'earlyBoss','earlyRobot','name','owner','source','transform','bossNotLast'):
            data=self.cf6_boss_prelude_fixture();stage=data['maps'][0]
            waves=stage['stage']['Wave']['SubWave'];wave=waves[0];enemy=wave['EnemyGroup']['Enemy'][0]
            if case=='timed':wave['WaveInformation']['Duration']=1
            elif case=='remaining':wave['WaveInformation']['FinishRequirement']=1
            elif case=='uncountedMap':wave['WaveInformation']['MapNoCount']=True
            elif case=='uncountedPoint':stage['stage']['SpawnPoint']={'Point':[{'x':100,'y':300,'NoCount':True}]}
            elif case=='malformedPoint':stage['stage']['SpawnPoint']={'Point':[1]}
            elif case=='empty':wave['EnemyGroup']['Enemy']=[]
            elif case=='tooMany':waves[0:0]=[copy.deepcopy(wave) for _ in range(4)]
            elif case=='earlyBoss':enemy['Type']='兵种463'
            elif case=='earlyRobot':enemy['Type']='兵种474'
            elif case=='name':enemy['InstanceName']='cf6Boss_A06'
            elif case=='owner':enemy['Parameters']['cf6BossOwnerToken']='foreign'
            elif case=='source':enemy['Parameters']['产生源']='无'
            elif case=='transform':enemy['Parameters']['老头变身']=True
            else:waves.reverse()
            with self.subTest(case=case),self.assertRaises(ValueError):self.validate_cf6(data)

    def test_cf6_elder_preludes_are_not_copied_into_native_successor(self):
        data=self.cf6_boss_prelude_fixture();stage=data['maps'][0]
        stage.update(id='A20',background='cf6/CF6_A20_BG.swf')
        stage['mechanism']['elderFinale']=True
        plan=stage['bossEncounter'];plan['instanceName']='cf6Boss_A20'
        successor=copy.deepcopy(plan);successor['instanceName']='cf6Boss_A20__elderbot';plan['nextPhase']=successor
        boss=stage['stage']['Wave']['SubWave'][-1]['EnemyGroup']['Enemy'][0]
        boss.update(Type='兵种473',InstanceName='cf6Boss_A20',Parameters={'老头变身':True})
        original=copy.deepcopy(data)
        self.validate_cf6(data)
        self.assertEqual(original,data)

    def test_cf6_boss_rejects_mandatory_adds_in_main_wave(self):
        data=self.cf6_boss_fixture();data['maps'][0]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'].append({'Type':'兵种461','Level':60,'Quantity':1})
        with self.assertRaises(ValueError):self.validate_cf6(data)

    def test_cf6_boss_rejects_wrong_boss_or_name(self):
        for field,value in [('Type','兵种472'),('InstanceName','other'),('Quantity',2)]:
            data=self.cf6_boss_fixture();data['maps'][0]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.validate_cf6(data)

    def test_cf6_boss_caps_threshold_and_budget(self):
        changes=[lambda p:p.update(maxAlive=9),lambda p:p.update(maxRanged=3),lambda p:p.update(intervalFrames=0),
                 lambda p:p['groups'][1].update(hpRatio=1),lambda p:p['groups'][0]['enemies'][0].update(Quantity=128),
                 lambda p:p.update(maxRanged=0)]
        for change in changes:
            data=self.cf6_boss_fixture();change(data['maps'][0]['bossEncounter'])
            with self.assertRaises(ValueError):self.validate_cf6(data)

    def test_cf6_boss_ownership_not_authorable(self):
        for key in ('cf6BossOwnerToken','cf6SupportIdentity','publishStageEvent','产生源','InstanceName'):
            data=self.cf6_boss_fixture();data['maps'][0]['bossEncounter']['groups'][0]['enemies'][0]['Parameters'][key]='injected'
            with self.subTest(key=key),self.assertRaises(ValueError):self.validate_cf6(data)
        data=self.cf6_boss_fixture();data['maps'][0]['bossEncounter']['groups'][0]['enemies'][0]['InstanceName']='injected'
        with self.assertRaises(ValueError):self.validate_cf6(data)

    def test_cf6_boss_spawn_index_must_exist(self):
        data=self.cf6_boss_fixture();entry=data['maps'][0]['bossEncounter']['groups'][0]['enemies'][0];entry['SpawnIndex']=0
        with self.assertRaises(ValueError):self.validate_cf6(data)
        data['maps'][0]['stage']['SpawnPoint']={'Point':[{'x':100,'y':300}]};self.validate_cf6(data)
        entry['SpawnIndex']=1
        with self.assertRaises(ValueError):self.validate_cf6(data)

    def test_cf6_a20_human_boss_transform_is_forbidden(self):
        data=self.cf6_boss_fixture();stage=data['maps'][0];stage.update(id='A20',background='cf6/CF6_A20_BG.swf')
        stage['bossEncounter']['instanceName']='cf6Boss_A20'
        boss=stage['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0];boss.update(Type='兵种473',InstanceName='cf6Boss_A20')
        with self.assertRaises(ValueError):self.validate_cf6(data)
        boss['Parameters']={'老头变身':False};self.validate_cf6(data)

    def test_cf6_identity_and_route_rejected(self):
        for key,value in [('id','repair-campus'),('routeId','plan61'),('stageName','书中历险-修理大学')]:
            data=self.cf6_fixture();data[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError): self.validate_cf6(data)

    def test_cf6_actor_must_have_matching_xp_fixed_max_skills_and_eleven_equipment(self):
        for mutate in [lambda a:a.update(experience=0),lambda a:a.update(level=35),
                       lambda a:a['equipment'][0].update(enhancement=1),lambda a:a['equipment'][0].update(slot='刀'),
                       lambda a:a['skills'][0].update(level=0),lambda a:a['skills'].append(copy.deepcopy(a['skills'][0]))]:
            data=self.cf6_fixture();mutate(data['actor'])
            with self.assertRaises(ValueError): self.validate_cf6(data)

    def test_cf6_no_duplicate_vehicle_or_cinematic_maps(self):
        for identity in ['A07','A21','../A01','A23']:
            data=self.cf6_fixture();data['maps'][0]['id']=identity
            with self.subTest(identity=identity),self.assertRaises(ValueError): self.validate_cf6(data)
        data=self.cf6_fixture();data['maps']*=2
        with self.assertRaises(ValueError): self.validate_cf6(data)

    def test_cf6_vehicle_requires_authored_rules_and_its_own_map(self):
        spec=importlib.util.spec_from_file_location('vehicle_fixture',ROOT/'tools/cf6-vehicle/chapter_fragment.py')
        vehicle=importlib.util.module_from_spec(spec);spec.loader.exec_module(vehicle)
        node,_,_=vehicle.build(False)
        data=self.cf6_fixture();data['maps']=[node]
        self.validate_cf6(data)
        for mutate in [lambda m:m['mechanism'].pop('vehicle'),
                       lambda m:m['mechanism']['vehicle'].update(projectilePower=999),
                       lambda m:m['mechanism']['vehicle'].update(assetUrl='flashswf/arts/new/foreign.swf'),
                       lambda m:m.update(id='A08',background='cf6/CF6_A08_BG.swf'),
                       lambda m:m['stage']['Wave']['SubWave'].append(copy.deepcopy(m['stage']['Wave']['SubWave'][0]))]:
            invalid=copy.deepcopy(data);mutate(invalid['maps'][0])
            with self.assertRaises(ValueError): self.validate_cf6(invalid)

    def test_cf6_invalid_background_enemy_and_nonfinite_mechanism_rejected(self):
        for mutate in [lambda m:m.update(background='../wrong.swf'),lambda m:m.update(mechanism={'duration':float('nan')}),
                       lambda m:m['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0].update(Type='兵种999999'),
                       lambda m:m['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0].update(Quantity=0),
                       lambda m:m['stage'].update(BasicInformation={'BookBoss':{}})]:
            data=self.cf6_fixture();mutate(data['maps'][0])
            with self.assertRaises(ValueError): self.validate_cf6(data)

    def test_cf6_turret_wiring_schema_gate(self):
        # A01 必须携带精确炮塔规格;其余地图严禁携带;字段/坐标/朝向逐项拒绝坏例。
        data=self.cf6_fixture();self.validate_cf6(data)
        data=self.cf6_fixture();data['maps'][0]['mechanism'].pop('turrets')
        with self.assertRaisesRegex(ValueError,'turret spec fields'):
            self.validate_cf6(data)
        data=self.cf6_fixture();data['maps'][0]['mechanism']['turrets']=None
        with self.assertRaisesRegex(ValueError,'turret spec fields'):
            self.validate_cf6(data)
        data=self.cf6_fixture();data['maps'][0].update(id='A02',background='cf6/CF6_A02_BG.swf')
        with self.assertRaisesRegex(ValueError,'non-A01'):
            self.validate_cf6(data)
        for key,value in [('assetUrl','cf6/other.swf'),('linkage','other'),('filterMarker','other'),
                          ('fireIntervalFrames',17),('fireFrameOffset',12)]:
            data=self.cf6_fixture();data['maps'][0]['mechanism']['turrets'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError): self.validate_cf6(data)
        for mutate in [lambda t:t.pop(),lambda t:t[0].update(x=float('nan')),
                       lambda t:t[0].update(y=5001),lambda t:t[0].update(facing='left'),
                       lambda t:t[0].update(name='turretA')]:
            data=self.cf6_fixture();mutate(data['maps'][0]['mechanism']['turrets']['turrets'])
            with self.assertRaises(ValueError): self.validate_cf6(data)
        # 真实装配产物全章过门
        chapter=builder.normalize_book_units(json.loads((ROOT/'data/stages/books/cf6-sting.json').read_text(encoding='utf-8-sig')), builder.UnitRegistry.load(ROOT))
        units={u['id'] for u in json.loads((ROOT/'data/units/units.json').read_text('utf-8-sig'))}
        builder.validate_cf6(chapter,self.items,self.skills,units,require_backgrounds=False)


class Cf6TransportContractTests(unittest.TestCase):
    def setUp(self):
        chapter=json.loads((ROOT/'data/stages/books/cf6-sting.runtime.json').read_text(encoding='utf-8-sig'))
        if not any('transport' in m['mechanism'] for m in chapter['maps']):
            transport_spec=importlib.util.spec_from_file_location('transport_assembly',ROOT/'tools/cf6-prototype/transport-assembly.py')
            transport=importlib.util.module_from_spec(transport_spec);transport_spec.loader.exec_module(transport)
            transport.adapt(chapter,require_swfs=False)
        self.maps={m['id']:m for m in chapter['maps']}

    def test_actual_three_transport_budgets_and_events(self):
        for identity in ('A09','A14','A18'):
            builder.validate_cf6_transport(self.maps[identity])

    def test_transport_preserves_its_wave_among_more_required_waves(self):
        stage=copy.deepcopy(self.maps['A09'])
        stage['stage']['Wave']['SubWave'].append({'WaveInformation':{'Duration':0,'FinishRequirement':0},
            'EnemyGroup':{'Enemy':[{'Type':'兵种461','Level':45,'Quantity':2,'SpawnIndex':'left'}]}})
        builder.validate_cf6_transport(stage)
        stage['stage']['Wave']['SubWave'][-1]['EnemyGroup']['Enemy'][0]['TriggerEvent']=copy.deepcopy(
            stage['stage']['Wave']['SubWave'][1]['EnemyGroup']['Enemy'][0]['TriggerEvent'])
        with self.assertRaises(ValueError):builder.validate_cf6_transport(stage)

    def test_pods_stay_unique_when_a15_has_later_waves(self):
        chapter={'maps':copy.deepcopy(list(self.maps.values()))}
        stage=next(m for m in chapter['maps'] if m['id']=='A15')
        stage['stage']['Wave']['SubWave'].append({'WaveInformation':{'Duration':0,'FinishRequirement':0},
            'EnemyGroup':{'Enemy':[{'Type':'兵种461','Level':51,'Quantity':3,'SpawnIndex':'left'}]}})
        builder.validate_cf6_interactive_props(chapter)
        stage['stage']['Wave']['SubWave'][-1]['EnemyGroup']['Enemy'][0]=copy.deepcopy(
            stage['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0])
        with self.assertRaises(ValueError):builder.validate_cf6_interactive_props(chapter)

    def test_transport_geometry_and_native_identity_rejected(self):
        mutations=[lambda s:s.update(id='foreign'),lambda s:s.update(sourceSprite=1869),
            lambda s:s.update(frames=28),lambda s:s.update(dispatchFrame=28),
            lambda s:s.update(subWaveIndex=0),lambda s:s.update(x=float('nan')),
            lambda s:s.update(artMatrix=[0,0,0,0,0,0]),lambda s:s.update(hitBounds=[0,0,0,0]),
            lambda s:s.update(extra=True),lambda s:s.update(url='flashswf/foreign.swf')]
        for mutate in mutations:
            stage=copy.deepcopy(self.maps['A09']);mutate(stage['mechanism']['transport'])
            with self.assertRaises(ValueError):builder.validate_cf6_transport(stage)

    def test_transport_event_owner_and_conserved_quantity_rejected(self):
        for kind in ('missingOwner','missingEvent','foreignToken','quantity','duplicateEvent','interval','booleanSpawn','unreviewedMap'):
            stage=copy.deepcopy(self.maps['A09']);enemy=stage['stage']['Wave']['SubWave'][1]['EnemyGroup']['Enemy'][0]
            if kind=='missingOwner':del stage['mechanism']['transport']
            elif kind=='missingEvent':del enemy['TriggerEvent']
            elif kind=='foreignToken':enemy['TriggerEvent']['Parameters']=['foreign']
            elif kind=='quantity':enemy['Quantity']+=1
            elif kind=='interval':enemy['Interval']=100
            elif kind=='booleanSpawn':enemy['SpawnIndex']=False
            elif kind=='duplicateEvent':stage['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0]['TriggerEvent']=copy.deepcopy(enemy['TriggerEvent'])
            else:stage['id']='A08'
            with self.subTest(kind=kind),self.assertRaises(ValueError):builder.validate_cf6_transport(stage)


if __name__ == '__main__':
    unittest.main()
