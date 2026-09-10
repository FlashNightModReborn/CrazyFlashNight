"""Contract checks for the offline model; these do not execute Flash."""
import copy
import math
import unittest

import jk_followup as j


class FollowupContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.b = j.configured()

    def test_current_sixty_round_loadout(self):
        self.assertEqual(j.m.gun_stats(self.b, j.QJZ)["capacity"], 60)
        self.assertEqual(j.m.gun_stats(self.b, j.QJZ)["gap"], 9)
        self.assertNotIn("加长弹匣", self.b["items"][-1]["mods"])
        self.assertFalse(self.b["illegalItems"])

    def test_low_blade_does_not_win_full_pool_even_with_alchemy(self):
        values = []
        for level in j.CONFIG["bloodEnhancements"]:
            b = j.configured(blood_tier=level)
            values.append(b["hpMax"] * 1.3 + j.shield_capacity(b, 24))
        self.assertEqual(values, sorted(values))
        self.assertGreater(values[-1], values[0])

    def test_blood_basis_ignores_external_negative_hp_and_overheal(self):
        b = copy.deepcopy(self.b)
        old = j.shield_capacity(b, 24)
        b["hpMax"] += 50000
        b["stats"]["hp"] -= 20000
        self.assertEqual(j.shield_capacity(b, 24), old)

    def test_true_pool_requires_blood(self):
        event = {"bullet": "test", "split": 1, "type": "真伤", "power": 1000, "slay": 0}
        states = []
        for tier in [0, 13]:
            s = j.CandidateEnergy(j.configured(blood_tier=tier))
            s.pulse()
            hp = s.hp
            s.hit_event(event, j.CONFIG["contactProfiles"]["working"])
            s.check()
            states.append(hp - s.hp)
        self.assertEqual(states, [1000, 0])

    def test_raw_execute_can_pierce_smaller_full_shield(self):
        e = {"bullet": "穿刺子弹", "split": 1, "type": "物理", "power": 68770, "slay": 6}
        for k, survives in [(16, False), (24, True)]:
            s = j.CandidateEnergy(self.b, coefficient=k)
            s.pulse()
            s.hp_damage += s.hp - 1000
            s.hp = 1000
            s.hit_event(e, j.CONFIG["contactProfiles"]["working"])
            self.assertEqual(s.hp > 0, survives)
            s.check()

    def test_full_and_unaffordable_skill_are_noops(self):
        s = j.CandidateEnergy(self.b)
        s.pulse()
        before = copy.deepcopy(s.__dict__)
        self.assertFalse(s.blood_skill(0))
        self.assertEqual(s.__dict__, before)
        s.hit(2000)
        s.hp = math.ceil(s.b["hpMax"] * .35)
        before = copy.deepcopy(s.__dict__)
        self.assertFalse(s.blood_skill(0))
        self.assertEqual(s.__dict__, before)

    def test_skill_has_real_cost_from_alchemy_cap(self):
        s = j.CandidateEnergy(self.b, hp_ratio=1.3)
        s.pulse()
        s.hit(2000)
        self.assertTrue(s.blood_skill(100))
        self.assertLess(s.hp, self.b["hpMax"])
        self.assertAlmostEqual(s.shield, s.maximum)
        s.hit(500)
        before = copy.deepcopy(s.__dict__)
        self.assertFalse(s.blood_skill(101))
        self.assertEqual(s.__dict__, before)
        s.check()

    def test_old_mp_price_cannot_charge_large_pool_without_supply(self):
        old = j.recovery(self.b, 24, .08, 1, False)
        candidate = j.recovery(self.b, 24, .012, 1, False)
        self.assertIsNone(old["fullAt"])
        self.assertLessEqual(candidate["fullAt"], 8)
        self.assertLessEqual(candidate["mpSpent"], self.b["mpMax"])

    def test_mark_decays_without_primary_refresh(self):
        self.assertEqual(j.vulnerability(0, 1.5), 1.5)
        self.assertEqual(j.vulnerability(27, 1.5), 0)
        self.assertGreater(j.vulnerability(4, 1.5), j.vulnerability(13, 1.5))
        # Main shots do not appear among mark refresh events.
        s = j.firing_schedule(self.b, j.QJZ, horizon=360, ray_capacity=1)
        self.assertEqual(len(s["ray"]), 1)
        self.assertGreater(len(s["main"]), 30)

    def test_roll_refills_secondary_and_interval_survives_refill(self):
        s = j.firing_schedule(self.b, j.QJZ, horizon=1080, ray_capacity=8)
        self.assertEqual(len(s["reloads"]), 2)
        self.assertEqual(s["reloads"][0]["kind"], "roll")
        self.assertEqual(s["reloads"][0]["frame"], 360)
        self.assertGreater(len(s["ray"]), 8)
        self.assertTrue(all(b - a >= 45 for a, b in zip(s["ray"], s["ray"][1:])))
        self.assertLessEqual(s["wallCoverage"], .6 + 27 / 1080)

    def test_f_reload_never_refills_main_for_free(self):
        s = j.firing_schedule(self.b, j.QJZ, "fast_12", 8, horizon=1800)
        self.assertTrue(any(x["kind"] == "F_assumed" for x in s["reloads"]))
        self.assertTrue(any(x["kind"] == "normal" for x in s["reloads"]))
        self.assertTrue(all(b - a >= 45 for a, b in zip(s["ray"], s["ray"][1:])))

    def test_counter_miss_does_not_apply_crumble_or_execute(self):
        class AlwaysZero:
            def random(self):
                return 0
        hp, maximum = j.actor_damage(2000, 10000, 10000, 2, 50, 99, AlwaysZero(), True)
        self.assertEqual((hp, maximum), (2000, 10000))

    def test_clip_name_alone_does_not_change_firepower(self):
        b = copy.deepcopy(self.b)
        baseline = j.m.gun_stats(b, j.QJZ)
        b["weaponData"][j.QJZ]["clipname"] = "高温自锐式针弹"
        self.assertEqual(j.m.gun_stats(b, j.QJZ), baseline)

    def test_in_memory_proposed_base_uses_mods_and_restores_source(self):
        before = j.m.ITEMS[j.QJZ].findtext("data/power")
        b = j.configured(proposed_power=2552)
        self.assertEqual(j.m.ITEMS[j.QJZ].findtext("data/power"), before)
        self.assertGreater(b["weaponData"][j.QJZ]["power"], 2552 * 3.04)

    def test_no_ray_preserves_old_ordinary_ttk_control(self):
        b = j.configured(j.ADVANCED, j.M134)
        old = j.m.isolated_ttk(b, j.M134)
        new = j.outgoing(b, j.M134, peak=0, policy="normal", flight=0)
        self.assertEqual(old["shots"], new["mainShots"])
        self.assertAlmostEqual(old["ttk"], new["ttk"])

    def test_broken_shield_disables_fire_control_despite_negative_weight(self):
        self.assertLess(self.b["stats"]["weight"], 0)
        offline = j.outgoing(self.b, j.QJZ, peak=0, policy="normal", online_fraction=0)
        online = j.outgoing(self.b, j.QJZ, peak=0, policy="normal", online_fraction=1)
        # Without 0.15% crumble / 10% execute, ordinary damage alone must pay
        # essentially all 3.77M HP. Negative weight cannot bypass the online gate.
        per_hit = j.m.gun_stats(self.b, j.QJZ)["ordinary"] * 300 / 1419
        required_hits = math.ceil(j.m.PARAMS["boss"]["hp"] / per_hit)
        cycles, remainder = divmod(required_hits, 5)
        expected_shots = cycles * 2 + (remainder > 0) + (remainder > 2)
        self.assertEqual(offline["mainShots"], expected_shots)
        self.assertGreater(offline["mainShots"], online["mainShots"] * 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
