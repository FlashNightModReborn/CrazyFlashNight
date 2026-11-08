"""The fixed roster's machinegun exception is a time budget, with native cadence."""
import copy
import json
import unittest
from pathlib import Path
import fixed_roster as fixed


class MachinegunSuppressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=fixed.read_source()
        cls.items=fixed.item_catalog()
        cls.runtime=fixed.runtime_catalog(cls.source,cls.items)

    def profile(self,row):
        return self.runtime['profiles'][self.runtime['identities'][row['unitIdentity']]['profileId']]

    def test_exact_weapon_scope(self):
        selected=[]
        for row in self.source['roster']:
            kind=self.items[row['primary']['name']].get('weapontype')
            profile=self.profile(row)
            self.assertEqual(kind in ('机枪','压制机枪'),'suppression' in profile['program'],row['unitIdentity'])
            if kind in ('机枪','压制机枪'):
                selected.append(row['unitIdentity'])
                spec=profile['program']['suppression']
                self.assertEqual((row['primary']['name'],kind,60,30),
                    (spec['weaponName'],spec['weaponType'],spec['fireFrames'],spec['recoveryFrames']))
        self.assertEqual(19,len(selected))

    def test_native_per_trigger_payload_is_unchanged(self):
        for row in self.source['roster']:
            profile=self.profile(row)
            if 'suppression' not in profile['program']:continue
            before=row['nominalFireBudget'];after=profile['budget']
            self.assertEqual(before['primarySplit'],after['primarySplit'])
            old_units=before.get('primaryFinalDamageUnitsPerAction',before['primaryProjectilesPerAction'])/before['primaryTriggerLimit']
            self.assertEqual(old_units,after['primaryFinalDamageUnitsPerAction']/after['primaryTriggerLimit'])
            self.assertEqual(before['sidearmSynchronizedTriggerLimit'],after['sidearmSynchronizedTriggerLimit'])
            self.assertEqual(before['sidearmProjectilesPerAction'],after['sidearmProjectilesPerAction'])

    def test_each_primary_cycle_has_exactly_two_seconds(self):
        for row in self.source['roster']:
            profile=self.profile(row)
            if 'suppression' not in profile['program']:continue
            self.assertEqual(60,profile['budget']['primaryTriggerLimit'])
            for variant in ('stages','dual','phase2','fallback','shield','grenade','pressure'):
                stages=profile['program'].get(variant,[])
                shots=[s for s in stages if s['kind']=='fire' and s['mode']=='primary']
                if not shots:continue
                self.assertEqual(60,sum(s['frames'] for s in shots),(row['unitIdentity'],variant))
                self.assertEqual(30,stages[-1]['frames'])
                self.assertTrue(all(s['events']==s['frames'] and s['gap']==1 for s in shots))
                self.assertLessEqual(sum(s['events'] for s in shots),profile['budget']['primaryTriggerLimit'])

    def test_other_weapons_keep_original_trigger_budgets(self):
        fields=('primaryTriggerLimit','primarySplit','primaryProjectilesPerAction','longgunWithSubProjectilesPerAction',
                'sidearmSynchronizedTriggerLimit','sidearmProjectilesPerAction','maxPlannedActionProjectiles')
        for row in self.source['roster']:
            profile=self.profile(row)
            if 'suppression' in profile['program']:continue
            for key in fields:self.assertEqual(row['nominalFireBudget'][key],profile['budget'][key],(row['unitIdentity'],key))
            self.assertLessEqual(profile['budget']['primaryTriggerLimit'],8)
            self.assertLessEqual(profile['budget']['maxGrantedDamageUnits'],14)
            self.assertEqual(row['aiBlueprint']['existingScalarOverrides'],profile['scalars'])

    def test_compile_still_rejects_extra_auxiliary_or_dual_shots(self):
        import soldier_programs
        for row in self.source['roster']:
            profile=copy.deepcopy(self.profile(row))
            if 'suppression' not in profile['program']:continue
            program=profile['program']
            program['stages'].insert(-1,soldier_programs.warning(1,'sub'))
            program['stages'].insert(-1,soldier_programs.fire(profile['extensions']['subweaponBurstLimit']+1,'sub'))
            with self.assertRaises(ValueError):soldier_programs.validate(program,profile)
            break


if __name__=='__main__':
    unittest.main()
