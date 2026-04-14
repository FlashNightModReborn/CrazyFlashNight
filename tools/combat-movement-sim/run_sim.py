"""
CLI entry point for the offline combat movement / survival harness.
"""
from __future__ import annotations

import argparse
import json
import os

from combat_agent import MovementConfig
from combat_sim import run_batch
from param_scanner import (
    DEFAULT_PARAM_GRID,
    SURVIVAL_PARAM_GRID,
    aggregate_results,
    print_results_table,
    rank_by_composite,
    save_results,
    scan_params,
)
from scenario_gen import (
    CHASE_SCENARIOS,
    SURVIVAL_SCENARIOS,
    get_all_scenarios,
    get_burst_elite_variant_scenarios,
    get_burst_scenarios,
    get_chase_scenarios,
    get_scenario_by_name,
)
from visualize import draw_all_scenarios, draw_comparison


def _output_dir() -> str:
    return os.path.join(os.path.dirname(__file__), "results")


def _write_summary(out_dir: str, config_label: str, agg: dict, results) -> None:
    os.makedirs(out_dir, exist_ok=True)
    summary_path = os.path.join(out_dir, "summary.json")
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(
            {
                "config": config_label,
                "metrics": agg,
                "per_scenario": [r.summary_dict() for r in results],
            },
            f,
            indent=2,
            ensure_ascii=False,
        )
    print(f"  Summary saved: {summary_path}")


def _write_scenario_manifest(out_dir: str, scenarios, args=None) -> None:
    os.makedirs(out_dir, exist_ok=True)
    manifest_path = os.path.join(out_dir, "scenario_manifest.json")
    payload = {
        "variant_seed": getattr(args, "variant_seed", None),
        "variant_count": getattr(args, "variant_count", None),
        "scenarios": [],
    }
    for scenario in scenarios:
        payload["scenarios"].append(
            {
                "name": scenario.name,
                "mode": scenario.mode,
                "description": scenario.description,
                "agent_start": list(scenario.agent_start),
                "safe_zone": list(scenario.safe_zone) if scenario.safe_zone else None,
                "survival_ticks": scenario.survival_ticks,
                "agent_hp": scenario.agent_hp,
                "enemies": [
                    {
                        "x": e.x,
                        "z": e.z,
                        "speed": e.speed,
                        "attack_range": e.attack_range,
                        "attack_damage": e.attack_damage,
                        "attack_impact": e.attack_impact,
                        "attack_cooldown_frames": e.attack_cooldown_frames,
                        "attack_windup_frames": e.attack_windup_frames,
                        "attack_tag": e.attack_tag,
                    }
                    for e in (scenario.enemies or [])
                ],
            }
        )
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
    print(f"  Manifest saved: {manifest_path}")


def _print_aggregate(agg: dict) -> None:
    print("\n  Aggregate:")
    for k, v in agg.items():
        if isinstance(v, float):
            print(f"    {k}: {v:.4f}")
        else:
            print(f"    {k}: {v}")


def _print_survival_rows(results) -> None:
    for r in results:
        min_d = r.min_enemy_dist if r.min_enemy_dist != float("inf") else -1
        tag = "OK" if r.succeeded else "FAIL"
        death = f" dead={r.death_reason}@{r.death_frame}" if r.dead else ""
        print(
            f"  {r.scenario_name}: {tag}"
            f" hp={r.hp_remaining_pct:.0%}"
            f" down={r.down_count}"
            f" break={r.tough_break_count}"
            f" shield={r.shield_uses}"
            f" escape={r.escape_skill_uses}"
            f" wake={r.wakeup_guard_uses}"
            f" evade={r.evaded_hits}"
            f" min_dist={min_d:.0f}{death}"
        )


def _scan_grid(args, survival_mode: bool):
    if args.grid:
        with open(args.grid, "r", encoding="utf-8") as f:
            return json.load(f)
    return SURVIVAL_PARAM_GRID if survival_mode else DEFAULT_PARAM_GRID


def _load_params_json(path: str | None) -> dict | None:
    if not path:
        return None
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _variant_suffix(args) -> str:
    if not getattr(args, "elite_variants", False):
        return ""
    return f"_elite_variants_s{args.variant_seed}_n{args.variant_count}"


def _resolve_burst_scenarios(args):
    if args.scenario:
        if getattr(args, "elite_variants", False):
            scenarios = get_burst_elite_variant_scenarios(args.variant_count, args.variant_seed)
            for scenario in scenarios:
                if scenario.name == args.scenario:
                    return [scenario]
            raise ValueError(f"Unknown elite variant scenario: {args.scenario}")
        return [get_scenario_by_name(args.scenario)]
    if getattr(args, "elite_variants", False):
        return get_burst_elite_variant_scenarios(args.variant_count, args.variant_seed)
    return get_burst_scenarios()


