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
        cls.source = builder.resolve_book_choices(json.loads(builder.SOURCE.read_text(encoding='utf-8')))
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


if __name__ == '__main__':
    unittest.main()
