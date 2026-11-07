"""Source identity, exact equipment and relocation regressions for fixed158."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
import fixed_roster as fixed

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('fixed_baseline_builder', HERE / 'build-route.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def groups(book):
    for stage in book['maps']:
        for enemy in builder.all_enemies(stage):
            if 'cf6FixedSlots' in enemy.get('Parameters', {}):
                yield stage, enemy


class FixedRosterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.book = json.loads(builder.build(include_fixed=False)[builder.OUTPUT])
        cls.source = fixed.read_source()
        cls.items = fixed.item_catalog()
        cls.compiled = fixed.compile_slots(cls.book, cls.source, cls.items)
        cls.projected = fixed.apply(cls.book, cls.compiled)

    def reject(self, change):
        source = copy.deepcopy(self.source)
        change(source)
        with self.assertRaises(ValueError):
            fixed.compile_slots(self.book, source, self.items)

    def test_complete_bijection_and_independent_serialized_slots(self):
        slots = [s for _, e in groups(self.projected) for s in e['Parameters']['cf6FixedSlots']]
        self.assertEqual(158, len(slots))
        self.assertEqual(158, len({s['parameters']['cf6UnitIdentity'] for s in slots}))
        self.assertEqual(100, self.compiled['counts']['sources'])
        self.assertEqual(101, len(list(groups(self.projected))))
        for _, enemy in groups(self.projected):
            self.assertEqual(list(range(enemy['Quantity'])), [s['ordinal'] for s in enemy['Parameters']['cf6FixedSlots']])

    def test_projection_does_not_mutate_source_book_or_compile_result(self):
        before = fixed.canonical(self.book), fixed.canonical(self.compiled)
        output = fixed.apply(self.book, self.compiled)
        first = next(groups(output))[1]['Parameters']['cf6FixedSlots'][0]
        first['parameters']['称号'] = 'test edit'
        self.assertEqual(before, (fixed.canonical(self.book), fixed.canonical(self.compiled)))

    def test_relocations_remove_original_seats_and_preserve_identity(self):
        maps = {m['id']: m for m in self.projected['maps']}
        moved = maps['A17']['bossEncounter']['groups'][0]['enemies'][:2]
        self.assertEqual(['CF6-C-PE-R-06', 'CF6-N-SW-01'],
                         [e['Parameters']['cf6FixedSlots'][0]['parameters']['cf6UnitIdentity'] for e in moved])
        original = maps['A17']['stage']['Wave']['SubWave'][2]['EnemyGroup']['Enemy'][6]
        self.assertEqual(3, original['Quantity'])
        robot = maps['A20']['bossEncounter']['nextPhase']['groups'][0]['enemies'][0]
        slot = robot['Parameters']['cf6FixedSlots'][0]
        self.assertEqual('CF6-M-IX', slot['parameters']['cf6UnitIdentity'])
        self.assertEqual('A20.W01.E01.I01', slot['parameters']['cf6SourceSeat'])

    def test_random_elite_overrides_retired_without_broadening_other_rewards(self):
        self.assertEqual([], self.projected['economy']['eliteWeapons'])
        for key in ('randomWeapons', 'choices'):
            self.assertEqual(self.book['economy'][key], self.projected['economy'][key])
        for _, enemy in groups(self.projected):
            self.assertNotIn('cf6EliteQuota', enemy['Parameters'])
            self.assertEqual([], enemy['Parameters']['掉落物'])
            self.assertIs(enemy['Parameters']['不掉装备'], True)

    def test_g1111_false_and_true_remain_distinct_boolean_instances(self):
        slots = {s['parameters']['cf6UnitIdentity']: s['parameters'] for _, e in groups(self.projected)
                 for s in e['Parameters']['cf6FixedSlots']}
        a, b = slots['CF6-M-XX'], slots['CF6-M-V']
        self.assertIs(a['长枪']['value']['isRocketMode'], False)
        self.assertIs(b['长枪']['value']['isRocketMode'], True)
        self.assertIsNot(a['长枪']['value'], b['长枪']['value'])
        self.assertIsNot(a['长枪']['value']['mods'], b['长枪']['value']['mods'])

    def test_display_names_do_not_assign_identity(self):
        source = copy.deepcopy(self.source)
        for row in source['roster']:
            row['displayName'] = 'same displayed title'
        compiled = fixed.compile_slots(self.book, source, self.items)
        ids = [s['parameters']['cf6UnitIdentity'] for rows in compiled['slots'].values() for s in rows]
        self.assertEqual(158, len(set(ids)))

    def test_duplicate_identity_rejected(self):
        self.reject(lambda s: s['roster'][1].update(unitIdentity=s['roster'][0]['unitIdentity']))

    def test_missing_or_duplicate_instance_ordinal_rejected(self):
        def change(source):
            row = next(r for r in source['roster'] if r['sourceInstanceOrdinal'] > 0)
            row['sourceInstanceOrdinal'] = 0
        self.reject(change)

    def test_unknown_tactic_rejected(self):
        self.reject(lambda s: next(r for r in s['roster'] if r['roleClass'] == 'instructor')
                    ['aiBlueprint']['proposedExtensions'].update(majorTactic='unimplemented'))

    def test_phase_rewrite_and_multiplier_change_rejected(self):
        self.reject(lambda s: s['roster'][0].update(startingPhase=1))
        self.reject(lambda s: s['roster'][0].update(difficultyScale=99))

    def test_string_false_and_boolean_enhancement_rejected(self):
        self.reject(lambda s: next(r for r in s['roster'] if r['unitIdentity'] == 'CF6-M-XX')
                    ['primary']['instanceValueOverrides'].update(isRocketMode='false'))
        self.reject(lambda s: s['roster'][0]['primary'].update(enhancement=True))

    def test_incompatible_mod_and_weapon_string_drift_rejected(self):
        def wrong_mod(source):
            primary = source['roster'][0]['primary']
            primary['mods'] = ['霰弹枪口收束器']
            primary['serialized'] = primary['name'] + '#' + str(primary['enhancement']) + '##霰弹枪口收束器'
        self.reject(wrong_mod)
        self.reject(lambda s: s['roster'][0]['primary'].update(serialized='AK47#1##'))

    def test_invalid_budget_and_nonfinite_geometry_rejected(self):
        self.reject(lambda s: s['roster'][0]['nominalFireBudget'].update(maxPlannedActionProjectiles=15))
        self.reject(lambda s: s['roster'][0]['proposedSpawn'].update(x=float('nan')))

    def test_historical_route_cannot_be_overwritten(self):
        historical = copy.deepcopy(self.book)
        historical['routeId'] = 'historical'
        with self.assertRaises(ValueError):
            fixed.compile_slots(historical, self.source, self.items)

    def test_exact_tier_admission_and_actor_profile_fingerprint(self):
        def unknown_tier(source):
            row=next(r for r in source['roster'] if r['primary'].get('tier'))
            row['primary']['tier']='unknown'
        self.reject(unknown_tier)
        def wrong_form(source):
            row=next(r for r in source['roster'] if r['primary'].get('tier'))
            row['primary']['form']='data'
        self.reject(wrong_form)
        self.reject(lambda source: source['roster'][0]['primary'].update(enhancement=8))
        originals={r['unitIdentity']:r for r in self.source['roster']}
        for slots in self.compiled['slots'].values():
            for slot in slots:
                p=slot['parameters'];fp=p['cf6FirepowerProfile']
                self.assertEqual((1,2),(fp['v'],fp['s']))
                for i,key in enumerate(('primary','secondary1','secondary2')):
                    authored=originals[p['cf6UnitIdentity']][key]
                    if authored:
                        self.assertEqual([authored['name'],authored['tier']],fp['g'][i][:2])

    def test_materialized_validation_rejects_tampering_without_count_changes(self):
        chapter=json.loads(builder.build()[builder.OUTPUT])
        fixed.validate_materialized(chapter)
        def first(data):
            return next(groups(data))[1]['Parameters']['cf6FixedSlots'][0]
        changes=[lambda d:first(d).__setitem__('x',first(d)['x']+1),
                 lambda d:first(d)['parameters'].__setitem__('长枪','AK47#1##'),
                 lambda d:first(d)['parameters'].__setitem__('cf6SourceSeat','wrong-seat'),
                 lambda d:d['type61']['soldiers']['lootPolicy']['caps'].__setitem__('packages',7),
                 lambda d:d['type61']['soldiers']['profiles'].pop(next(iter(d['type61']['soldiers']['profiles']))),
                 lambda d:next(m for m in d['maps'] if m['id']=='A17')['bossEncounter'].__setitem__('intervalFrames',1)]
        for change in changes:
            candidate=copy.deepcopy(chapter);change(candidate)
            with self.subTest(change=changes.index(change)),self.assertRaises(ValueError):
                fixed.validate_materialized(candidate)

    def test_all_authored_positions_clear_the_current_static_map_polygons(self):
        spec=importlib.util.spec_from_file_location('fixed_spawn_geometry',HERE.parent/'cf6-map-runtime/geometry.py')
        geometry=importlib.util.module_from_spec(spec);spec.loader.exec_module(geometry)
        environments={e.findtext('BackgroundURL'):e for e in ET.parse(builder.ROOT/'data/environment/stage_environment.xml').getroot()}
        for row in self.source['roster']:
            env=environments['CF6_'+row['mapId']+'_BG.swf']
            x,y=row['proposedSpawn']['x'],row['proposedSpawn']['y']
            bounds=[float(env.findtext(k)) for k in ('Xmin','Ymin','Xmax','Ymax')]
            polygons=[[[float(v) for v in point.text.split(',')] for point in collision.findall('Point')]
                      for collision in env.findall('Collision')]
            with self.subTest(identity=row['unitIdentity']):
                self.assertTrue(bounds[0]<=x<=bounds[2] and bounds[1]<=y<=bounds[3])
                self.assertFalse(any(geometry.point_inside([x,y],polygon) for polygon in polygons))


if __name__ == '__main__':
    unittest.main()
