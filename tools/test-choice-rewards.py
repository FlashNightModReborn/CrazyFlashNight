"""Authoring failures that could make a choice impossible or misleading in game."""
import copy
import json
import unittest
import xml.etree.ElementTree as ET
from choice_reward_catalog import ROOT, load, validate, validate_loadout, item_catalog, runtime_catalog, resolve_book_choices


class ChoiceCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = load()

    def reject(self, mutate):
        data = copy.deepcopy(self.catalog)
        mutate(data)
        with self.assertRaises(ValueError):
            validate(data)

    def test_current_book_checkpoints_resolve_only_their_pool(self):
        book = resolve_book_choices(json.loads((ROOT/'data/stages/books/repair-campus.json').read_text('utf-8')))
        self.assertEqual(len(book['buildChoices']), 2)
        for checkpoint, pool in zip(book['buildChoices'], self.catalog['pools']):
            self.assertEqual(checkpoint['choiceItem'], pool['itemName'])
            self.assertEqual(len(checkpoint['options']), 4)
            self.assertEqual([g['draw'] for g in pool['groups']], [2, 1])

    def test_revive_coin_is_a_single_advanced_candidate_not_legacy_crafting(self):
        pools = runtime_catalog(self.catalog)
        coins = [(i, option) for i,p in enumerate(pools) for g in p['groups'] for option in g['entries']
                 if any(e['itemName']=='复活币' for e in option['entries'])]
        self.assertEqual(len(coins),1)
        self.assertEqual(coins[0][0],1)
        self.assertEqual(coins[0][1]['entries'],[{'itemName':'复活币','quantity':1}])
        book = resolve_book_choices(json.loads((ROOT/'data/stages/books/repair-campus.json').read_text('utf-8')))
        self.assertEqual(sum(1 for c in book['buildChoices'] if c['poolId']==pools[1]['id']),1)
        self.assertTrue(all('items' not in option for c in book['buildChoices'] for option in c['options']))

    def test_runtime_supplies_include_real_underbarrel_ammunition(self):
        pools = runtime_catalog(self.catalog)
        option = next(e for g in pools[0]['groups'] for e in g['entries'] if e['id'] == 'campus.initial.2')
        contents = {e['itemName']: e['quantity'] for e in option['entries']}
        self.assertEqual(contents['M203榴弹发射器'], 1)
        self.assertEqual(contents['榴弹弹药'], 6)

    def test_no_rerolls_or_multiple_selections(self):
        for key, value in [('rerolls',1), ('chooseCount',2), ('chooseCount',True)]:
            self.reject(lambda d: d['pools'][0].update({key:value}))

    def test_positive_integer_weights_only(self):
        for value in [0,-1,0.5,True,10001]:
            self.reject(lambda d: d['pools'][0]['groups'][0]['entries'][0].update(weight=value))

    def test_no_duplicate_options_across_groups(self):
        self.reject(lambda d: d['pools'][0]['groups'][1]['entries'][0].update(bundleId='campus.initial.4'))

    def test_no_overdraw(self):
        self.reject(lambda d: d['pools'][0]['groups'][0].update(draw=len(d['pools'][0]['groups'][0]['entries']) + 1))

    def test_no_unknown_bundle(self):
        self.reject(lambda d: d['pools'][0]['groups'][0]['entries'][0].update(bundleId='missing'))

    def test_pool_level_rejects_unusable_weapons(self):
        self.reject(lambda d: d['pools'][0].update(maxItemLevel=1))

    def test_wrong_weapon_plugin_is_rejected(self):
        self.reject(lambda d: d['bundles'][0].update(mods=['M203榴弹发射器']))

    def test_missing_underbarrel_ammunition_is_rejected(self):
        self.reject(lambda d: d['bundles'][1]['consumables'].pop())

    def test_mutual_plugin_tags_are_rejected(self):
        self.reject(lambda d: d['bundles'][2]['mods'].append('脉冲式惯性阻尼器'))

    def test_shotgun_ammunition_is_an_alternative_not_two_installed_mods(self):
        self.reject(lambda d: d['bundles'][2]['mods'].append('八门金锁镇暴弹'))

    def test_level_thirteen_dual_blade_cannot_fit_three_mods(self):
        self.reject(lambda d: next(b for b in d['bundles'] if b['id'] == 'campus.advanced.4')['mods'].append('手柄皮'))

    def test_underbarrel_cards_have_compatible_book_guns_and_correct_ammo(self):
        book = json.loads((ROOT / 'data/stages/books/repair-campus.json').read_text('utf-8'))
        shop = json.loads((ROOT / 'data/shops/npcs/书中-迷之盔甲君.json').read_text('utf-8'))
        items = item_catalog()
        directory = ROOT / 'data/items/equipment_mods'
        mods = {m.findtext('name'): m for e in ET.parse(directory / 'list.xml').findall('items')
                for m in ET.parse(directory / e.text).findall('mod')}
        advanced = runtime_catalog(self.catalog)[1]
        cards = {o['id']: o for g in advanced['groups'] for o in g['entries']}
        for suffix in ['flame', 'storm', 'missile', 'revolver']:
            card = cards['campus.advanced.' + suffix]
            entries = {e['itemName']: e['quantity'] for e in card['entries']}
            plugin = next(n for n in entries if n in mods)
            ammo = mods[plugin].findtext('subweapon/reserveName')
            self.assertIn(ammo, entries)
            self.assertIn(ammo, shop['catalog'].values())
            self.assertTrue(1 <= entries[ammo] <= 6)
            option = dict(weapon='M4A1', mods=[plugin], consumables=[
                dict(name='突击步枪通用弹药', count=1), dict(name=ammo, count=entries[ammo])])
            self.assertIn('M4A1', book['maps'][3]['equipment'])
            validate_loadout(option, 13, items, mods)
            option['consumables'].pop()
            with self.assertRaises(ValueError): validate_loadout(option, 13, items, mods)
        battery_cards = [o for p in runtime_catalog(self.catalog) for g in p['groups'] for o in g['entries']
                         if any(e['itemName'] == '能量电池' for e in o['entries'])]
        self.assertEqual([o['id'] for o in battery_cards], ['campus.advanced.missile'])
        self.assertEqual(next(e['quantity'] for e in battery_cards[0]['entries'] if e['itemName'] == '能量电池'), 1)
        self.assertNotIn('能量电池', [e['name'] for e in book['ammoBundle']['contents']])

    def test_book_cannot_reference_another_runs_pool(self):
        data = copy.deepcopy(self.catalog)
        data['pools'][0]['scope']['bookId'] = 'other-book'
        book = json.loads((ROOT/'data/stages/books/repair-campus.json').read_text('utf-8'))
        with self.assertRaises(ValueError): resolve_book_choices(book, data)

    def test_ordinary_character_scope_is_supported(self):
        data = copy.deepcopy(self.catalog)
        data['pools'][0]['scope'] = {'kind':'character'}
        self.assertEqual(validate(data)['pools'][0]['scope'], {'kind':'character'})

    def test_future_schema_and_unknown_fields_are_rejected(self):
        self.reject(lambda d: d.update(schema='choice-rewards.v2'))
        self.reject(lambda d: d['pools'][0].update(clientSeed=123))

    def test_generic_medical_bundle_does_not_require_a_weapon(self):
        data = copy.deepcopy(self.catalog)
        bundle = data['bundles'][0]
        for key in ('weapon','mods','consumables'): del bundle[key]
        bundle['items'] = [{'itemName':'普通hp药剂','quantity':5}]
        validate(data)
        rows = [e for g in runtime_catalog(data)[0]['groups'] for e in g['entries']]
        self.assertEqual(next(e for e in rows if e['id'] == bundle['id'])['entries'], bundle['items'])
        bundle['items'] = [{'itemName':'UZI','quantity':2}]
        with self.assertRaises(ValueError): validate(data)


if __name__ == '__main__': unittest.main(verbosity=2)
