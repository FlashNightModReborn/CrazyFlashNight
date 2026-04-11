"""
战斗移动仿真可视化 — 轨迹绘制 + 统计面板。
"""
from __future__ import annotations

import math
import os
from typing import Dict, List, Optional, Tuple

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
from shapely.geometry import Polygon, MultiPolygon

from combat_agent import MovementConfig
from combat_sim import SimResult
from scenario_gen import CombatScenario


def _plot_polygon(ax, geom, **kwargs):
    """绘制 shapely Polygon / MultiPolygon。"""
    defaults = {"facecolor": "#8B4513", "edgecolor": "#333", "alpha": 0.6}
    defaults.update(kwargs)
    if isinstance(geom, MultiPolygon):
        for poly in geom.geoms:
            _plot_polygon(ax, poly, **defaults)
        return
    if isinstance(geom, Polygon) and not geom.is_empty:
        xs, ys = geom.exterior.xy
        ax.fill(xs, ys, **defaults)


def draw_scenario(ax, scenario: CombatScenario) -> None:
    """绘制地图底图：边界 + 碰撞体 + 出生点 + 敌人 + 安全区。"""
    m = scenario.map_data
    xmin, xmax, ymin, ymax = m.bounds

    # 可行走区域背景
    ax.add_patch(mpatches.Rectangle(
        (xmin, ymin), xmax - xmin, ymax - ymin,
        facecolor="#f0f0e0", edgecolor="#666", linewidth=1.5, zorder=0))

    # 碰撞体
    for coll in m.collisions:
        _plot_polygon(ax, coll, zorder=1)

    # 出生点
    ax.plot(*scenario.agent_start, "bo", markersize=10, zorder=5, label="Agent Start")

    # 敌人
    ax.plot(*scenario.enemy_pos, "r^", markersize=12, zorder=5, label="Enemy")

    # 安全区
    if scenario.safe_zone:
        circle = plt.Circle(scenario.safe_zone, 80, fill=False,
                            edgecolor="green", linewidth=2, linestyle="--", zorder=4)
        ax.add_patch(circle)
        ax.plot(*scenario.safe_zone, "g*", markersize=14, zorder=5, label="Safe Zone")

    ax.set_xlim(xmin - 20, xmax + 20)
    ax.set_ylim(ymin - 20, ymax + 20)
    ax.set_aspect("equal")
    ax.invert_yaxis()  # Y轴翻转（屏幕坐标系）
    ax.set_title(scenario.name, fontsize=11, fontweight="bold")


def draw_trajectory(ax, result: SimResult, color: str = "#2196F3",
                    alpha: float = 0.7, linewidth: float = 1.5) -> None:
    """绘制一条轨迹。"""
    traj = result.trajectory
    if len(traj) < 2:
        return
    xs = [p[0] for p in traj]
    zs = [p[1] for p in traj]
    ax.plot(xs, zs, color=color, alpha=alpha, linewidth=linewidth, zorder=3)

    # 起点和终点标记
    ax.plot(xs[0], zs[0], "o", color=color, markersize=6, zorder=6)
    end_marker = "s" if result.reached_safe else "x"
    end_color = "green" if result.reached_safe else "red"
    ax.plot(xs[-1], zs[-1], end_marker, color=end_color, markersize=8, zorder=6)

    # 敌人轨迹（多敌人追逐仿真时）
    enemy_trajs = getattr(result, '_enemy_trajectories', None)
    if enemy_trajs:
        e_colors = ["#FF5722", "#E91E63", "#9C27B0", "#FF9800",
                     "#795548", "#F44336", "#D32F2F", "#C62828"]
        for ei, et in enumerate(enemy_trajs):
            if len(et) < 2:
                continue
            ec = e_colors[ei % len(e_colors)]
            exs = [p[0] for p in et]
            ezs = [p[1] for p in et]
            ax.plot(exs, ezs, color=ec, alpha=0.4, linewidth=1.0,
                    linestyle="--", zorder=2)
            ax.plot(exs[-1], ezs[-1], "^", color=ec, markersize=7, zorder=5)


