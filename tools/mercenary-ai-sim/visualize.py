"""
可视化模块：绘制地图、碰撞体、门、佣兵轨迹和统计信息。
"""

from __future__ import annotations

from typing import List, Optional
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.collections import LineCollection
from shapely.geometry import Polygon, MultiPolygon

from map_model import MapData
from mercenary_ai import MercenaryAgent


def _plot_polygon(ax, poly, **kwargs):
    """绘制 shapely Polygon（支持 MultiPolygon）。"""
    if poly.is_empty:
        return
    if isinstance(poly, MultiPolygon):
        for p in poly.geoms:
            _plot_polygon(ax, p, **kwargs)
        return

    xs, ys = poly.exterior.xy
    ax.fill(xs, ys, **kwargs)


def draw_map(ax, map_data: MapData, title: Optional[str] = None):
    """绘制地图底图：边界框 + 碰撞多边形 + 门。"""
    xmin, xmax, ymin, ymax = map_data.bounds

    # 可行走区域
    ax.add_patch(mpatches.Rectangle(
        (xmin, ymin), xmax - xmin, ymax - ymin,
        fill=True, facecolor="#f0f0e8", edgecolor="black", linewidth=1.5,
        label="walkable area"
    ))

    # 碰撞多边形
    for i, poly in enumerate(map_data.collisions):
        _plot_polygon(ax, poly, alpha=0.6, facecolor="#8B4513",
                      edgecolor="#5C3317", linewidth=1,
                      label="collision" if i == 0 else None)

    # 门
    for i, (dx, dy) in enumerate(map_data.doors):
        ax.plot(dx, dy, "s", color="lime", markersize=12, markeredgecolor="darkgreen",
                markeredgewidth=2, label="door" if i == 0 else None, zorder=10)
        ax.annotate(f"Door{i}", (dx, dy), textcoords="offset points",
                    xytext=(5, 5), fontsize=8, color="darkgreen")

    ax.set_xlim(xmin - 30, xmax + 30)
    ax.set_ylim(ymin - 30, ymax + 30)
    ax.set_aspect("equal")
    ax.invert_yaxis()  # Flash 坐标系 Y 向下
    if title:
        ax.set_title(title, fontsize=11)


def draw_trajectory(ax, agent: MercenaryAgent, color: str = "blue",
                    alpha: float = 0.4, linewidth: float = 1.0):
    """绘制单个佣兵的轨迹。"""
    traj = np.array(agent.trajectory)
    if len(traj) < 2:
        return

    ax.plot(traj[:, 0], traj[:, 1], color=color, alpha=alpha,
            linewidth=linewidth, zorder=5)
    # 起点
    ax.plot(traj[0, 0], traj[0, 1], "o", color=color, markersize=5, zorder=6)
    # 终点
    marker = "^" if agent.exited else "x"
    end_color = "green" if agent.exited else "red"
    ax.plot(traj[-1, 0], traj[-1, 1], marker, color=end_color,
            markersize=7, zorder=6)


def draw_batch_result(map_data: MapData, agents: List[MercenaryAgent],
                      title: Optional[str] = None,
                      save_path: Optional[str] = None,
                      show: bool = True):
    """绘制批量模拟结果：地图 + 所有轨迹 + 统计面板。"""
    fig, (ax_map, ax_stats) = plt.subplots(1, 2, figsize=(16, 7),
                                            gridspec_kw={"width_ratios": [3, 1]})

    # --- 地图面板 ---
    draw_map(ax_map, map_data, title=title or map_data.name)

    n_exit = sum(1 for a in agents if a.exit_reason == "door")
    n_timeout = sum(1 for a in agents if a.exit_reason == "timeout")
    n_active = len(agents) - n_exit - n_timeout

    for a in agents:
        color = "#2196F3" if a.exit_reason == "door" else "#F44336"
        draw_trajectory(ax_map, a, color=color, alpha=0.3)

    # 图例
    exit_patch = mpatches.Patch(color="#2196F3", alpha=0.5, label=f"exited ({n_exit})")
    timeout_patch = mpatches.Patch(color="#F44336", alpha=0.5, label=f"timeout ({n_timeout})")
    door_marker = plt.Line2D([], [], marker="s", color="lime", linestyle="None",
                              markeredgecolor="darkgreen", markersize=10, label="door")
    ax_map.legend(handles=[exit_patch, timeout_patch, door_marker],
                  loc="upper right", fontsize=9)

    # --- 统计面板 ---
    ax_stats.axis("off")

    exit_rate = n_exit / len(agents) * 100 if agents else 0
    exit_frames = [a.alive_frames for a in agents if a.exit_reason == "door"]
    timeout_frames = [a.alive_frames for a in agents if a.exit_reason == "timeout"]

    lines = [
        f"Agents: {len(agents)}",
        f"Exit Rate: {exit_rate:.1f}%",
        f"",
        f"--- Exited ---",
        f"  Count: {n_exit}",
        f"  Avg frames: {np.mean(exit_frames):.0f}" if exit_frames else "  Avg: N/A",
        f"  Med frames: {np.median(exit_frames):.0f}" if exit_frames else "  Med: N/A",
        f"  Min: {min(exit_frames):.0f}" if exit_frames else "",
        f"  Max: {max(exit_frames):.0f}" if exit_frames else "",
        f"",
        f"--- Timeout ---",
        f"  Count: {n_timeout}",
        f"  Avg frames: {np.mean(timeout_frames):.0f}" if timeout_frames else "  Avg: N/A",
    ]

    ax_stats.text(0.05, 0.95, "\n".join(lines), transform=ax_stats.transAxes,
                  fontsize=11, verticalalignment="top", fontfamily="monospace",
                  bbox=dict(boxstyle="round", facecolor="wheat", alpha=0.5))

    plt.tight_layout()
    if save_path:
        fig.savefig(save_path, dpi=150, bbox_inches="tight")
    if show:
        plt.show()
    else:
        plt.close(fig)

    return fig