def _candidate_compare_config(survival_mode: bool) -> tuple[MovementConfig, str]:
    if survival_mode:
        return (
            MovementConfig(
                burst_guard_hp_threshold=0.55,
                burst_guard_impact_ratio=0.45,
                burst_guard_nearby_enemies=1,
                shield_duration_frames=32,
                shield_damage_mult=0.35,
                shield_impact_mult=0.25,
                overguard_imminent_damage_ratio=0.7,
                overguard_recast_gap_frames=12,
                impact_recovery_per_tick=240.0,
                post_break_pure_move_frames=32,
                emergency_speed_mult=1.30,
                escape_single_imminent_damage_ratio=0.7,
                escape_single_imminent_hp_threshold=0.25,
                escape_dash_distance=160.0,
                escape_invuln_frames=8,
                escape_cooldown_frames=72,
                escape_impact_clear_ratio=0.1,
                escape_push_distance=110.0,
                escape_attack_delay_frames=28,
                wakeup_guard_invuln_frames=14,
                wakeup_guard_dash_distance=130.0,
                wakeup_guard_push_distance=130.0,
            ),
            "candidate_burst",
        )

    return (
        MovementConfig(
            margin=80,
            no_progress_threshold=2,
            unstuck_base_window=12,
            unstuck_mid_window=24,
            unstuck_high_window=40,
            probe_speed_mult=5.0,
            edge_escape_margin=100,
            encirclement_evade_threshold=0.15,
            pressure_dominance_ratio=1.05,
            pack_escape_window=12,
            pack_escape_min_nearby=1,
        ),
        "candidate_chase",
    )


def cmd_baseline(args) -> None:
    scenarios = get_all_scenarios() if not args.scenario else [get_scenario_by_name(args.scenario)]
    config = MovementConfig()
    print(f"\n=== Baseline: {len(scenarios)} scenarios ===")
    results = run_batch(scenarios, config, max_ticks=args.max_ticks)

    out_dir = os.path.join(_output_dir(), "baseline")
    draw_all_scenarios(results, scenarios, out_dir)

    agg = aggregate_results(results)
    _print_aggregate(agg)
    _write_summary(out_dir, "default (AS2 current)", agg, results)


def cmd_chase(args) -> None:
    scenarios = get_chase_scenarios() if not args.scenario else [get_scenario_by_name(args.scenario)]
    config = MovementConfig()
    print(f"\n=== Chase: {len(scenarios)} scenarios ===")
    results = run_batch(scenarios, config, max_ticks=args.max_ticks)

    out_dir = os.path.join(_output_dir(), "chase")
    draw_all_scenarios(results, scenarios, out_dir)

    agg = aggregate_results(results)
    _print_aggregate(agg)
    for r in results:
        min_d = r.min_enemy_dist if r.min_enemy_dist != float("inf") else -1
        caught = " CAUGHT" if r.caught else ""
        tag = "OK" if r.succeeded else "FAIL"
        print(f"  {r.scenario_name}: {tag}({r.escape_frames}f) min_dist={min_d:.0f}{caught}")
    _write_summary(out_dir, "default", agg, results)


def cmd_burst(args) -> None:
    scenarios = _resolve_burst_scenarios(args)
    params = _load_params_json(args.params_json)
    config = MovementConfig(**params) if params else MovementConfig()
    config_label = "custom" if params else "default"
    print(f"\n=== Burst Survival: {len(scenarios)} scenarios ===")
    results = run_batch(scenarios, config, max_ticks=args.max_ticks)

    out_dir = os.path.join(_output_dir(), "burst" + _variant_suffix(args))
    _write_scenario_manifest(out_dir, scenarios, args)
    draw_all_scenarios(results, scenarios, out_dir)

    agg = aggregate_results(results)
    _print_aggregate(agg)
    _print_survival_rows(results)
    _write_summary(out_dir, config_label, agg, results)


def cmd_scan(args) -> None:
    survival_mode = args.burst
    if args.scenario:
        scenarios = _resolve_burst_scenarios(args) if survival_mode else [get_scenario_by_name(args.scenario)]
    elif survival_mode:
        scenarios = _resolve_burst_scenarios(args)
    else:
        scenarios = get_all_scenarios()
        if args.include_chase:
            scenarios.extend(get_chase_scenarios())

    grid = _scan_grid(args, survival_mode)
    base_params = _load_params_json(args.base_params_json)
    total_combos = 1
    for vals in grid.values():
        total_combos *= len(vals)

    print(f"\n=== Parameter Scan: {total_combos} combos x {len(scenarios)} scenarios ===")
    scan_results = scan_params(
        scenarios, grid, max_ticks=args.max_ticks, base_params=base_params
    )
    ranked = rank_by_composite(scan_results)
    print_results_table(ranked, top_n=args.top_n)

    folder = ("scan_burst" + _variant_suffix(args)) if survival_mode else "scan"
    out_dir = os.path.join(_output_dir(), folder)
    os.makedirs(out_dir, exist_ok=True)
    if survival_mode:
        _write_scenario_manifest(out_dir, scenarios, args)
    save_results(ranked, os.path.join(out_dir, "scan_results.json"))

    if ranked:
        best_params = ranked[0][0]
        merged_params = dict(base_params or {})
        merged_params.update(best_params)
        print(f"\n  Best params: {best_params}")
        if base_params:
            print(f"  Best merged params: {merged_params}")
        best_cfg = MovementConfig(**merged_params)
        best_results = run_batch(scenarios, best_cfg, max_ticks=args.max_ticks)
        draw_all_scenarios(best_results, scenarios, os.path.join(out_dir, "best"))


