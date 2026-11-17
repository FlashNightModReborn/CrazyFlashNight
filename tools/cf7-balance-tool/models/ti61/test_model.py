"""Contract checks for the offline model; no Flash/runtime acceptance claims."""
import unittest
import copy

import model as m
import reference


class ModelContractTests(unittest.TestCase):
    def test_current_full_hp_initial_shield_is_free_once(self):
        p = m.PARAMS["profiles"][m.PARAMS["runtimeProfile"]]
        s = m.EnergyState(self.b, p, mp_ratio=0)
        s.pulse()
        self.assertEqual(s.shield, s.maximum)
        self.assertEqual(s.initial_shield_granted, s.maximum)
        self.assertEqual((s.spent, s.mp, s.startups), (0, 0, 0))
        s.hit(100)
        s.pulse()
        self.assertEqual(s.shield, s.maximum - 100)
        s.check()

    def test_wounded_before_rebuild_cannot_claim_free_shield_after_lowering_max(self):
        p = m.PARAMS["profiles"][m.PARAMS["runtimeProfile"]]
        s = m.EnergyState(self.b, p)
        s.constrain_initial_shield_to_previous_health(self.b["hpMax"], self.b["hpMax"] + 1000)
        s.pulse()
        self.assertEqual(s.initial_shield_granted, 0)
        self.assertLess(s.shield, s.maximum)
        self.assertEqual(s.startups, 1)
        s.check()

    def test_full_initial_shield_preserves_overheal(self):
        p = m.PARAMS["profiles"][m.PARAMS["runtimeProfile"]]
        s = m.EnergyState(self.b, p, hp_ratio=1.3)
        hp, mp = s.hp, s.mp
        s.pulse()
        self.assertEqual((s.hp, s.mp), (hp, mp))
        self.assertEqual(s.shield, s.maximum)
        s.check()

    def setUp(self):
        self.b = m.build("titanium_type_61_armor", 55, 13,
                         ["血色光剑天秤", "钛合金P90", "钛合金P90", "钛合金QJZ171"])
        self.p = m.PARAMS["profiles"]["glass_cannon_candidate"]

    def test_live_negative_hp_scales_and_gun_loadout_still_pays(self):
        self.assertEqual(m.data("血色光剑天秤", 13)["hp"], -3037)
        self.assertEqual(self.b["hpMax"], 5508)
        self.assertEqual(self.b["stats"]["weight"], -17)

    def test_invalid_energy_parameters_are_rejected(self):
        params = copy.deepcopy(m.PARAMS)
        params["profiles"]["glass_cannon_candidate"]["ammoMpPerRound"] = 0
        with self.assertRaises(ValueError):
            m.validate_parameters(params)
        params["profiles"]["glass_cannon_candidate"]["ammoMpPerRound"] = float("nan")
        with self.assertRaises(ValueError):
            m.validate_parameters(params)

    def test_level_45_cannot_borrow_later_weapons(self):
        b = m.build("titanium_type_61_armor", 45, 13, ["血色光剑天秤", "钛合金QJZ171", "M134暴力版"])
        self.assertEqual(len(b["illegalItems"]), 3)
        with self.assertRaises(ValueError):
            m.isolated_ttk(b, "钛合金QJZ171")

    def test_activation_starts_zero_and_pays_exact_actual_charge(self):
        s = m.EnergyState(self.b, self.p)
        self.assertEqual(s.shield, 0)
        s.pulse()
        self.assertGreater(s.shield, 0)
        self.assertAlmostEqual(s.spent, self.p["startupMp"] + s.shield * self.p["shieldMpPerPoint"])
        s.check()

    def test_no_mp_no_free_shield_or_heal(self):
        s = m.EnergyState(self.b, self.p, 0)
        s.hit(100)
        for _ in range(100):
            s.pulse()
        self.assertEqual(s.shield, 0)
        self.assertEqual(s.healed, 0)
        self.assertEqual(s.startups, 0)
        s.check()

    def test_interrupted_zero_capacity_reboot_does_not_charge_twice(self):
        s = m.EnergyState(self.b, self.p, 0)
        s.mp = s.initial_mp = self.p["startupMp"]
        s.pulse()
        self.assertEqual(s.shield, 0)
        self.assertTrue(s.paid)
        s.hit(10)
        s.p90_fire(0)
        for _ in range(10):
            s.pulse()
        self.assertEqual(s.startups, 1)
        self.assertGreater(s.shield, 0)
        s.check()

    def test_last_hp_can_be_paid_exactly_even_for_low_hp_fixture(self):
        b = dict(self.b, hpMax=100)
        s = m.EnergyState(b, self.p)
        s.hit(1)
        s.pulse()
        self.assertEqual(s.hp, 100)
        self.assertAlmostEqual(s.healed, 1)
        s.check()

    def test_full_shield_does_not_prevent_large_single_hit_death(self):
        s = m.EnergyState(self.b, self.p)
        for _ in range(100):
            s.pulse()
        self.assertAlmostEqual(s.shield, s.maximum)
        s.hit(self.b["hpMax"] + s.strength + 1)
        self.assertEqual(s.hp, 0)
        self.assertGreater(s.shield, 0)
        s.check()

    def test_online_leaked_hp_is_not_healed(self):
        s = m.EnergyState(self.b, self.p)
        for _ in range(100):
            s.pulse()
        s.hit(s.strength + 100)
        hp = s.hp
        for _ in range(20):
            s.pulse()
        self.assertEqual(s.hp, hp)
        s.check()

    def test_held_weapon_does_not_cause_attack_state_self_damage(self):
        s = m.EnergyState(self.b, self.p)
        for _ in range(100):
            s.pulse()
        self.assertEqual(s.hp, self.b["hpMax"])
        self.assertEqual(s.self_damage, 0)

    def test_synthesis_respects_reserve_and_reload(self):
        s = m.EnergyState(self.b, self.p)
        for _ in range(100):
            s.pulse()
        s.shot = [10, 8]
        spent = s.spent
        s.pulse(reloading=True)
        self.assertEqual(s.spent, spent)
        self.assertEqual(s.shot, [10, 8])
        for _ in range(100):
            s.pulse()
        self.assertEqual(s.shot, [0, 0])
        self.assertAlmostEqual(s.spent - spent, 18 * self.p["ammoMpPerRound"])
        s.check()

    def test_p90_empty_no_generation_and_mp_overflow_lost(self):
        s = m.EnergyState(self.b, self.p)
        self.assertTrue(s.p90_fire(0))
        self.assertEqual(s.generated, 0)
        s.shot[0] = 50
        self.assertFalse(s.p90_fire(0))
        self.assertEqual(s.generated, 0)

    def test_saint_does_not_sum_both_weapon_peaks(self):
        r = next(x for x in m.sword_saint_projection()["rows"] if x["level"] == 55 and x["enhancement"] == 13)
        self.assertEqual(r["punchBurst"] - r["punchNormal"], 638)
        self.assertEqual(r["armorKnifeBonus"] - r["knifeBonusDuringBurst"], 638)
        self.assertEqual(r["burstSeconds"] / r["cycleSeconds"], .75)

    def test_source_animation_load_events_not_multiplied_by_duration(self):
        a = m.animation_inputs()["wrist"]
        self.assertEqual(len(a["events"]), 10)
        self.assertEqual(a["durationFrames"], 77)
        self.assertAlmostEqual(sum(e["coefficient"] for e in a["events"]), 22.7)

    def test_no_online_fire_control_and_overload_peak_sum(self):
        self.assertEqual(m.overload(self.p, self.b, self.b["hpMax"] * .25, 1), 0)
        self.assertGreater(m.overload(self.p, self.b, self.b["hpMax"] * .25, 0), 0)

    def test_reload_recovery_keeps_firing_and_returns_to_main(self):
        r = m.run_pressure(self.p, m.PARAMS["pressureScripts"][0], mp_ratio=.15)
        self.assertGreater(r["p90Shots"], 100)
        self.assertGreaterEqual(r["switches"], 2)
        self.assertIsNotNone(r["bossTtk"])

    def test_recovery_target_above_neutral_synthesis_floor_is_a_trap(self):
        r = m.run_pressure(self.p, m.PARAMS["pressureScripts"][0], mp_ratio=.15, return_mp_ratio=.65)
        self.assertEqual(r["switches"], 1)
        self.assertGreater(r["p90Shots"], 100)
        self.assertLess(r["trace"][-1]["mp"], self.b["mpMax"] * .65)

    def test_resource_conservation_in_pressure_and_alternate_order(self):
        for p in m.PARAMS["profiles"].values():
            for scenario in m.PARAMS["pressureScripts"]:
                r = m.run_pressure(p, scenario, mp_ratio=.3, order="pulse_hit_fire")
                self.assertLessEqual(r["shieldOnlineFraction"], 1)
                self.assertGreaterEqual(r["elapsed"], 0)

    def test_crumble_is_current_max_compounding_not_constant_dps(self):
        hp, maximum = m.apply_boss_hit(100000, 100000, 0, 10, 0)
        hp, maximum = m.apply_boss_hit(hp, maximum, 0, 10, 0)
        self.assertEqual(hp, 81000)
        self.assertEqual(maximum, 81000)

    def test_overlevel_dodge_and_weight_are_separate(self):
        activation = m.dodge_activation(55, 100)
        self.assertLess(activation, .03)
        self.assertEqual(m.weight_speed(-17, 55), 1.25)
        self.assertGreater(m.dodge_activation(55, 55), activation)

    def test_mod_percent_joins_enhancement_without_second_multiply(self):
        registry = reference.mods_from_source(m)
        d = reference.resolve(m, "剑圣头部装甲", 13, "data_4",
                              ["纳米执行单元", "传感器", "碳纤维布料"], registry)
        self.assertEqual(d["hp"], 255)  # round(80 * (3.04 + .15)), not 80*3.04*1.15
        self.assertEqual(d["knifepower"], 234)
        self.assertEqual(d["evasion"], 47)

    def test_blade_vampirism_does_not_leak_to_unarmed_slot(self):
        registry = reference.mods_from_source(m)
        defensive = reference.configured_build(m, 55, "all_defensive", registry)
        vampire = reference.configured_build(m, 55, "lifesteal_hand", registry)
        self.assertEqual(defensive["bladeVampirism"], 5)
        self.assertEqual(defensive["unarmedVampirism"], 0)
        self.assertEqual(vampire["unarmedVampirism"], 5)
        self.assertEqual(defensive["evasion"] - vampire["evasion"], 35)

    def test_lifesteal_merge_takes_maximum_not_sum(self):
        registry = reference.mods_from_source(m)
        # Existing 10% on this blade must remain 10%, not become 15%.
        original = m.ITEMS["青龙偃月刀"].find("data")
        import xml.etree.ElementTree as ET
        temporary = ET.SubElement(original, "vampirism")
        temporary.text = "10"
        try:
            d = reference.resolve(m, "青龙偃月刀", 13, "data", ["强化柄芯", "纳米执行单元", "绯红忆弦轮"], registry)
            self.assertEqual(d["vampirism"], 10)
        finally:
            original.remove(temporary)

    def test_lifesteal_does_not_revive_and_has_diminishing_overflow(self):
        self.assertEqual(reference.overflow_heal(0, 1000, 1000), 0)
        self.assertEqual(reference.overflow_heal(500, 1000, 100), 100)
        self.assertLess(reference.overflow_heal(1400, 1000, 100), 100)
        self.assertLess(1400 + reference.overflow_heal(1400, 1000, 10000), 1501)

    def test_free_three_slots_belong_to_sword_saint_only(self):
        registry = reference.mods_from_source(m)
        self.assertEqual(m.data("黄金骑士牙狼头盔")["modslot"], 1)
        self.assertEqual(m.data("钛合金61式头部装甲")["modslot"], 1)
        self.assertEqual(m.data("剑圣头部装甲", 13, "data_4")["modslot"], 3)
        with self.assertRaises(ValueError):
            reference.resolve(m, "钛合金61式头部装甲", 13, "data", ["纳米执行单元", "传感器", "碳纤维布料"], registry)

    def test_extension_occupies_slot_and_reduces_qjz_lightload_progress(self):
        registry = reference.mods_from_source(m)
        b = reference.configured_build(m, 55, "all_defensive", registry, "titanium_type_61_armor")
        self.assertEqual(b["weight"], -5)
        self.assertAlmostEqual(b["qjzProgress"], 5/17)

    def test_compensation_restores_blood_penalty_for_single_shieldable_hit(self):
        p = m.PARAMS["profiles"]["blood_cost_compensated_candidate"]
        for enhancement in [1, 13]:
            b = m.build("titanium_type_61_armor", 55, enhancement, ["血色光剑天秤"])
            capacity, strength, _ = m.shield_spec(b, p)
            loss = -m.data("血色光剑天秤", enhancement)["hp"]
            self.assertGreaterEqual(min(capacity, strength), loss * 1.25)
            s = m.EnergyState(b, p)
            for _ in range(50):
                s.pulse()
            s.hit(b["hpMax"] + loss)
            self.assertGreater(s.hp, 0)
            s.check()

    def test_universal_compensation_shield_not_created_by_equipping_blood_sword(self):
        p = m.PARAMS["profiles"]["blood_cost_compensated_candidate"]
        a = m.build("titanium_type_61_armor", 55, 13)
        b = m.build("titanium_type_61_armor", 55, 13, ["血色光剑天秤"])
        self.assertEqual(m.shield_spec(a, p), m.shield_spec(b, p))

    def test_weight_servo_requires_blood_and_online_and_never_accumulates(self):
        p = m.PARAMS["profiles"]["blood_cost_compensated_candidate"]
        self.assertEqual(m.effective_weight(self.b, p, 0), -17)
        self.assertEqual(m.effective_weight(self.b, p, 1), -33)
        self.assertEqual(m.effective_weight(self.b, p, 1), -33)
        self.assertEqual(self.b["stats"]["weight"], -17)
        no_blood = dict(self.b, hasBloodSword=False)
        self.assertEqual(m.effective_weight(no_blood, p, 1), -17)
        four_pieces = dict(self.b, setPieces=4)
        self.assertEqual(m.effective_weight(four_pieces, p, 1), -17)

    def test_compensation_does_not_restore_bypass_survival(self):
        p = m.PARAMS["profiles"]["blood_cost_compensated_candidate"]
        s = m.EnergyState(self.b, p)
        for _ in range(50):
            s.pulse()
        s.hit(self.b["hpMax"], bypass=True)
        self.assertEqual(s.hp, 0)
        self.assertEqual(s.absorbed, 0)
        s.check()

    def test_full_gun_mods_capacity_toughness_and_weight(self):
        registry = reference.mods_from_source(m)
        b = reference.configured_build(m, 55, "all_defensive", registry, "titanium_type_61_armor")
        resolved = reference.energy_build(m, b)
        qjz = resolved["weaponData"]["钛合金QJZ171"]
        p90 = resolved["weaponData"]["钛合金P90"]
        self.assertEqual(qjz["capacity"], 72)
        self.assertEqual(qjz["power"], 7715)
        self.assertEqual(qjz["reloadPenalty"], 50)  # No native NOAH on this MG.
        self.assertEqual(p90["weight"], 11)
        self.assertEqual(p90["toughness"], 50)
        self.assertEqual(p90["accuracy"], -10)
        self.assertEqual(b["toughnessBonus"], 100)
        self.assertEqual(m.gun_stats(resolved, "钛合金QJZ171")["capacity"], 72)
        p = m.PARAMS["profiles"]["blood_cost_compensated_candidate"]
        self.assertEqual(m.effective_weight(resolved, p, 1), -21)

    def test_long_mag_cap_limits_gain_not_total_capacity(self):
        registry = reference.mods_from_source(m)
        d = reference.resolve(m, "M134暴力版", 13, "data", ["战术鱼骨零件", "水冷机构", "加长弹匣"], registry)
        self.assertEqual(d["capacity"], 1850)

    def test_invalid_p90_subtype_or_self_power_does_not_pass(self):
        registry = reference.mods_from_source(m)
        with self.assertRaises(ValueError):
            reference.resolve(m, "钛合金P90", 13, "data", ["手枪卡宾转换套件"], registry)
        with self.assertRaises(ValueError):
            reference.resolve(m, "钛合金QJZ171", 13, "data", ["战术鱼骨零件", "矢量偏转枪盾"], registry)

    def test_confirmed_base_cycle_balances_and_p90_has_net_income(self):
        p = m.PARAMS["profiles"]["blood_cost_compensated_candidate"]
        # 留出回蓝空间；满MP会按既定封顶丢弃发射返还。
        s = m.EnergyState(self.b, p, mp_ratio=.75)
        for _ in range(50):
            s.pulse()
        before = s.mp
        self.assertTrue(s.pistol_fire(0))
        s.pulse()
        self.assertAlmostEqual(s.mp, before)
        self.assertEqual(s.shot[0], 0)
        self.assertTrue(s.p90_fire(0))
        s.pulse()
        self.assertAlmostEqual(s.mp - before, 3)
        s.check()

    def test_confirmed_online_healing_and_overflow_reboot(self):
        p = m.PARAMS["profiles"]["blood_cost_compensated_candidate"]
        s = m.EnergyState(self.b, p)
        for _ in range(50):
            s.pulse()
        s.hit(s.strength + 100)
        old = s.hp
        s.pulse()
        self.assertGreater(s.hp, old)
        s.check()
        overflow = m.EnergyState(self.b, p, hp_ratio=1.5)
        overflow.pulse()
        self.assertEqual(overflow.hp, self.b["hpMax"]*1.5)
        self.assertGreater(overflow.shield, 0)
        overflow.check()