def draw_single_result(scenario: CombatScenario, result: SimResult,
                       output_path: str = None) -> None:
    """单场景结果可视化：地图 + 轨迹 + 统计。"""
    fig, (ax_map, ax_stats) = plt.subplots(1, 2, figsize=(16, 6),
                                            gridspec_kw={"width_ratios": [3, 1]})

    draw_scenario(ax_map, scenario)
    draw_trajectory(ax_map, result)
    ax_map.legend(loc="upper right", fontsize=8)

    # 统计面板
    ax_stats.axis("off")
    stats_text = (
        f"Scenario: {result.scenario_name}\n"
        f"{'─' * 30}\n"
        f"Total frames: {result.total_frames}\n"
        f"Reached safe: {'✓' if result.reached_safe else '✗'}\n"
        f"Escape frames: {result.escape_frames}\n"
        f"Stuck rate: {result.stuck_rate:.1%}\n"
        f"Smoothness: {result.smoothness:.3f}\n"
        f"Corner events: {result.corner_events}\n"
        f"Slide events: {result.slide_events}\n"
        f"Direction changes: {result.direction_changes}\n"
        f"{'─' * 30}\n"
        f"Config:\n"
        f"  margin={result.config.margin}\n"
        f"  no_progress={result.config.no_progress_threshold}\n"
        f"  unstuck_win={result.config.unstuck_base_window}\n"
        f"  probe_mult={result.config.probe_speed_mult}"
    )
    ax_stats.text(0.05, 0.95, stats_text, transform=ax_stats.transAxes,
                  fontsize=9, verticalalignment="top", fontfamily="monospace")

    plt.tight_layout()
    if output_path:
        fig.savefig(output_path, dpi=120, bbox_inches="tight")
        print(f"  Saved: {output_path}")
    plt.close(fig)


def draw_comparison(scenario: CombatScenario,
                    result_a: SimResult, label_a: str,
                    result_b: SimResult, label_b: str,
                    output_path: str = None) -> None:
    """两组参数对比可视化。"""
    fig, axes = plt.subplots(1, 3, figsize=(20, 6),
                              gridspec_kw={"width_ratios": [2, 2, 1]})

    # A
    draw_scenario(axes[0], scenario)
    draw_trajectory(axes[0], result_a, color="#2196F3")
    axes[0].set_title(f"{scenario.name} — {label_a}", fontsize=10)

    # B
    draw_scenario(axes[1], scenario)
    draw_trajectory(axes[1], result_b, color="#FF5722")
    axes[1].set_title(f"{scenario.name} — {label_b}", fontsize=10)

    # Stats comparison
    axes[2].axis("off")
    lines = [
        f"{'Metric':<20} {'A':>8} {'B':>8}",
        f"{'─' * 38}",
        f"{'Reached safe':<20} {'✓' if result_a.reached_safe else '✗':>8} {'✓' if result_b.reached_safe else '✗':>8}",
        f"{'Escape frames':<20} {result_a.escape_frames:>8} {result_b.escape_frames:>8}",
        f"{'Stuck rate':<20} {result_a.stuck_rate:>7.1%} {result_b.stuck_rate:>7.1%}",
        f"{'Smoothness':<20} {result_a.smoothness:>8.3f} {result_b.smoothness:>8.3f}",
        f"{'Corners':<20} {result_a.corner_events:>8} {result_b.corner_events:>8}",
        f"{'Slides':<20} {result_a.slide_events:>8} {result_b.slide_events:>8}",
    ]
    axes[2].text(0.05, 0.95, "\n".join(lines), transform=axes[2].transAxes,
                 fontsize=9, verticalalignment="top", fontfamily="monospace")

    plt.tight_layout()
    if output_path:
        fig.savefig(output_path, dpi=120, bbox_inches="tight")
        print(f"  Saved: {output_path}")
    plt.close(fig)


def draw_all_scenarios(results: List[SimResult],
                       scenarios: List[CombatScenario],
                       output_dir: str) -> None:
    """为每个场景绘制单独的结果图。"""
    os.makedirs(output_dir, exist_ok=True)
    scenario_map = {s.name: s for s in scenarios}
    for r in results:
        s = scenario_map.get(r.scenario_name)
        if s:
            path = os.path.join(output_dir, f"{r.scenario_name}.png")
            draw_single_result(s, r, path)
