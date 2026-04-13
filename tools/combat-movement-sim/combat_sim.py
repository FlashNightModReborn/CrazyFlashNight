"""
战斗移动仿真器 — 模拟撤退/交战期间的移动决策。

核心循环（每 tick = 4 帧）：
  1. agent.update_boundaries()
  2. 计算撤退方向 (want_x, want_z) — 远离 enemy
  3. movement_resolver.apply_boundary_aware_movement()
  4. agent.apply_movement() — 4 子帧碰撞检测
  5. agent.record_frame()

评估指标：
  - stuck_rate:        卡死帧占比
  - escape_frames:     从陷阱到达安全区的帧数（越少越好）
  - smoothness:        方向变化频率（越低越平滑）
  - reached_safe:      是否到达安全区
  - corner_events:     角落突围次数
  - slide_events:      沿墙滑行次数
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

from combat_agent import CombatAgent, MovementConfig
from movement_resolver import apply_boundary_aware_movement
from scenario_gen import CombatScenario
from shared import CollisionWorld


@dataclass
class SimResult:
    """单次仿真结果。"""
    scenario_name: str
    config: MovementConfig
    objective: str = "reach_safe"
    total_frames: int = 0
    stuck_frames: int = 0
    reached_safe: bool = False
    caught: bool = False
    caught_frame: int = -1
    min_enemy_dist: float = float("inf")
    escape_frames: int = -1          # -1 = 未到达
    corner_events: int = 0
    slide_events: int = 0
    direction_changes: int = 0       # 方向变化次数
    trajectory: List[Tuple[float, float]] = field(default_factory=list)

    @property
    def stuck_rate(self) -> float:
        return self.stuck_frames / max(1, self.total_frames)

    @property
    def smoothness(self) -> float:
        """方向变化频率 = direction_changes / total_ticks。越低越平滑。"""
        total_ticks = self.total_frames // 4
        return self.direction_changes / max(1, total_ticks)

    @property
    def succeeded(self) -> bool:
        if self.objective == "survive":
            return not self.caught
        return self.reached_safe

    def summary_dict(self) -> Dict:
        return {
            "scenario": self.scenario_name,
            "objective": self.objective,
            "succeeded": self.succeeded,
            "total_frames": self.total_frames,
            "stuck_frames": self.stuck_frames,
            "stuck_rate": round(self.stuck_rate, 4),
            "reached_safe": self.reached_safe,
            "caught": self.caught,
            "caught_frame": self.caught_frame if self.caught_frame >= 0 else None,
            "min_enemy_dist": (
                round(self.min_enemy_dist, 4)
                if self.min_enemy_dist != float("inf")
                else None
            ),
            "escape_frames": self.escape_frames,
            "corner_events": self.corner_events,
            "slide_events": self.slide_events,
            "smoothness": round(self.smoothness, 4),
        }


# ═══════ 撤退方向计算（纯 AS2 复刻）═══════

def _compute_retreat_dir(agent, enemy_x, enemy_z, safe_zone, frame):
    """纯 AS2 撤退方向，无策略层修复。"""
    diff_x = enemy_x - agent.x
    diff_z = enemy_z - agent.z

    if abs(diff_x) > 5:
        want_x = -1 if diff_x > 0 else 1
    elif safe_zone:
        want_x = 1 if safe_zone[0] > agent.x else -1
    else:
        want_x = 1 if agent.bnd_right > agent.bnd_left else -1

    z_safe = 120
    abs_dz = abs(diff_z)
    want_z = 0

    if abs_dz < z_safe:
        if diff_z != 0:
            escape_z = -1 if diff_z > 0 else 1
            if escape_z < 0 and agent.bnd_up < 50:
                escape_z = 1
            elif escape_z > 0 and agent.bnd_down < 50:
                escape_z = -1
            want_z = escape_z
        else:
            want_z = -1 if agent.bnd_up > agent.bnd_down else 1
    else:
        z_wave = (frame // 30) % 2
        if z_wave == 0 and agent.bnd_up > 60:
            want_z = -1
        elif z_wave == 1 and agent.bnd_down > 60:
            want_z = 1

    return want_x, want_z


def _compute_survival_gap_dir(agent, enemies):
    """在无安全区的多敌包围下，朝敌人角度分布的最大缺口移动。"""
    angles = []
    for e in enemies:
        dx = e["x"] - agent.x
        dz = e["z"] - agent.z
        if abs(dx) < 1e-6 and abs(dz) < 1e-6:
            continue
        angles.append(math.atan2(dz, dx))

    if not angles:
        return 0, 0

    angles.sort()
    best_mid = angles[0]
    best_score = -1e9
    wrapped = angles + [angles[0] + 2 * math.pi]

    for idx in range(len(angles)):
        start = wrapped[idx]
        end = wrapped[idx + 1]
        gap = end - start
        mid = start + gap * 0.5
        dir_x = math.cos(mid)
        dir_z = math.sin(mid)

        space_x = agent.bnd_right if dir_x > 0 else agent.bnd_left
        space_z = agent.bnd_down if dir_z > 0 else agent.bnd_up
        score = gap + 0.002 * (space_x + space_z)
        if score > best_score:
            best_score = score
            best_mid = mid

    dir_x = math.cos(best_mid)
    dir_z = math.sin(best_mid)
    want_x = 1 if dir_x > 0.35 else (-1 if dir_x < -0.35 else 0)
    want_z = 1 if dir_z > 0.35 else (-1 if dir_z < -0.35 else 0)

    if want_x == 0 and want_z == 0:
        if abs(dir_x) >= abs(dir_z):
            want_x = 1 if dir_x >= 0 else -1
        else:
            want_z = 1 if dir_z >= 0 else -1

    return want_x, want_z


# ═══════ 策略层：边界逃脱承诺窗口 ═══════

class WallEscapeStrategy:
    """
    检测撤退方向被地图边界阻挡 → 反转 X + 强制 Z 逃脱。
    承诺窗口内保持逃脱方向不动摇，防止每帧振荡。

    对应 AS2 移植目标：RetreatMovementStrategy._computeRetreatMove 中新增逻辑。
    """
    def __init__(self, window_frames: int = 30):
        self.window = window_frames
        self._until = 0
        self._esc_x = 0
        self._esc_z = 0

    def apply(self, agent, want_x, want_z, enemy_z, margin, frame):
        """返回 (want_x, want_z)，可能被承诺窗口覆盖。"""
        # 承诺窗口内
        if frame < self._until:
            return self._esc_x, self._esc_z

        # 检测边界困境
        trapped = False
        if want_x < 0 and agent.bnd_left < margin:
            trapped = True
        elif want_x > 0 and agent.bnd_right < margin:
            trapped = True

        if not trapped:
            return want_x, want_z

        # X 逃脱：优先朝安全区推进，否则反转当前 X
        if agent.target_x is not None and abs(agent.target_x - agent.x) > 8:
            esc_x = 1 if agent.target_x > agent.x else -1
        else:
            esc_x = -want_x

        # Z 逃脱：优先朝安全区对齐，否则远离敌人 Z 轴
        if agent.target_z is not None and abs(agent.target_z - agent.z) > 8:
            esc_z = 1 if agent.target_z > agent.z else -1
        else:
            diff_z = enemy_z - agent.z
            if diff_z != 0:
                esc_z = -1 if diff_z > 0 else 1
            else:
                esc_z = -1 if agent.bnd_up > agent.bnd_down else 1

        if esc_z < 0 and agent.bnd_up < 50:
            esc_z = 1
        elif esc_z > 0 and agent.bnd_down < 50:
            esc_z = -1

        self._until = frame + self.window
        self._esc_x = esc_x
        self._esc_z = esc_z
        return esc_x, esc_z


def run_retreat_sim(
    scenario: CombatScenario,
    config: Optional[MovementConfig] = None,
    max_ticks: int = 500,
    safe_radius: float = 80.0,
    wall_escape: bool = False,
    wall_escape_window: int = 30,
) -> SimResult:
    """
    运行一次撤退仿真。

    wall_escape=True 时启用策略层承诺窗口（第二步修复）。
    """
    if config is None:
        config = MovementConfig()

    coll = CollisionWorld(scenario.map_data)
    agent = CombatAgent(
        x=scenario.agent_start[0],
        z=scenario.agent_start[1],
        config=config,
    )
    agent.target_x = scenario.safe_zone[0] if scenario.safe_zone else None
    agent.target_z = scenario.safe_zone[1] if scenario.safe_zone else None

    result = SimResult(
        scenario_name=scenario.name,
        config=config,
        objective="reach_safe",
    )

    strategy = WallEscapeStrategy(wall_escape_window) if wall_escape else None

    prev_move_x = 0
    prev_move_z = 0
    frame = 0

    for tick in range(max_ticks):
        frame = tick * 4

        agent.update_boundaries(scenario.map_data.bounds)

        ex, ez = scenario.enemy_pos
        want_x, want_z = _compute_retreat_dir(agent, ex, ez, scenario.safe_zone, frame)

        # 策略层叠加
        if strategy:
            want_x, want_z = strategy.apply(agent, want_x, want_z, ez, config.margin, frame)

        agent.clear_input()
        apply_boundary_aware_movement(agent, coll, want_x, want_z, frame)

        # 4. 统计方向变化
        cur_mx = (-1 if agent.move_left else (1 if agent.move_right else 0))
        cur_mz = (-1 if agent.move_up else (1 if agent.move_down else 0))
        if cur_mx != prev_move_x or cur_mz != prev_move_z:
            result.direction_changes += 1
        prev_move_x = cur_mx
        prev_move_z = cur_mz

        # 5. 移动
        agent.apply_movement(coll)
        agent.record_frame()

        # 6. 到达安全区判定
        if scenario.safe_zone and not result.reached_safe:
            sx, sz = scenario.safe_zone
            dist = math.sqrt((agent.x - sx) ** 2 + (agent.z - sz) ** 2)
            if dist < safe_radius:
                result.reached_safe = True
                result.escape_frames = frame
                break

    # 汇总
    result.total_frames = frame + 4
    result.stuck_frames = agent.stuck_frames
    result.corner_events = agent.corner_events
    result.slide_events = agent.slide_events
    result.trajectory = agent.trajectory

    return result


def run_chase_sim(
    scenario: CombatScenario,
    config: Optional[MovementConfig] = None,
    max_ticks: int = 500,
    safe_radius: float = 80.0,
    wall_escape: bool = False,
    wall_escape_window: int = 30,
) -> SimResult:
    """
    多移动敌人追逐仿真。

    敌人行为：每 tick 朝 agent 直线移动（受碰撞阻挡）。
    agent 行为：远离"最近威胁"撤退，边界逃脱承诺窗口生效。

    新增指标：
      - survival_frames: 最近敌人距离 > 被抓距离的持续帧数
      - min_enemy_dist:  仿真期间与最近敌人的最小距离
    """
    if config is None:
        config = MovementConfig()

    from scenario_gen import EnemyConfig
    coll = CollisionWorld(scenario.map_data)
    agent = CombatAgent(
        x=scenario.agent_start[0],
        z=scenario.agent_start[1],
        config=config,
    )
    agent.target_x = scenario.safe_zone[0] if scenario.safe_zone else None
    agent.target_z = scenario.safe_zone[1] if scenario.safe_zone else None

    # 初始化敌人列表
    enemies = []
    if scenario.enemies:
        for ec in scenario.enemies:
            enemies.append({"x": ec.x, "z": ec.z, "speed": ec.speed})
    else:
        enemies.append({"x": scenario.enemy_pos[0], "z": scenario.enemy_pos[1],
                         "speed": scenario.enemy_speed})

    enemy_trajectories = [[(e["x"], e["z"])] for e in enemies]

    result = SimResult(
        scenario_name=scenario.name,
        config=config,
        objective="reach_safe" if scenario.safe_zone else "survive",
    )
    strategy = WallEscapeStrategy(wall_escape_window) if wall_escape else None
    prev_move_x = 0
    prev_move_z = 0
    frame = 0

    CAUGHT_DIST = 40.0

    for tick in range(max_ticks):
        frame = tick * 4

        # ── 敌人移动（简单追逐 AI）──
        for ei, e in enumerate(enemies):
            dx = agent.x - e["x"]
            dz = agent.z - e["z"]
            dist = math.sqrt(dx * dx + dz * dz)
            if dist > 1.0:
                spd = e["speed"]
                nx = e["x"] + (dx / dist) * spd
                nz = e["z"] + (dz / dist) * spd
                # 每帧碰撞检测（简化：4 子帧合并为 1 步）
                for _ in range(4):
                    step_x = e["x"] + (nx - e["x"]) / 4
                    step_z = e["z"] + (nz - e["z"]) / 4
                    if coll.is_point_valid(step_x, e["z"]):
                        e["x"] = step_x
                    if coll.is_point_valid(e["x"], step_z):
                        e["z"] = step_z
                    nx = e["x"] + (dx / dist) * spd
                    nz = e["z"] + (dz / dist) * spd
            enemy_trajectories[ei].append((e["x"], e["z"]))

        # ── 找最近敌人（决策用）──
        nearest_ex, nearest_ez = enemies[0]["x"], enemies[0]["z"]
        nearest_dist = 9999.0
        threat_x = 0.0
        threat_z = 0.0
        threat_w = 0.0
        for e in enemies:
            d = math.sqrt((agent.x - e["x"]) ** 2 + (agent.z - e["z"]) ** 2)
            if d < nearest_dist:
                nearest_dist = d
                nearest_ex, nearest_ez = e["x"], e["z"]
            # 多敌场景下使用加权威胁中心，避免只盯最近敌人而撞向其余包抄者
            w = 1.0 / max(d, 40.0)
            threat_x += e["x"] * w
            threat_z += e["z"] * w
            threat_w += w

        result.min_enemy_dist = min(result.min_enemy_dist, nearest_dist)
        if nearest_dist < CAUGHT_DIST and not result.caught:
            result.caught = True
            result.caught_frame = frame
            break

        # ── agent 移动决策 ──
        agent.update_boundaries(scenario.map_data.bounds)
        if scenario.safe_zone is None and len(enemies) >= 3:
            want_x, want_z = _compute_survival_gap_dir(agent, enemies)
        else:
            decision_ex = nearest_ex
            decision_ez = nearest_ez
            use_threat_center = bool(scenario.map_data.collisions)
            if len(enemies) > 1 and threat_w > 0 and use_threat_center:
                decision_ex = threat_x / threat_w
                decision_ez = threat_z / threat_w
            want_x, want_z = _compute_retreat_dir(
                agent, decision_ex, decision_ez, scenario.safe_zone, frame)
        if strategy:
            want_x, want_z = strategy.apply(
                agent, want_x, want_z, nearest_ez, config.margin, frame)

        agent.clear_input()
        apply_boundary_aware_movement(agent, coll, want_x, want_z, frame)

        cur_mx = (-1 if agent.move_left else (1 if agent.move_right else 0))
        cur_mz = (-1 if agent.move_up else (1 if agent.move_down else 0))
        if cur_mx != prev_move_x or cur_mz != prev_move_z:
            result.direction_changes += 1
        prev_move_x = cur_mx
        prev_move_z = cur_mz

        agent.apply_movement(coll)
        agent.record_frame()

        # 安全区判定
        if scenario.safe_zone and not result.reached_safe:
            sx, sz = scenario.safe_zone
            dist = math.sqrt((agent.x - sx) ** 2 + (agent.z - sz) ** 2)
            if dist < safe_radius:
                result.reached_safe = True
                result.escape_frames = frame
                break

    result.total_frames = frame + 4
    result.stuck_frames = agent.stuck_frames
    result.corner_events = agent.corner_events
    result.slide_events = agent.slide_events
    result.trajectory = agent.trajectory
    # 附加多敌人数据到 result（供可视化用）
    result._enemy_trajectories = enemy_trajectories
    result._min_enemy_dist = result.min_enemy_dist
    result._caught = result.caught

    return result


def run_batch(
    scenarios: List[CombatScenario],
    config: Optional[MovementConfig] = None,
    max_ticks: int = 500,
    n_runs: int = 1,
    wall_escape: bool = False,
    wall_escape_window: int = 30,
) -> List[SimResult]:
    """批量运行多个场景，每个场景跑 n_runs 次。自动选择单敌/多敌仿真。"""
    results = []
    for s in scenarios:
        for _ in range(n_runs):
            if s.enemies:
                r = run_chase_sim(s, config, max_ticks,
                                  wall_escape=wall_escape,
                                  wall_escape_window=wall_escape_window)
            else:
                r = run_retreat_sim(s, config, max_ticks,
                                    wall_escape=wall_escape,
                                    wall_escape_window=wall_escape_window)
            results.append(r)
    return results