class AmmoEconomyContractTests(unittest.TestCase):
    def setUp(self):
        self.p = m.PARAMS["profiles"][m.PARAMS["runtimeProfile"]]
        self.b = dict(m.build("titanium_type_61_armor", 60, 13), mpMax=3000)

    def test_real_ammo_prices_cover_all_launchers_and_floor(self):
        expected = {"P90": 3, "钛合金P90": 3, "Glock 18": 3, "MP5战术版": 7,
                    "战术版MGL": 375, "沧蓝陨铁手炮": 375, "M79式榴弹发射器": 938, "加农手炮": 268}
        self.assertEqual({name: m.ammo_mp_cost(name, self.p) for name in expected}, expected)

    def test_effective_ordinary_capacity_and_fixed_p90(self):
        self.assertEqual(m.ammo_mp_cost("MP5战术版", self.p, capacity=120), 4)
        self.assertEqual(m.ammo_mp_cost("钛合金P90", self.p, capacity=1), 3)
        ammo_price = m.ITEMS["冲锋枪钢芯穿甲弹"].find("price")
        original = ammo_price.text
        try:
            ammo_price.text = "800"
            self.assertEqual(m.ammo_mp_cost("钛合金P90", self.p), 3)
        finally:
            ammo_price.text = original

    def test_missing_or_invalid_price_and_capacity_fail_closed(self):
        self.assertIsNone(m.ammo_mp_cost("战术版MGL", self.p, clipname="not_registered"))
        for capacity in [0, -1, 1.5, float("nan"), float("inf")]:
            self.assertIsNone(m.ammo_mp_cost("战术版MGL", self.p, capacity=capacity))
        price = m.ITEMS["火箭弹弹药"].find("price")
        original = price.text
        try:
            for value in ["0", "-1", "nan", "inf", "bad_price"]:
                price.text = value
                self.assertIsNone(m.ammo_mp_cost("战术版MGL", self.p))
        finally:
            price.text = original

    def test_per_round_rounding_cannot_be_changed_by_batching(self):
        state = m.EnergyState(self.b, self.p, mp_ratio=1600/3000, weapons=("MP5战术版", "钛合金P90"))
        state.shot[0] = 3
        state.pulse()
        self.assertEqual((state.mp, state.ammo_spent, state.synthesized), (1579, 21, 3))
        state.check()

    def test_cheaper_secondary_has_priority_over_missing_launcher_rounds(self):
        state = m.EnergyState(self.b, self.p, mp_ratio=1875/3000, weapons=("战术版MGL", "钛合金P90"))
        state.shot = [5, 1]
        state.pulse()
        self.assertEqual((state.shot, state.mp), ([5, 0], 1872))
        state.check()

    def test_high_price_partial_synthesis_preserves_reserve(self):
        state = m.EnergyState(self.b, self.p, mp_ratio=.75, weapons=("战术版MGL", "钛合金P90"))
        state.shot[0] = 5
        state.pulse()
        self.assertEqual((state.shot[0], state.mp, state.ammo_spent), (3, 1500, 750))
        state.pulse()
        self.assertEqual(state.ammo_spent, 750)
        state.check()

    def test_launcher_refund_is_fixed_not_its_synthesis_price(self):
        state = m.EnergyState(self.b, self.p, mp_ratio=.5, weapons=("战术版MGL", "钛合金P90"))
        self.assertTrue(state.pistol_fire(0))
        self.assertEqual(state.mp, 1503)
        state.check()

    def test_paid_sustained_output_is_allowed_and_accounts_for_real_potions(self):
        report = m.ammo_economy_report()
        self.assertTrue(report["paidSustainedLauncherFireAllowed"])
        rows = [row for row in report["trials"] if row["weapon"] == "加农手炮" and row["seconds"] == 60]
        unpaid = next(row for row in rows if row["mpChannels"] == 0)
        paid = next(row for row in rows if row["mpChannels"] == 3 and row["alchemy"] == 0)
        self.assertLess(unpaid["shots"], paid["shots"])
        self.assertEqual(paid["shots"], 300)
        self.assertGreater(paid["goldSpent"], 0)
        self.assertEqual(paid["goldSpent"], paid["potions"] * 2500)
        self.assertLessEqual(paid["mpFinal"], paid["mpMax"])


