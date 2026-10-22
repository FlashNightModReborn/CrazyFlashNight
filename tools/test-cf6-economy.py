"""Validate actual item/ammo/skill references and finite delivery ownership."""
import copy
import unittest
from choice_reward_catalog import item_catalog
from cf6_economy import validate_economy


class Cf6EconomyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.items = item_catalog()

    def weapon(self, name):
        return dict(weapon=name, ammo=self.items[name].findtext('data/clipname'), ammoCount=3)

    def fixture(self):
        rows = [dict(id=m, stage=dict(BasicInformation=dict(PlayerX=200,PlayerY=300),Wave=dict(SubWave=[dict(EnemyGroup=dict(Enemy=[]))]), Pickups=dict(Pickup=[])))
                for m in ('A04','A09','A13')]
        for index, quota in ((1,'E1'),(2,'E2')):
            rows[index]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy']=[
                dict(Type='兵种467', Quantity=1, Parameters=dict(cf6EliteQuota=quota))]
        return dict(actor=dict(skills=[dict(name='迅斩',level=10)]), maps=rows,
                    economy=dict(randomWeapons=[dict(mapId='A04',choices=[self.weapon('DD MK18战术版'),self.weapon('M60E3')])],
                                 eliteWeapons=[dict(mapId='A09',quota='E1',choices=[self.weapon('SAI GRY 幽灵')]),
                                               dict(mapId='A13',quota='E2',choices=[self.weapon('TTI Gen 12'),self.weapon('T181C')])],
                                 choices=[dict(mapId='A04',poolId='cf6.test',itemName='CF6 TEST')]))

    def catalog(self):
        return dict(schema='choice-rewards.v1',bundles=[dict(id='cf6.'+str(i),name='TEST',title='TEST',description='TEST',
                    grade='low',items=[dict(itemName='普通hp药剂',quantity=i+1)]) for i in range(3)],
                    pools=[dict(id='cf6.test',version=1,title='TEST',itemName='CF6 TEST',scope=dict(kind='book',bookId='cf6-sting'),
                                maxItemLevel=60,chooseCount=1,rerolls=0,groups=[dict(id='supplies',draw=2,entries=[
                                    dict(bundleId='cf6.'+str(i),weight=1) for i in range(3)])])])

    def check(self, book=None, catalog=None):
        validate_economy(self.fixture() if book is None else book,self.items,self.catalog() if catalog is None else catalog)

    def reject(self, change):
        book=self.fixture(); change(book)
        with self.assertRaises(ValueError): self.check(book)

    def test_valid_real_weapon_ammo_and_isolated_choices(self): self.check()

    def test_optional_economy_preserves_old_authored_fixtures(self):
        validate_economy({},self.items)

    def test_singleton_is_not_random_and_elite_two_has_alternatives(self):
        for key,index in [('randomWeapons',0),('eliteWeapons',1)]:
            self.reject(lambda b:b['economy'][key][index]['choices'].pop())

    def test_supplies_need_finite_world_spawn(self):
        self.reject(lambda b:b['maps'][0]['stage'].pop('BasicInformation'))
        self.reject(lambda b:b['maps'][0]['stage']['BasicInformation'].update(PlayerX=float('nan')))

    def test_ammunition_and_quantity_references(self):
        self.reject(lambda b:b['economy']['randomWeapons'][0]['choices'][0].update(ammo='普通hp药剂'))
        for value in (0,31,True,1.5):
            self.reject(lambda b:b['economy']['randomWeapons'][0]['choices'][0].update(ammoCount=value))

    def test_duplicate_and_foreign_weapon_sources(self):
        self.reject(lambda b:b['economy']['randomWeapons'][0]['choices'].append(self.weapon('SAI GRY 幽灵')))
        self.reject(lambda b:b['economy']['eliteWeapons'][1]['choices'].append(self.weapon('SAI GRY 幽灵')))
        self.reject(lambda b:b['economy']['randomWeapons'][0]['choices'].append(self.weapon('M60E3')))

    def test_fixed_pickup_or_ordinary_drop_cannot_duplicate_reserved_gun(self):
        self.reject(lambda b:b['maps'][0]['stage']['Pickups']['Pickup'].append(dict(Name='M60E3',Value=1)))
        self.reject(lambda b:b['maps'][0]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'].append(
            dict(Type='兵种461',Quantity=1,Parameters={'掉落物':[{'名字':'SAI GRY 幽灵'}]})))

    def test_elite_carrier_is_unique_single_and_exact_map(self):
        self.reject(lambda b:b['maps'][1]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0].update(Quantity=2))
        self.reject(lambda b:b['maps'][1]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0].update(Type='兵种461'))
        self.reject(lambda b:b['maps'][1]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'].__imul__(2))
        self.reject(lambda b:b['economy']['eliteWeapons'][0].update(mapId='A04'))
        self.reject(lambda b:b['economy']['eliteWeapons'].pop())

    def test_elite_support_is_consumable_without_authored_instance_name(self):
        book=self.fixture();enemies=book['maps'][1]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy']
        book['maps'][1]['bossEncounter']=dict(groups=[dict(enemies=enemies[:])]);enemies.clear();self.check(book)

    def test_exact_choice_scope_price_and_skill_ceiling(self):
        for change in [lambda c:c['pools'][0]['scope'].update(bookId='repair-campus'),
                       lambda c:c['bundles'][0].update(kCost=300),
                       lambda c:c['bundles'][0].update(skills=[dict(skillKey='迅斩',level=10)]),
                       lambda c:c['bundles'][0].update(skills=[dict(skillKey='口才',level=1000)]),
                       lambda c:c['bundles'][0].update(items=[dict(itemName='SAI GRY 幽灵',quantity=1)])]:
            catalog=self.catalog();change(catalog)
            with self.assertRaises(ValueError): self.check(catalog=catalog)

    def test_elite_replacement_cannot_silently_discard_other_rewards(self):
        self.reject(lambda b:b['maps'][1]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0]['Parameters'].update(
            {'掉落物':[{'名字':'金币'}]}))

    def test_choices_have_unique_delivery_and_live_fallback(self):
        self.reject(lambda b:b['economy']['choices'].__imul__(2))
        self.reject(lambda b:b['economy']['choices'].clear())
        self.reject(lambda b:b['economy']['choices'][0].update(itemName='other'))
        catalog=self.catalog()
        for b in catalog['bundles']: b['items']=[dict(itemName='M4A1',quantity=1)]
        with self.assertRaises(ValueError): self.check(catalog=catalog)

    def test_skill_candidate_may_retire_with_two_consumable_fallbacks(self):
        catalog=self.catalog();catalog['pools'][0]['groups'][0]['draw']=3
        catalog['bundles'][2].update(items=[],skills=[dict(skillKey='小跳',level=1)])
        self.check(catalog=catalog)

    def test_choice_pack_not_duplicated_by_static_pickup_or_drop(self):
        self.reject(lambda b:b['maps'][0]['stage']['Pickups']['Pickup'].append(dict(Name='CF6 TEST',Value=1)))
        self.reject(lambda b:b['maps'][1]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy'][0]['Parameters'].update(
            {'掉落物':[{'名字':'CF6 TEST'}]}))

if __name__ == '__main__': unittest.main(verbosity=2)