def cmd_compare(args) -> None:
    survival_mode = args.burst
    if args.scenario:
        scenarios = _resolve_burst_scenarios(args) if survival_mode else [get_scenario_by_name(args.scenario)]
    elif survival_mode:
        scenarios = _resolve_burst_scenarios(args)
    else:
        scenarios = get_all_scenarios()
        if args.include_chase:
            scenarios.extend(get_chase_scenarios())

    config_a = MovementConfig()
    if args.params_json:
        with open(args.params_json, "r", encoding="utf-8") as f:
            params = json.load(f)
        config_b = MovementConfig(**params)
        label_b = "custom"
    else:
        config_b, label_b = _candidate_compare_config(survival_mode)

    folder = ("compare_burst" + _variant_suffix(args)) if survival_mode else "compare"
    out_dir = os.path.join(_output_dir(), folder)
    os.makedirs(out_dir, exist_ok=True)
    if survival_mode:
        _write_scenario_manifest(out_dir, scenarios, args)
    print(f"\n=== Compare: default vs {label_b}, {len(scenarios)} scenarios ===")

    results_a = []
    results_b = []
    for scenario in scenarios:
        r_a = run_batch([scenario], config_a, max_ticks=args.max_ticks)[0]
        r_b = run_batch([scenario], config_b, max_ticks=args.max_ticks)[0]
        results_a.append(r_a)
        results_b.append(r_b)
        draw_comparison(
            scenario,
            r_a,
            "default",
            r_b,
            label_b,
            os.path.join(out_dir, f"compare_{scenario.name}.png"),
        )
        print(
            f"  {scenario.name}: "
            f"default={'OK' if r_a.succeeded else 'FAIL'} "
            f"vs {label_b}={'OK' if r_b.succeeded else 'FAIL'}"
        )
    if len(scenarios) > 1:
        print("\n  Compare aggregate:")
        print(f"    default success={aggregate_results(results_a)['success_rate']:.2%}")
        print(f"    {label_b} success={aggregate_results(results_b)['success_rate']:.2%}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Combat movement and burst survival simulator")
    parser.add_argument("--baseline", action="store_true", help="Run the static retreat baseline set")
    parser.add_argument("--chase", action="store_true", help="Run moving-enemy chase scenarios")
    parser.add_argument("--burst", action="store_true", help="Run elite burst survival scenarios")
    parser.add_argument("--scan", action="store_true", help="Grid-search parameters for the active mode")
    parser.add_argument("--compare", action="store_true", help="Compare default config vs candidate/custom")
    parser.add_argument("--include-chase", action="store_true", help="Include chase scenarios in baseline/scan/compare")
    parser.add_argument("--scenario", type=str, default=None, help="Run only one named scenario")
    parser.add_argument("--max-ticks", type=int, default=500, help="Maximum ticks per simulation")
    parser.add_argument("--top-n", type=int, default=10, help="How many scan results to print")
    parser.add_argument("--grid", type=str, default=None, help="Optional JSON scan grid")
    parser.add_argument("--params-json", type=str, default=None, help="Optional JSON config for compare")
    parser.add_argument("--base-params-json", type=str, default=None, help="Optional JSON base config for scan")
    parser.add_argument("--elite-variants", action="store_true", help="Use generated elite burst variant scenarios")
    parser.add_argument("--variant-count", type=int, default=24, help="How many elite burst variants to generate")
    parser.add_argument("--variant-seed", type=int, default=1337, help="Random seed for elite burst variants")
    args = parser.parse_args()

    if not (args.baseline or args.chase or args.burst or args.scan or args.compare):
        args.baseline = True

    if args.baseline:
        cmd_baseline(args)
    if args.chase:
        cmd_chase(args)
    if args.burst and not args.scan and not args.compare:
        cmd_burst(args)
    if args.scan:
        cmd_scan(args)
    if args.compare:
        cmd_compare(args)


if __name__ == "__main__":
    main()
