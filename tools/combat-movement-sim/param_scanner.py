"""
参数扫描框架 — 网格搜索 MovementResolver 的可调参数。

用法：
  results = scan_params(scenarios, param_grid)
  best = find_best(results, metric="escape_frames")
  print_results_table(results)
"""
from __future__ import annotations

import itertools
import json
import os
from dataclasses import asdict
from typing import Dict, List, Optional, Tuple

from combat_agent import MovementConfig
from combat_sim import SimResult, run_batch
from scenario_gen import CombatScenario


# ═══════ 参数网格 ═══════

DEFAULT_PARAM_GRID = {
    "margin": [60, 80, 100, 120],
    "no_progress_threshold": [2, 3, 4, 5],
    "unstuck_base_window": [8, 12, 16, 24],
    "probe_speed_mult": [3.0, 4.0, 5.0],
}

# 不在默认网格中但可单独扫描的参数
EXTENDED_PARAM_GRID = {
    "probe_min": [15, 20, 30],
    "probe_max": [40, 60, 80],
    "probe_fail_trigger": [2, 3, 5],
    "unstuck_mid_window": [16, 24, 32],
    "unstuck_high_window": [30, 40, 50],
    "unstuck_mid_thresh": [4, 6, 8],
    "unstuck_high_thresh": [8, 12, 16],
}


def _make_config(**overrides) -> MovementConfig:
    return MovementConfig(**overrides)


# ═══════ 扫描 ═══════

def scan_params(
    scenarios: List[CombatScenario],
    param_grid: Dict[str, List] = None,
    max_ticks: int = 500,
    verbose: bool = True,
) -> List[Tuple[Dict, List[SimResult]]]:
    """
    网格搜索：每组参数组合 × 每个场景 → SimResult。

    返回 [(param_dict, [SimResult, ...]), ...]
    """
    if param_grid is None:
        param_grid = DEFAULT_PARAM_GRID

    param_names = list(param_grid.keys())
    param_values = list(param_grid.values())
    combos = list(itertools.product(*param_values))

    all_results = []
    total = len(combos)

    for idx, combo in enumerate(combos):
        params = dict(zip(param_names, combo))
        cfg = _make_config(**params)

        sim_results = run_batch(scenarios, cfg, max_ticks=max_ticks)

        all_results.append((params, sim_results))

        if verbose and (idx + 1) % max(1, total // 10) == 0:
            pct = (idx + 1) / total * 100
            print(f"  [{pct:.0f}%] {idx + 1}/{total} combos done")

    return all_results


# ═══════ 聚合和排序 ═══════

def aggregate_results(results: List[SimResult]) -> Dict:
    """将一组 SimResult 聚合为统计摘要。"""
    n = len(results)
    if n == 0:
        return {}

    succeeded = sum(1 for r in results if r.succeeded)
    reached = sum(1 for r in results if r.reached_safe)
    caught = sum(1 for r in results if r.caught)
    escape_frames = [r.escape_frames for r in results if r.escape_frames >= 0]
    stuck_rates = [r.stuck_rate for r in results]
    smoothness = [r.smoothness for r in results]
    corners = [r.corner_events for r in results]
    slides = [r.slide_events for r in results]
    min_enemy_dists = [r.min_enemy_dist for r in results if r.min_enemy_dist != float("inf")]

    summary = {
        "n_scenarios": n,
        "success_rate": succeeded / n,
        "reach_rate": reached / n,
        "caught_rate": caught / n,
        "avg_escape_frames": sum(escape_frames) / max(1, len(escape_frames)),
        "avg_stuck_rate": sum(stuck_rates) / n,
        "max_stuck_rate": max(stuck_rates),
        "avg_smoothness": sum(smoothness) / n,
        "avg_corner_events": sum(corners) / n,
        "avg_slide_events": sum(slides) / n,
    }
    if min_enemy_dists:
        summary["avg_min_enemy_dist"] = sum(min_enemy_dists) / len(min_enemy_dists)
        summary["min_min_enemy_dist"] = min(min_enemy_dists)
    return summary


def find_best(
    scan_results: List[Tuple[Dict, List[SimResult]]],
    metric: str = "success_rate",
    higher_is_better: bool = True,
) -> Tuple[Dict, Dict]:
    """找到指定指标最优的参数组合。"""
    best_params = None
    best_agg = None
    best_val = None

    for params, sim_results in scan_results:
        agg = aggregate_results(sim_results)
        val = agg.get(metric, 0)

        if best_val is None:
            best_val = val
            best_params = params
            best_agg = agg
        elif higher_is_better and val > best_val:
            best_val = val
            best_params = params
            best_agg = agg
        elif not higher_is_better and val < best_val:
            best_val = val
            best_params = params
            best_agg = agg

    return best_params, best_agg


def rank_by_composite(
    scan_results: List[Tuple[Dict, List[SimResult]]],
    weights: Dict[str, float] = None,
) -> List[Tuple[Dict, Dict, float]]:
    """
    综合评分排序。

    默认权重（越高越好的加，越低越好的减）：
      reach_rate: +3.0      到达率最重要
      avg_escape_frames: -1.0/1000  逃脱越快越好（归一化到 [0,2]）
      avg_stuck_rate: -2.0   卡死率惩罚
      avg_smoothness: -0.5   方向抖动惩罚
    """
    if weights is None:
        weights = {
            "success_rate": 4.0,
            "caught_rate": -1.5,
            "avg_escape_frames": -0.001,
            "avg_stuck_rate": -2.0,
            "avg_smoothness": -0.25,
            "avg_min_enemy_dist": 0.002,
        }

    scored = []
    for params, sim_results in scan_results:
        agg = aggregate_results(sim_results)
        score = sum(agg.get(k, 0) * w for k, w in weights.items())
        scored.append((params, agg, score))

    scored.sort(key=lambda x: x[2], reverse=True)
    return scored


# ═══════ 输出 ═══════

def print_results_table(
    ranked: List[Tuple[Dict, Dict, float]],
    top_n: int = 10,
) -> None:
    """打印排名前 N 的参数组合。"""
    print(f"\n{'='*80}")
    print(f"  Top {min(top_n, len(ranked))} Parameter Combinations")
    print(f"{'='*80}")

    for i, (params, agg, score) in enumerate(ranked[:top_n]):
        print(f"\n  #{i+1}  score={score:.4f}")
        print(f"    params: {params}")
        print(f"    success={agg['success_rate']:.2%}"
              f"  reach={agg['reach_rate']:.2%}"
              f"  caught={agg['caught_rate']:.2%}"
              f"  avg_escape={agg['avg_escape_frames']:.0f}f"
              f"  stuck={agg['avg_stuck_rate']:.2%}"
              f"  smooth={agg['avg_smoothness']:.3f}"
              f"  corners={agg['avg_corner_events']:.1f}"
              f"  slides={agg['avg_slide_events']:.1f}")
        if "avg_min_enemy_dist" in agg:
            print("    "
                  f"min_enemy_dist(avg/min)={agg['avg_min_enemy_dist']:.1f}/"
                  f"{agg['min_min_enemy_dist']:.1f}")


def save_results(
    ranked: List[Tuple[Dict, Dict, float]],
    output_path: str,
) -> None:
    """保存扫描结果到 JSON。"""
    data = []
    for params, agg, score in ranked:
        data.append({
            "params": params,
            "metrics": agg,
            "score": score,
        })
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f"  Results saved to {output_path}")
