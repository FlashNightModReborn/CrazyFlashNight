"""
CLI 入口 — 战斗移动仿真 + 参数扫描。

用法：
  # 默认参数跑全部场景，生成轨迹图
  python run_sim.py --baseline

  # 参数扫描（网格搜索）
  python run_sim.py --scan

  # 对比当前参数 vs 最优参数
  python run_sim.py --compare

  # 单场景调试
  python run_sim.py --scenario corner_trap_left --baseline
"""
from __future__ import annotations

import argparse
import json
import os
import sys

from combat_agent import MovementConfig
from combat_sim import run_retreat_sim, run_batch
from scenario_gen import get_all_scenarios, get_scenario_by_name, CombatScenario, CHASE_SCENARIOS
from param_scanner import (
    scan_params, rank_by_composite, print_results_table,
    save_results, DEFAULT_PARAM_GRID, aggregate_results,
)
from visualize import draw_single_result, draw_comparison, draw_all_scenarios


def _output_dir():
    return os.path.join(os.path.dirname(__file__), "results")


def cmd_baseline(args):
    """用默认参数（AS2 当前值）跑全部场景。"""
    scenarios = _get_scenarios(args)
    config = MovementConfig()  # 默认 = AS2 当前硬编码值

    print(f"\n=== Baseline: {len(scenarios)} scenarios, default config ===")
    results = run_batch(scenarios, config, max_ticks=args.max_ticks)

    out_dir = os.path.join(_output_dir(), "baseline")
    draw_all_scenarios(results, scenarios, out_dir)

    agg = aggregate_results(results)
    print(f"\n  Aggregate:")
    for k, v in agg.items():
        if isinstance(v, float):
            print(f"    {k}: {v:.4f}")
        else:
            print(f"    {k}: {v}")

    # 保存摘要
    summary_path = os.path.join(out_dir, "summary.json")
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump({
            "config": "default (AS2 current)",
            "metrics": agg,
            "per_scenario": [r.summary_dict() for r in results],
        }, f, indent=2, ensure_ascii=False)
    print(f"  Summary saved: {summary_path}")


def cmd_scan(args):
    """参数网格搜索。"""
    scenarios = _get_scenarios(args)

    # 可通过 --grid 指定自定义网格（JSON 文件）
    grid = DEFAULT_PARAM_GRID
    if args.grid:
        with open(args.grid, "r") as f:
            grid = json.load(f)

    total_combos = 1
    for v in grid.values():
        total_combos *= len(v)
    print(f"\n=== Parameter Scan: {total_combos} combos × {len(scenarios)} scenarios ===")

    scan_results = scan_params(scenarios, grid, max_ticks=args.max_ticks)
    ranked = rank_by_composite(scan_results)

    print_results_table(ranked, top_n=args.top_n)

    out_dir = os.path.join(_output_dir(), "scan")
    os.makedirs(out_dir, exist_ok=True)
    save_results(ranked, os.path.join(out_dir, "scan_results.json"))

    # 用最优参数跑一遍并画图
    if ranked:
        best_params = ranked[0][0]
        print(f"\n  Best params: {best_params}")
        best_cfg = MovementConfig(**best_params)
        best_results = run_batch(scenarios, best_cfg, max_ticks=args.max_ticks)
        draw_all_scenarios(best_results, scenarios, os.path.join(out_dir, "best"))


def cmd_compare(args):
    """对比默认参数 vs 指定参数。"""
    scenarios = _get_scenarios(args)

    config_a = MovementConfig()  # 默认
    # 从 JSON 或命令行加载对比参数
    if args.params_json:
        with open(args.params_json, "r") as f:
            params = json.load(f)
        config_b = MovementConfig(**params)
        label_b = "custom"
    else:
        # 使用一组已知改进参数
        config_b = MovementConfig(
            margin=100,
            no_progress_threshold=2,
            unstuck_base_window=16,
            probe_speed_mult=4.0,
        )
        label_b = "tuned"

    print(f"\n=== Compare: default vs {label_b}, {len(scenarios)} scenarios ===")
    out_dir = os.path.join(_output_dir(), "compare")
    os.makedirs(out_dir, exist_ok=True)

    for s in scenarios:
        r_a = run_retreat_sim(s, config_a, args.max_ticks)
        r_b = run_retreat_sim(s, config_b, args.max_ticks)
        path = os.path.join(out_dir, f"compare_{s.name}.png")
        draw_comparison(s, r_a, "default", r_b, label_b, path)

        tag_a = "OK" if r_a.reached_safe else "FAIL"
        tag_b = "OK" if r_b.reached_safe else "FAIL"
        print(f"  {s.name}: "
              f"default={tag_a}({r_a.escape_frames}f) "
              f"vs {label_b}={tag_b}({r_b.escape_frames}f)")


def cmd_chase(args):
    """多移动敌人追逐场景。"""
    scenarios = [fn() for fn in CHASE_SCENARIOS]
    config = MovementConfig()

    print(f"\n=== Chase: {len(scenarios)} scenarios, moving enemies ===")
    results = run_batch(scenarios, config, max_ticks=args.max_ticks)

    out_dir = os.path.join(_output_dir(), "chase")
    draw_all_scenarios(results, scenarios, out_dir)

    agg = aggregate_results(results)
    print(f"\n  Aggregate:")
    for k, v in agg.items():
        if isinstance(v, float):
            print(f"    {k}: {v:.4f}")
        else:
            print(f"    {k}: {v}")

    # 额外打印追逐专属指标
    for r in results:
        caught = getattr(r, '_caught', False)
        min_d = getattr(r, '_min_enemy_dist', -1)
        tag = "OK" if r.reached_safe else "FAIL"
        caught_tag = " CAUGHT" if caught else ""
        print(f"  {r.scenario_name}: {tag}({r.escape_frames}f)"
              f"  min_dist={min_d:.0f}{caught_tag}")

    summary_path = os.path.join(out_dir, "summary.json")
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump({
            "config": "default",
            "metrics": agg,
            "per_scenario": [r.summary_dict() for r in results],
        }, f, indent=2, ensure_ascii=False)


def _get_scenarios(args) -> list:
    if args.scenario:
        return [get_scenario_by_name(args.scenario)]
    return get_all_scenarios()


def main():
    parser = argparse.ArgumentParser(
        description="Combat Movement Simulator — MovementResolver 离线调优")
    parser.add_argument("--baseline", action="store_true",
                        help="用 AS2 当前参数跑基线")
    parser.add_argument("--scan", action="store_true",
                        help="参数网格搜索")
    parser.add_argument("--compare", action="store_true",
                        help="默认 vs 调优参数对比")
    parser.add_argument("--chase", action="store_true",
                        help="多移动敌人追逐场景")
    parser.add_argument("--scenario", type=str, default=None,
                        help="只跑指定场景（名称）")
    parser.add_argument("--max-ticks", type=int, default=500,
                        help="每次仿真最大 tick 数（默认 500）")
    parser.add_argument("--top-n", type=int, default=10,
                        help="扫描结果显示前 N 名")
    parser.add_argument("--grid", type=str, default=None,
                        help="自定义参数网格 JSON 文件路径")
    parser.add_argument("--params-json", type=str, default=None,
                        help="对比用的参数 JSON 文件路径")

    args = parser.parse_args()

    if not (args.baseline or args.scan or args.compare or args.chase):
        args.baseline = True  # 默认跑基线

    if args.baseline:
        cmd_baseline(args)
    if args.scan:
        cmd_scan(args)
    if args.compare:
        cmd_compare(args)
    if args.chase:
        cmd_chase(args)


if __name__ == "__main__":
    main()