def _stats_text(agents: List[MercenaryAgent], label: str) -> str:
    """生成统计文本块。"""
    n_exit = sum(1 for a in agents if a.exit_reason == "door")
    n_total = len(agents)
    exit_rate = n_exit / n_total * 100 if n_total else 0
    exit_frames = [a.alive_frames for a in agents if a.exit_reason == "door"]

    lines = [
        f"=== {label} ===",
        f"Exit Rate: {exit_rate:.1f}%",
        f"Exited: {n_exit}/{n_total}",
    ]
    if exit_frames:
        lines.append(f"Avg: {np.mean(exit_frames):.0f}f")
        lines.append(f"Med: {np.median(exit_frames):.0f}f")
        lines.append(f"Max: {max(exit_frames):.0f}f")
    else:
        lines.append("Avg: N/A")
    return "\n".join(lines)


def draw_compare_result(map_data: MapData,
                        baseline_agents: List[MercenaryAgent],
                        bfs_agents: List[MercenaryAgent],
                        title: Optional[str] = None,
                        save_path: Optional[str] = None,
                        show: bool = True):
    """绘制 baseline vs BFS 对比：左右两张地图 + 统计。"""
    fig, axes = plt.subplots(1, 3, figsize=(22, 7),
                              gridspec_kw={"width_ratios": [3, 3, 1.2]})
    ax_base, ax_bfs, ax_stats = axes

    # --- Baseline ---
    draw_map(ax_base, map_data, title="Baseline (L-path)")
    for a in baseline_agents:
        color = "#2196F3" if a.exit_reason == "door" else "#F44336"
        draw_trajectory(ax_base, a, color=color, alpha=0.3)
    n_base_exit = sum(1 for a in baseline_agents if a.exit_reason == "door")
    ax_base.set_xlabel(f"Exit: {n_base_exit}/{len(baseline_agents)}", fontsize=11)

    # --- BFS ---
    draw_map(ax_bfs, map_data, title="BFS (A* grid)")
    for a in bfs_agents:
        color = "#4CAF50" if a.exit_reason == "door" else "#FF9800"
        draw_trajectory(ax_bfs, a, color=color, alpha=0.3)
    n_bfs_exit = sum(1 for a in bfs_agents if a.exit_reason == "door")
    ax_bfs.set_xlabel(f"Exit: {n_bfs_exit}/{len(bfs_agents)}", fontsize=11)

    # --- 统计对比 ---
    ax_stats.axis("off")
    text = _stats_text(baseline_agents, "Baseline") + "\n\n" + _stats_text(bfs_agents, "BFS")

    # delta
    base_rate = sum(1 for a in baseline_agents if a.exit_reason == "door") / len(baseline_agents) * 100
    bfs_rate = sum(1 for a in bfs_agents if a.exit_reason == "door") / len(bfs_agents) * 100
    delta = bfs_rate - base_rate

    base_frames = [a.alive_frames for a in baseline_agents if a.exit_reason == "door"]
    bfs_frames = [a.alive_frames for a in bfs_agents if a.exit_reason == "door"]
    avg_base = np.mean(base_frames) if base_frames else float('inf')
    avg_bfs = np.mean(bfs_frames) if bfs_frames else float('inf')

    text += f"\n\n=== Delta ===\nRate: {delta:+.1f}%"
    if base_frames and bfs_frames:
        text += f"\nAvg: {avg_bfs - avg_base:+.0f}f"

    ax_stats.text(0.05, 0.95, text, transform=ax_stats.transAxes,
                  fontsize=10, verticalalignment="top", fontfamily="monospace",
                  bbox=dict(boxstyle="round", facecolor="wheat", alpha=0.5))

    if title:
        fig.suptitle(title, fontsize=13, y=1.02)

    plt.tight_layout()
    if save_path:
        fig.savefig(save_path, dpi=150, bbox_inches="tight")
    if show:
        plt.show()
    else:
        plt.close(fig)

    return fig