class EmergencySequenceTests(unittest.TestCase):
    def test_default_off_and_source_bound_thresholds(self):
        state = m.EmergencyState(1000)
        self.assertEqual((state.trigger, state.reset), (.5, .7))
        state.event(damage=700)
        self.assertEqual((state.hp, state.stock, state.gold), (300, 3, 0))

    def test_two_independent_hits_and_paid_real_potion(self):
        state = m.EmergencyState(1000, enabled=True)
        state.event(damage=700)
        state.event(damage=700, ready=False)
        self.assertEqual((state.hp, state.stock, state.doses, state.gold), (300, 2, 1, 2500))

    def test_single_aggregate_lethal_does_not_inject(self):
        state = m.EmergencyState(1000, enabled=True)
        state.event(damage=1400)
        self.assertEqual((state.hp, state.doses), (0, 0))

    def test_same_low_crisis_does_not_rearm_on_ready(self):
        state = m.EmergencyState(5576, enabled=True)
        state.event(damage=4500)
        state.event(damage=500)
        self.assertEqual((state.hp, state.doses, state.gold), (2076, 1, 2500))

    def test_healthy_recovery_then_descending_event_rearms(self):
        state = m.EmergencyState(5576, enabled=True)
        state.event(damage=3000)
        state.event(damage=1600)
        self.assertEqual((state.hp, state.doses, state.gold), (3976, 2, 5000))

    def test_full_eligibility_and_alchemy(self):
        state = m.EmergencyState(5576, alchemy=10, enabled=True)
        state.event(damage=2900, shield_broken=False)
        state.event(damage=100, prohibited=True)
        state.event(damage=100, ready=False)
        self.assertEqual(state.doses, 0)
        state.event(damage=100)
        self.assertEqual((state.hp, state.doses, state.heal), (4376, 1, 2000))


if __name__ == "__main__":
    unittest.main()
