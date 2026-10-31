"""Audit the Type61 authoring closure against independent economic invariants."""
import collections
import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from choice_reward_catalog import item_catalog, load, runtime_catalog
spec=importlib.util.spec_from_file_location('type61_builder',HERE/'build-route.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)


class Type61RouteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=json.loads(builder.SOURCE.read_text('utf8'))
        cls.outputs=builder.build()
        cls.chapter=json.loads(cls.outputs[builder.OUTPUT])
        cls.config=cls.chapter['type61']
        cls.items=item_catalog()
        cls.base=json.loads(builder.BASE.read_text('utf8'))
        cls.maps={m['id']:m for m in cls.chapter['maps']}

    def test_generated_closure_is_current_and_repeatable(self):
        self.assertEqual(self.outputs,builder.build())
        for path,content in self.outputs.items():
            with self.subTest(path=path.name): self.assertEqual(content,path.read_bytes())

    def test_exact_fixed_budget_and_a16_frontloading(self):
        rows=self.config['checkpoints']
        self.assertEqual([4720000,100000,10000,1640],[sum(r[k] for r in rows) for k in ('money','kpoints','stones','skillPoints')])
        self.assertEqual(4750000,self.chapter['startingMoney']+sum(r['money'] for r in rows))
        self.assertEqual(7500,sum(r['stones'] for r in rows[:16]))
        self.assertEqual(100000,sum(r['kpoints'] for r in rows[:16]))
        self.assertEqual(78000,sum(r['kpoints'] for r in rows[:12]))
        self.assertEqual((1500000,78000),(self.source['startingMoney']+sum(r['money'] for r in rows[:10]),sum(r['kpoints'] for r in rows[:10])))
        self.assertEqual([36,37,38,39,40,41,42,43,44,45,46,48,49,50,52,55,56,58,60],[r['level'] for r in rows])

    def test_first_instructor_defense_uses_only_money_already_received_on_arrival(self):
        spec=importlib.util.spec_from_file_location('defense_acquisition',HERE/'acquisition-budget.py')
        budget=importlib.util.module_from_spec(spec);spec.loader.exec_module(budget)
        row=budget.report(through_node='A10',purchase_node='A11',enhancements=[7]*10,primaries=['M134'])['routes'][0]
        self.assertEqual((1500000,78000,2160,0),(row['fixedGold'],row['fixedK'],row['requiredStones'],row['missingStones']))
        self.assertEqual(1460000,row['totalGoldAfterFixedK'])
        self.assertEqual(40000,row['balanceBeforeDropsAndSales'])
        for item in [e['name'] for e in self.source['actor']['equipment'] if e['name'].startswith('61式')]:
            self.assertLessEqual(int(self.items['钛合金'+item].findtext('data/level')),45)
        self.assertLessEqual(int(self.items['钛合金P90'].findtext('data/level')),45)

    def test_sp_presets_free_points_and_natural_growth(self):
        skills={s.findtext('Name'):s for s in ET.parse(ROOT/'data/skills/skills.xml').findall('Skill')}
        paid=sum(int(skills[s['name']].findtext('UnlockSP'))+(s['level']-1)*int(skills[s['name']].findtext('UpgradeSP')) for s in self.chapter['actor']['skills'])
        self.assertEqual(1510,paid)
        natural=sum(60 if n<=40 else 70 if n<=50 else 80 for n in range(36,61))
        self.assertEqual(6000,paid+self.chapter['startingSkillPoints']+natural+1640)
        self.assertEqual(1,next(s['level'] for s in self.chapter['actor']['skills'] if s['name']=='铁匠'))
        self.assertFalse(set(self.source['blockedSkills']) & set(self.config['learnableSkills']))
        self.assertTrue({'炼金','逆向'} <= set(self.config['learnableSkills']))

    def test_nine_piece_budget_has_only_five_base_armor_instances(self):
        gear=self.chapter['actor']['equipment']
        self.assertEqual(['战斗狂人军牌'],[e['name'] for e in gear if e['slot']=='颈部装备'])
        armor=[e for e in gear if e['slot']!='颈部装备']
        self.assertEqual(5,len(armor));self.assertEqual(5,len({e['slot'] for e in armor}))
        self.assertTrue(all(e['enhancement']==1 and e['name'].startswith('61式') for e in armor))
        self.assertEqual(17372868,self.chapter['actor']['experience'])
        self.assertEqual(2,sum(p['Name']=='极品UZI战术版' for p in self.maps['A01']['stage']['Pickups']['Pickup']))

    def test_material_coverage_and_exact_stone_delivery(self):
        rows=[r for value in self.source['materialDeliveries'].values() for r in value]
        totals=collections.Counter()
        for row in rows: totals[row['name']]+=row['count']
        self.assertEqual({'传感器':10,'高耐力橡胶':10,'红外夜视仪':1},dict(totals))
        self.assertEqual(579800,sum(int(self.items[n].findtext('price'))*v for n,v in totals.items()))
        self.assertEqual(10000,sum(r['count'] for rows in self.config['deliveryItems'].values() for r in rows if r['name']=='强化石'))
        self.assertEqual(2,sum(p['Value'] for m in self.maps.values() for p in m['stage']['Pickups']['Pickup'] if p['Name']=='强化石'))

    def test_medicine_ammo_and_revives_match_the_m4_baseline(self):
        totals=collections.Counter()
        for rows in self.config['deliveryItems'].values():
            for row in rows: totals[row['name']]+=row['count']
        # Exactly one initial gun choice contributes its own eight main reloads.
        bundles={b['id']:b for b in load()['bundles']}
        starter=next(b for b in bundles.values() if b['id'].startswith('cf6.type61.starter.') and b['items'][0]['itemName']=='M4A1战术版')
        for row in starter['items']: totals[row['itemName']]+=row['quantity']
        ammo={n:v for n,v in totals.items() if self.items.get(n) is not None and self.items[n].findtext('use')=='弹夹'}
        self.assertEqual({'突击步枪通用弹药':24,'冲锋枪达姆弹弹药':12,'机枪贫铀穿甲弹':8,'冲锋枪钢芯穿甲弹':24,'能量电池':6,'榴弹弹药':12},ammo)
        drugs={n:v for n,v in totals.items() if self.items.get(n) is not None and self.items[n].findtext('use')=='药剂'}
        self.assertEqual(119,sum(drugs.values()))
        self.assertEqual(439600,sum(int(self.items[n].findtext('price'))*v for n,v in drugs.items()))
        self.assertEqual(168400,sum(int(self.items[n].findtext('price'))*v for n,v in ammo.items()))
        self.assertEqual(4,totals['复活币'])
        self.assertEqual(['大HP药剂','大MP药剂','净化药剂','狴犴·零型','狻猊·一型','囚牛·一型','睚眦·一型','螭吻·一型'],[r['name'] for r in self.config['deliveryItems']['TUTORIAL'][:8]])

    def test_initial_ammo_follows_all_three_choices(self):
        starters=[b for b in load()['bundles'] if b['id'].startswith('cf6.type61.starter.')]
        self.assertEqual(3,len(starters))
        for bundle in starters:
            gun,ammo=bundle['items']
            self.assertEqual(self.items[gun['itemName']].findtext('data/clipname'),ammo['itemName'])
            self.assertEqual(8,ammo['quantity'])
        self.assertFalse(any(r['name']=='突击步枪通用弹药' for r in self.config['deliveryItems']['TUTORIAL']))

    def test_no_old_authored_medicine_ammo_or_currency_layer_remains(self):
        names=[]
        for stage in self.chapter['maps']:
            names.extend(p['Name'] for p in stage['stage']['Pickups']['Pickup'])
            for enemy in builder.all_enemies(stage): names.extend(d['名字'] for d in enemy.get('Parameters',{}).get('掉落物',[]))
        self.assertFalse({'金币','金钱','K点','技能点','经验值'} & set(names))
        self.assertFalse(any(self.items[n].findtext('use') in ('药剂','弹夹','战场补给') for n in names))

    def test_a04_keeps_every_original_choice_without_a_second_gun(self):
        row=next(r for r in self.chapter['economy']['randomWeapons'] if r['mapId']=='A04')
        replacements=self.config['a04ReplacementPacks']
        pools={p['itemName']:p for p in runtime_catalog(load())}
        for option in row['choices']:
            if option['weapon']=='HKSL8EX': self.assertEqual('',replacements[option['weapon']]);continue
            pool=pools[replacements[option['weapon']]]
            entries=pool['groups'][0]['entries']
            self.assertEqual(2,len(entries));self.assertEqual(2,pool['groups'][0]['draw'])
            counts=[collections.Counter(r['itemName'] for r in b['entries']) for b in entries]
            self.assertIn(collections.Counter({option['weapon']:option.get('weaponCount',1)}),counts)
            self.assertIn(collections.Counter({'HKSL8EX':1}),counts)

    def test_all_ammunition_is_bought_from_a01_and_stars_are_absent(self):
        for node in builder.SHOP_NODES:
            path=ROOT/('data/shops/npcs/书中-CF6六一-'+node+'.json')
            names=set(json.loads(self.outputs[path])['catalog'].values())
            self.assertTrue(set(self.source['ammoCatalog'])<=names)
            self.assertFalse(set(self.source['ordinaryConstellations']+['血色光剑天秤','复活币'])&names)
            self.assertFalse(any(n.startswith('钛合金61式') for n in names))
        self.assertEqual(['SVD','钛合金P90','战术巴雷特'],self.config['kShopLate'])

    def test_acquisition_channels_and_build_enablers(self):
        from cf6_acquisition import channels
        gold,kpoints,recipes=channels()
        for node in builder.SHOP_NODES:
            stock=set(json.loads(self.outputs[ROOT/('data/shops/npcs/书中-CF6六一-'+node+'.json')])['catalog'].values())
            self.assertNotIn('M134暴力版',stock)
            for name in stock:
                if self.items[name].findtext('type')=='武器':self.assertIn(name,gold,name)
        early=set(json.loads(self.outputs[ROOT/'data/shops/npcs/书中-CF6六一-A01.json'])['catalog'].values())
        self.assertTrue({'M134','RPG','M249','Desert Eagle','可充锂电池','战术导轨','M203榴弹发射器'}<=early)
        self.assertEqual('A16',self.config['kShopUnlocks']['M134暴力版'])
        for key in ('randomWeapons','eliteWeapons'):
            self.assertFalse(any(x['weapon']=='M134暴力版' for row in self.chapter['economy'][key] for x in row['choices']))
        for pool in load()['pools']:
            if pool['scope'].get('bookId')=='cf6-sting':
                bundles={b['id']:b for b in load()['bundles']}
                self.assertFalse(any(bundles[e['bundleId']].get('weapon')=='M134暴力版' for group in pool['groups'] for e in group['entries']))
        self.assertEqual(50000,min(x['price'] for x in kpoints['M134暴力版']))
        self.assertEqual('A05',self.config['recipeUnlocks']['craft.plugin.009'])
        self.assertEqual('A11',self.config['recipeUnlocks']['craft.iron-spear.006'])
        later=set(json.loads(self.outputs[ROOT/'data/shops/npcs/书中-CF6六一-A11.json'])['catalog'].values())
        self.assertTrue({'手枪卡宾转换套件','下挂喷火器','骨约晨星','光棱射线弹-强化'}<=later)
        self.assertNotIn('灰蛊蚀刻霰弹',later)
        self.assertTrue({'00号鹿弹','纳米执行单元'}<=later)

    def test_titanium_requires_one_corresponding_unified_piece(self):
        rows=json.loads(self.outputs[HERE/'recipes.generated.json'])
        self.assertEqual(5,len(rows))
        for row in rows:
            self.assertIn(row['name'],self.items)
            self.assertTrue(all(m.split('#')[0] in self.items for m in row['materials']))
            self.assertEqual(['统合'+row['name'][3:]+'#1'],row['materials'])
            self.assertEqual((100000,9000),(row['price'],row['kprice']))
            self.assertEqual('A11',self.config['recipeUnlocks'][row['recipeId']])
        self.assertEqual(475000,sum(r['price']*95//100 for r in rows))
        self.assertEqual(42750,sum(r['kprice']*95//100 for r in rows))

    def test_hell_is_limited_to_boss_groups_and_elevators(self):
        for stage in self.chapter['maps']:
            boss=stage.get('bossEncounter',{})
            for wave in stage['stage']['Wave']['SubWave']:
                for enemy in wave['EnemyGroup']['Enemy']:
                    expected=2.5 if stage['id'] in ('A10','A13') or enemy.get('InstanceName')==boss.get('instanceName','__none__') else 1
                    self.assertEqual(expected,enemy.get('Parameters',{}).get('cf6DifficultyScale',1),(stage['id'],enemy['Type']))
            for phase in (boss,boss.get('nextPhase',{})):
                for group in phase.get('groups',[]):
                    self.assertTrue(all(e['Parameters']['cf6DifficultyScale']==2.5 for e in group['enemies']))
        for node in ('A10','A13'):
            enemies=self.maps[node]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy']
            self.assertEqual(4 if node=='A10' else 1,sum(e['Quantity'] for e in enemies))
        self.assertEqual('E2',self.maps['A13']['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0]['Parameters']['cf6EliteQuota'])

    def test_soldier_progression_and_loot_carriers(self):
        registry=builder.UnitRegistry.load(ROOT)
        counts={}
        for node,stage in self.maps.items():
            counter=collections.Counter()
            for enemy in builder.all_enemies(stage):
                unit=registry.resolve_type(enemy['Type']);p=enemy.get('Parameters',{})
                role={'兵种466':'ordinary','兵种467':'ordinary','兵种478':'elite','兵种479':'elite','兵种480':'instructor','兵种481':'instructor'}.get(unit)
                if role is None:continue
                counter[role]+=enemy['Quantity']
                if node<'A10':self.assertEqual('ordinary',role)
                if node<'A13':self.assertNotEqual('instructor',role)
                if node>='A18':self.assertEqual('instructor',role)
                if role in ('elite','instructor'):self.assertTrue(p.get('手枪') and p.get('手枪2'))
                if role in ('ordinary','instructor'):self.assertTrue(p.get('特种兵投掷物') in self.items,(node,unit))
                if p.get('cf6EliteQuota'):
                    self.assertEqual(1,enemy['Quantity'])
                    if p['cf6EliteQuota']!='E1':self.assertEqual('instructor',role)
                    self.assertEqual(p['长枪'],p['掉落物'][0]['名字'])
            counts[node]=counter
        self.assertEqual({'ordinary':8},counts['A06'])
        self.assertEqual({'ordinary':15},counts['A09'])
        self.assertEqual({'elite':4},counts['A10'])
        self.assertEqual({'instructor':1},counts['A13'])
        for node in ('A14','A15','A17'):self.assertEqual({'ordinary','elite','instructor'},set(counts[node]))
        units={x['id']:x['spritename'] for x in json.loads((ROOT/'data/units/units.json').read_text('utf-8-sig'))}
        props=ET.parse(ROOT/'data/enemy_properties/CF6重制敌人.xml')
        for unit in (466,467,478,479):self.assertIsNotNone(props.find(units[unit]+'/魔法抗性/精英'))
        for unit in (480,481):
            row=props.find(units[unit]);self.assertIsNone(row.find('魔法抗性/精英'))
            self.assertIsNotNone(row.find('魔法抗性/首领'))
            self.assertEqual(('8','9'),(row.findtext('标识/阶段'),row.findtext('标识/档次系数')))

    def test_throwables_reach_player_only_after_required_level(self):
        levels={'TUTORIAL':35,**{r['mapId']:r['level'] for r in self.source['checkpoints']}}
        for node,rows in self.source['throwableDeliveries'].items():
            for row in rows:
                self.assertLessEqual(int(self.items[row['name']].findtext('data/level')),levels[node])
                self.assertIn(row,self.config['deliveryItems'][node])
        self.assertEqual(5,sum(row['count'] for rows in self.source['throwableDeliveries'].values() for row in rows if row['name']=='战术核弹手雷'))

    def test_field_supplies_are_unique_and_pure(self):
        rows=self.config['fieldSupplies']
        self.assertEqual(59,len({(r['map'],r['wave'],r['phase']) for r in rows}))
        self.assertEqual(29,sum(r['high'] for r in rows))
        self.assertEqual(44,29+(59-29)*0.5)
        root=ET.fromstring(self.outputs[ROOT/'data/items/消耗品_CF6六一配给.xml'])
        entries={i.findtext('name'):i for i in root.findall('item')}
        heal=entries['61计划战场急救包'].findall('data/effects/effect')
        self.assertEqual(1,len(heal));self.assertEqual('heal',heal[0].get('type'))
        self.assertEqual(('25%','0','false'),(heal[0].get('hp'),heal[0].get('mp'),heal[0].get('scaleWithAlchemy')))
        ammo=entries['61计划战场弹药包'].findall('data/effects/effect')
        self.assertEqual(1,len(ammo));self.assertEqual('equipped',ammo[0].get('scope'))

    def test_random_stars_preserve_the_four_independent_ten_percent_draws(self):
        root=ET.fromstring(self.outputs[ROOT/'data/items/消耗品_CF6六一配给.xml'])
        boxes={i.findtext('name'):i for i in root.findall('item') if i.find('data/rewardPack') is not None}
        ordinary=boxes['61计划普通星座箱'].findall('data/rewardPack/entries/entry')
        self.assertEqual(set(self.source['ordinaryConstellations']),{e.findtext('itemName') for e in ordinary})
        self.assertEqual([1,1,1,1],[int(e.findtext('weight')) for e in ordinary])
        blood=boxes['61计划星座机缘箱'].findall('data/rewardPack/entries/entry')
        weights={e.findtext('itemName'):int(e.findtext('weight')) for e in blood}
        self.assertAlmostEqual(.1,weights['血色光剑天秤']/sum(weights.values()))
        self.assertEqual(4,sum(r['name']=='61计划星座机缘箱' for rows in self.config['deliveryItems'].values() for r in rows))

    def test_authoring_rejects_budget_and_phase_corruption(self):
        mutations=[lambda s:s['checkpoints'][0].__setitem__('money',35001),lambda s:s['checkpoints'][0].__setitem__('kpoints',True),
                   lambda s:s.__setitem__('startingSkillPoints',2560),lambda s:s['titaniumUpgrade'].__setitem__('kpointsPerPiece',0),
                   lambda s:s['fieldSupplies'].append(copy.deepcopy(s['fieldSupplies'][0])),lambda s:s['fieldSupplies'][0].__setitem__('wave',99),
                   lambda s:s['ammoCatalog'].pop(),lambda s:s['medicineDeliveries']['TUTORIAL'][0].__setitem__('count',-1),
                   lambda s:s['elevatorKeep']['A10'].append(5),lambda s:s.__setitem__('bloodSwordChance',100)]
        for mutation in mutations:
            source=copy.deepcopy(self.source);mutation(source)
            with self.subTest(mutation=mutations.index(mutation)):
                with self.assertRaises(ValueError): builder.build(source)


if __name__=='__main__': unittest.main(verbosity=2)
