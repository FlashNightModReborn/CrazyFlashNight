"""
佣兵 AI 模拟器主入口。

用法:
  # 跑所有真实地图（自动在边界放门）
  python run_sim.py --real

  # 跑随机生成的测试地图
  python run_sim.py --random --difficulty hard --n-maps 5

  # 跑指定真实地图
  python run_sim.py --real --map-name 基地房顶

  # 批量跑并保存统计（不弹窗）
  python run_sim.py --real --no-show --save-dir results/
"""

from __future__ import annotations

import argparse
import os
import sys
import json
import random
from pathlib import Path

from map_model import (MapData, load_real_maps, generate_random_map,
                       place_doors_on_bounds, generate_adversarial_map)
from mercenary_ai import AIConfig, run_batch_sim, run_compare_sim
from visualize import draw_batch_result, draw_compare_result


def get_default_xml_path() -> str:
    """定位 scene_environment.xml。"""
    # 从工具目录往上回溯
    here = Path(__file__).resolve().parent
    candidates = [
        here / "../../data/environment/scene_environment.xml",
        here / "../../../data/environment/scene_environment.xml",
    ]
    for c in candidates:
        if c.exists():
            return str(c)
    return ""


def run_real_maps(args):
    """跑真实地图测试。"""
    xml_path = args.xml or get_default_xml_path()
    if not xml_path or not os.path.exists(xml_path):
        print(f"[ERROR] Cannot find scene_environment.xml at: {xml_path}")
        sys.exit(1)

    maps = load_real_maps(xml_path)
    print(f"Loaded {len(maps)} real maps from XML.")

    # 过滤有碰撞数据的地图（没碰撞的地图太简单没意义）
    if args.map_name:
        maps = [m for m in maps if args.map_name in m.name]
        if not maps:
            print(f"[ERROR] No map matching '{args.map_name}'")
            sys.exit(1)

    results = {}

    for m in maps:
        # 真实地图的门不在XML中，在边界附近放置
        place_doors_on_bounds(m, n_doors=args.n_doors)

        if not m.doors:
            print(f"  [{m.name}] SKIP: no doors placed")
            continue

        print(f"  [{m.name}] running {args.n_agents} agents...")
        agents = run_batch_sim(m, n_agents=args.n_agents, max_ticks=args.max_ticks)

        n_exit = sum(1 for a in agents if a.exit_reason == "door")
        exit_rate = n_exit / max(len(agents), 1) * 100
        avg_frames = sum(a.alive_frames for a in agents if a.exit_reason == "door") / max(n_exit, 1)
        print(f"    Exit rate: {exit_rate:.1f}%  Avg exit frames: {avg_frames:.0f}")

        results[m.name] = {
            "exit_rate": exit_rate,
            "avg_exit_frames": avg_frames,
            "n_exit": n_exit,
            "n_timeout": len(agents) - n_exit,
            "has_collisions": len(m.collisions) > 0,
        }

        save_path = None
        if args.save_dir:
            os.makedirs(args.save_dir, exist_ok=True)
            save_path = os.path.join(args.save_dir, f"{m.name}.png")

        draw_batch_result(m, agents, title=f"[Real] {m.name}",
                          save_path=save_path, show=not args.no_show)

    # 输出汇总
    print("\n=== Summary ===")
    print(f"{'Map':<20} {'Exit%':>8} {'AvgFrames':>10} {'Collisions':>10}")
    print("-" * 52)
    for name, r in sorted(results.items(), key=lambda kv: kv[1]["exit_rate"]):
        print(f"{name:<20} {r['exit_rate']:>7.1f}% {r['avg_exit_frames']:>10.0f}"
              f" {'YES' if r['has_collisions'] else 'no':>10}")

    if args.save_dir:
        with open(os.path.join(args.save_dir, "summary.json"), "w", encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        print(f"\nResults saved to {args.save_dir}/")


def run_random_maps(args):
    """跑随机生成的测试地图。"""
    results = {}

    for i in range(args.n_maps):
        name = f"random_{args.difficulty}_{i:02d}"
        m = generate_random_map(
            name=name,
            n_obstacles=args.n_obstacles,
            n_doors=args.n_doors,
            difficulty=args.difficulty,
        )

        print(f"  [{name}] {len(m.collisions)} obstacles, {len(m.doors)} doors")
        agents = run_batch_sim(m, n_agents=args.n_agents, max_ticks=args.max_ticks)

        n_exit = sum(1 for a in agents if a.exit_reason == "door")
        exit_rate = n_exit / max(len(agents), 1) * 100
        avg_frames = sum(a.alive_frames for a in agents if a.exit_reason == "door") / max(n_exit, 1)
        print(f"    Exit rate: {exit_rate:.1f}%  Avg exit frames: {avg_frames:.0f}")

        results[name] = {
            "exit_rate": exit_rate,
            "avg_exit_frames": avg_frames,
            "n_exit": n_exit,
            "n_timeout": len(agents) - n_exit,
        }

        save_path = None
        if args.save_dir:
            os.makedirs(args.save_dir, exist_ok=True)
            save_path = os.path.join(args.save_dir, f"{name}.png")

        draw_batch_result(m, agents, title=f"[Random/{args.difficulty}] {name}",
                          save_path=save_path, show=not args.no_show)

    # 汇总
    print("\n=== Random Maps Summary ===")
    all_rates = [r["exit_rate"] for r in results.values()]
    print(f"  Maps: {len(results)}")
    print(f"  Avg exit rate: {sum(all_rates)/len(all_rates):.1f}%")
    print(f"  Worst: {min(all_rates):.1f}%  Best: {max(all_rates):.1f}%")

    if args.save_dir:
        with open(os.path.join(args.save_dir, "random_summary.json"), "w",
                  encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)


def run_adversarial_maps(args):
    """跑对抗性测试地图——专门击败 L-path 算法的场景。"""
    patterns = ["wall_gap", "zigzag", "u_trap", "spiral", "double_wall",
                "narrow_maze", "bottleneck", "pocket", "multi_room",
                "long_corridor"]
    results = {}

    for pattern in patterns:
        m = generate_adversarial_map(name="adversarial", pattern=pattern)
        print(f"  [{m.name}] {len(m.collisions)} obstacles, {len(m.doors)} doors")
        agents = run_batch_sim(m, n_agents=args.n_agents, max_ticks=args.max_ticks)

        n_exit = sum(1 for a in agents if a.exit_reason == "door")
        exit_rate = n_exit / max(len(agents), 1) * 100
        avg_frames = sum(a.alive_frames for a in agents if a.exit_reason == "door") / max(n_exit, 1)
        timeout_frames = [a.alive_frames for a in agents if not a.exited]
        avg_timeout = sum(timeout_frames) / max(len(timeout_frames), 1)
        print(f"    Exit: {exit_rate:.1f}%  AvgExit: {avg_frames:.0f}f  AvgTimeout: {avg_timeout:.0f}f")

        results[m.name] = {
            "exit_rate": exit_rate,
            "avg_exit_frames": avg_frames,
            "n_exit": n_exit,
            "n_timeout": len(agents) - n_exit,
            "pattern": pattern,
        }

        save_path = None
        if args.save_dir:
            os.makedirs(args.save_dir, exist_ok=True)
            save_path = os.path.join(args.save_dir, f"{m.name}.png")

        draw_batch_result(m, agents, title=f"[Adversarial] {m.name}",
                          save_path=save_path, show=not args.no_show)

    # 汇总
    print("\n=== Adversarial Maps Summary ===")
    print(f"{'Pattern':<20} {'Exit%':>8} {'AvgFrames':>10}")
    print("-" * 42)
    for name, r in sorted(results.items(), key=lambda kv: kv[1]["exit_rate"]):
        print(f"{r['pattern']:<20} {r['exit_rate']:>7.1f}% {r['avg_exit_frames']:>10.0f}")

    if args.save_dir:
        with open(os.path.join(args.save_dir, "adversarial_summary.json"), "w",
                  encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)


def run_compare(args):
    """跑 baseline vs BFS 对比测试（同一出生点，公平比较）。"""
    patterns = ["wall_gap", "zigzag", "u_trap", "spiral", "double_wall",
                "narrow_maze", "bottleneck", "pocket", "multi_room",
                "long_corridor"]
    results = {}

    for pattern in patterns:
        m = generate_adversarial_map(name="compare", pattern=pattern)
        print(f"  [{pattern}] comparing baseline vs BFS, {args.n_agents} agents...")

        baseline_agents, bfs_agents = run_compare_sim(
            m, n_agents=args.n_agents, max_ticks=args.max_ticks
        )

        n_base = sum(1 for a in baseline_agents if a.exit_reason == "door")
        n_bfs = sum(1 for a in bfs_agents if a.exit_reason == "door")
        base_rate = n_base / len(baseline_agents) * 100
        bfs_rate = n_bfs / len(bfs_agents) * 100

        base_frames = [a.alive_frames for a in baseline_agents if a.exit_reason == "door"]
        bfs_frames = [a.alive_frames for a in bfs_agents if a.exit_reason == "door"]
        avg_base = sum(base_frames) / max(len(base_frames), 1)
        avg_bfs = sum(bfs_frames) / max(len(bfs_frames), 1)

        print(f"    Baseline: {base_rate:.1f}% exit, avg {avg_base:.0f}f")
        print(f"    BFS:      {bfs_rate:.1f}% exit, avg {avg_bfs:.0f}f")
        print(f"    Delta:    {bfs_rate - base_rate:+.1f}% rate, {avg_bfs - avg_base:+.0f}f speed")

        results[pattern] = {
            "baseline_exit_rate": base_rate,
            "bfs_exit_rate": bfs_rate,
            "baseline_avg_frames": avg_base,
            "bfs_avg_frames": avg_bfs,
            "delta_rate": bfs_rate - base_rate,
            "delta_frames": avg_bfs - avg_base,
        }

        save_path = None
        if args.save_dir:
            os.makedirs(args.save_dir, exist_ok=True)
            save_path = os.path.join(args.save_dir, f"compare_{pattern}.png")

        draw_compare_result(m, baseline_agents, bfs_agents,
                            title=f"Baseline vs BFS: {pattern}",
                            save_path=save_path, show=not args.no_show)

    # 汇总
    print("\n=== Baseline vs BFS Summary ===")
    print(f"{'Pattern':<15} {'Base%':>8} {'BFS%':>8} {'Delta':>8} {'BaseAvg':>9} {'BFSAvg':>9} {'Faster':>8}")
    print("-" * 72)
    for p, r in sorted(results.items(), key=lambda kv: kv[1]["delta_rate"], reverse=True):
        faster = r["baseline_avg_frames"] - r["bfs_avg_frames"]
        print(f"{p:<15} {r['baseline_exit_rate']:>7.1f}% {r['bfs_exit_rate']:>7.1f}%"
              f" {r['delta_rate']:>+7.1f}% {r['baseline_avg_frames']:>8.0f}f"
              f" {r['bfs_avg_frames']:>8.0f}f {faster:>+7.0f}f")

    if args.save_dir:
        with open(os.path.join(args.save_dir, "compare_summary.json"), "w",
                  encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)


def main():
    parser = argparse.ArgumentParser(description="Mercenary AI Simulator")
    parser.add_argument("--real", action="store_true", help="Test real maps from XML")
    parser.add_argument("--random", action="store_true", help="Test random generated maps")
    parser.add_argument("--adversarial", action="store_true",
                        help="Test adversarial maps designed to break L-path")
    parser.add_argument("--compare", action="store_true",
                        help="Compare baseline vs BFS on adversarial maps")
    parser.add_argument("--xml", default="", help="Path to scene_environment.xml")
    parser.add_argument("--map-name", default="", help="Filter real maps by name")
    parser.add_argument("--difficulty", default="medium",
                        choices=["easy", "medium", "hard"])
    parser.add_argument("--n-maps", type=int, default=5, help="Number of random maps")
    parser.add_argument("--n-agents", type=int, default=50, help="Agents per map")
    parser.add_argument("--n-doors", type=int, default=2, help="Doors per map")
    parser.add_argument("--n-obstacles", type=int, default=3, help="Obstacles (random maps)")
    parser.add_argument("--max-ticks", type=int, default=1000, help="Max ticks per agent")
    parser.add_argument("--no-show", action="store_true", help="Don't show plots (headless)")
    parser.add_argument("--save-dir", default="", help="Directory to save results")
    parser.add_argument("--seed", type=int, default=None, help="Random seed")

    args = parser.parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    if not args.real and not args.random and not args.adversarial and not args.compare:
        # 默认跑对比测试
        args.compare = True

    if args.real:
        print("=== Real Maps ===")
        run_real_maps(args)

    if args.random:
        print("\n=== Random Maps ===")
        run_random_maps(args)

    if args.adversarial:
        print("\n=== Adversarial Maps ===")
        run_adversarial_maps(args)

    if args.compare:
        print("\n=== Baseline vs BFS Comparison ===")
        run_compare(args)


if __name__ == "__main__":
    main()
