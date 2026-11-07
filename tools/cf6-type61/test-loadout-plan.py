"""Structural regressions for ordered rail installation and independent hands."""
import copy
import json
import unittest
import xml.etree.ElementTree as ET
import fixed_roster as fixed
import loadout_rules as rules


class LoadoutPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.items, cls.mods = fixed.item_catalog(), fixed.mod_catalog()
        cls.source = fixed.read_source()
        cls.plan = json.loads((fixed.HERE / 'soldier-loadout-plan.source.json').read_text('utf-8'))

    def gun(self, name='M4A1'):
        if name == 'M4A1':
            return fixed.effective_item(dict(name=name, form='data_fire', tier='狱火'), self.items)
        return copy.deepcopy(self.items[name])

    def validate(self, item, mods):
        rules.validate(item, mods, self.mods, self.items)

    def test_unexpanded_capacity_cannot_be_bypassed(self):
        with self.assertRaisesRegex(ValueError, 'slots exceeded'):
            self.validate(self.gun('M60E3'), ['透镜', '强化金属管'])

    def test_tier_inherits_base_default_slots_before_its_level_overlay(self):
        pistol = fixed.effective_item(dict(name='MP40', form='data_ice', tier='墨冰'), self.items)
        self.assertGreaterEqual(int(pistol.findtext('data/level')), 30)
        self.assertEqual(rules.capacity(pistol, [], self.mods), 2)
        self.assertEqual(rules.capacity(self.gun('M4A1'), [], self.mods), 3)

    def test_rail_must_be_installed_before_functional_pair(self):
        self.validate(self.gun(), ['战术鱼骨零件', '战术握把', '加长弹匣'])
        with self.assertRaisesRegex(ValueError, 'slots exceeded'):
            self.validate(self.gun('M60E3'), ['透镜', '战术鱼骨零件', '战术握把'])

    def test_rail_type_grant_is_distinct_from_conditional_tags(self):
        shotgun = self.gun('XM1014')
        self.validate(shotgun, ['战术鱼骨零件', '战术握把', '加长弹匣'])
        use, types, tags = rules.contexts(shotgun, ['战术鱼骨零件'], self.mods)
        self.assertIn('突击步枪', types)
        self.assertNotIn('突击步枪', use)
        self.assertNotIn('NOAH', tags)
        self.assertIn('NOAH', rules.contexts(self.gun(), ['战术鱼骨零件'], self.mods)[2])

    def test_duplicate_functional_socket_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Incompatible'):
            self.validate(self.gun(), ['战术鱼骨零件', '透镜', '小型液晶屏'])

    def test_closed_and_zero_slot_weapons_keep_factory_policy(self):
        with self.assertRaisesRegex(ValueError, 'Incompatible'):
            self.validate(self.gun('MG42战术版'), ['战术鱼骨零件'])
        with self.assertRaisesRegex(ValueError, 'slots exceeded'):
            self.validate(self.gun('极品UZI的KING版'), ['加长弹匣'])

    def test_plan_retains_weapon_and_underbarrel_identities(self):
        count = rails = sidearms = 0
        for row in self.source['roster']:
            for key in ('primary', 'secondary1', 'secondary2'):
                slot = row[key]
                if slot is None:
                    continue
                count += 1
                entry = self.plan['slots'][row['unitIdentity'] + '/' + key]
                self.assertEqual(slot['mods'], entry['after'])
                for name in ('M203榴弹发射器', '下挂霰弹枪'):
                    self.assertEqual(name in entry['before'], name in entry['after'])
                if key == 'primary':
                    rails += '战术鱼骨零件' in slot['mods']
                else:
                    sidearms += 1
                    self.assertLessEqual(len(slot['mods']), 1)
                    self.assertNotIn('手枪卡宾转换套件', slot['mods'])
        self.assertEqual((count, rails, sidearms), (282, 145, 124))

    def test_both_hands_have_no_shared_structural_context(self):
        for row in self.source['roster']:
            for key in ('secondary1', 'secondary2'):
                if row[key] is None:
                    continue
                slot = row[key]
                item = fixed.effective_item(slot, self.items)
                tags = rules.contexts(item, slot['mods'], self.mods)[2]
                self.assertEqual(tags, rules.words(item, 'inherentTags'))

    def test_material_capture_candidate_is_really_installed(self):
        for row in self.source['roster']:
            installed = {m for key in ('primary', 'secondary1', 'secondary2') if row[key] for m in row[key]['mods']}
            material = row['lootRules']['materialCandidate']
            self.assertTrue(material is None or material in installed, row['unitIdentity'])

    def test_recalculated_raw_and_independent_compensation_anchors(self):
        fire = fixed.firepower_source()
        enhance = {int(x.get('index')): float(x.text) for x in ET.parse(fixed.ROOT / 'data/equipment/equipment_config.xml').findall('.//LevelStatList/Level')}
        for row in self.source['roster']:
            for key, profile in fire['profiles'][row['unitIdentity']]['slots'].items():
                raw = rules.power(fixed.effective_item(row[key], self.items), row[key], self.mods, enhance)
                self.assertEqual(raw, profile['weaponOnlyRaw'])
                for stage, field in [(1, 'expectedB'), (2, 'expectedC')]:
                    self.assertAlmostEqual(rules.compensated(raw, row, profile, stage, key == 'primary'), profile[field], places=7)

    def test_positive_half_integer_power_anchors_use_authored_decimals(self):
        enhance = {12: 2.76}
        item = self.gun('远古诛神短枪')
        # Use the actual +12 config value, not a hand-entered approximation.
        enhance[12] = float(ET.parse(fixed.ROOT / 'data/equipment/equipment_config.xml').find(".//LevelStatList/Level[@index='12']").text)
        self.assertEqual(rules.power(item, dict(enhancement=12, mods=['强化金属管']), self.mods, enhance), 1840)
        self.assertEqual(rules.power(item, dict(enhancement=12, mods=['弹簧']), self.mods, enhance), 1827)


if __name__ == '__main__':
    unittest.main()
