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
    dead: bool = False
    death_frame: int = -1
    death_reason: str = ""
    down_count: int = 0
    tough_break_count: int = 0
    shield_uses: int = 0
    escape_skill_uses: int = 0
    wakeup_guard_uses: int = 0
    evaded_hits: int = 0
    total_damage_taken: float = 0.0
    total_impact_taken: float = 0.0
    hp_remaining: float = 0.0
    hp_max: float = 0.0

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
        if self.objective in ("survive", "burst_survival"):
            return (not self.caught) and (not self.dead)
        return self.reached_safe

    @property
    def hp_remaining_pct(self) -> float:
        if self.hp_max <= 0:
            return 0.0
        return self.hp_remaining / self.hp_max

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
            "dead": self.dead,
            "death_frame": self.death_frame if self.death_frame >= 0 else None,
            "death_reason": self.death_reason or None,
            "min_enemy_dist": (
                round(self.min_enemy_dist, 4)
                if self.min_enemy_dist != float("inf")
                else None
            ),
            "escape_frames": self.escape_frames,
            "corner_events": self.corner_events,
            "slide_events": self.slide_events,
            "smoothness": round(self.smoothness, 4),
            "down_count": self.down_count,
            "tough_break_count": self.tough_break_count,
            "shield_uses": self.shield_uses,
            "escape_skill_uses": self.escape_skill_uses,
            "wakeup_guard_uses": self.wakeup_guard_uses,
            "evaded_hits": self.evaded_hits,
            "total_damage_taken": round(self.total_damage_taken, 4),
            "total_impact_taken": round(self.total_impact_taken, 4),
            "hp_remaining_pct": round(self.hp_remaining_pct, 4),
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


def _pick_z_dir_by_space(agent, margin):
    """Approx MovementResolver.pickZDirBySpaceEx without bullet-pressure input."""
    up_space = agent.bnd_up
    down_space = agent.bnd_down

    if up_space < margin and down_space < margin:
        return 0
    if up_space < margin:
        return 2
    if down_space < margin:
        return -2
    return -1 if up_space >= down_space else 1


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


def _compute_enemy_pressure(agent, enemies, config):
    """
    近似 ThreatAssessor 的多敌空间感知。

    输出：
      - left/right_count   ThreatAssessor 左右敌人数
      - nearby_count       近距敌人数
      - encirclement       左右同时有敌时的包围度
      - dominant_side      1=右侧更挤, -1=左侧更挤, 0=均衡
      - threat_center_x/z  加权威胁中心（多敌时比“最近敌人”更稳）
    """
    left_count = 0
    right_count = 0
    total_left_count = 0
    total_right_count = 0
    nearby_count = 0
    left_weight = 0.0
    right_weight = 0.0
    threat_x = 0.0
    threat_z = 0.0
    threat_w = 0.0

    for e in enemies:
        dx = e["x"] - agent.x
        dz = e["z"] - agent.z
        dist = math.sqrt(dx * dx + dz * dz)

        if dx < 0:
            total_left_count += 1
        elif dx > 0:
            total_right_count += 1

        if dist <= config.threat_scan_range:
            if dx < 0:
                left_count += 1
            elif dx > 0:
                right_count += 1
            if dx < 0:
                left_weight += 1.0 / max(dist, 40.0)
            elif dx > 0:
                right_weight += 1.0 / max(dist, 40.0)

        if dist <= config.nearby_enemy_range:
            nearby_count += 1

        w = 1.0 / max(dist, 40.0)
        threat_x += e["x"] * w
        threat_z += e["z"] * w
        threat_w += w

    encirclement = min(1.0, (left_count * right_count) / 4.0)
    dominant_side = 0
    if right_count > left_count + config.pincer_side_advantage:
        dominant_side = 1
    elif left_count > right_count + config.pincer_side_advantage:
        dominant_side = -1
    elif total_right_count > total_left_count + config.pincer_side_advantage:
        dominant_side = 1
    elif total_left_count > total_right_count + config.pincer_side_advantage:
        dominant_side = -1
    elif right_weight > left_weight * config.pressure_dominance_ratio:
        dominant_side = 1
    elif left_weight > right_weight * config.pressure_dominance_ratio:
        dominant_side = -1

    if threat_w > 0:
        threat_x /= threat_w
        threat_z /= threat_w
    else:
        threat_x = agent.x
        threat_z = agent.z

    return {
        "left_count": left_count,
        "right_count": right_count,
        "total_left_count": total_left_count,
        "total_right_count": total_right_count,
        "left_weight": left_weight,
        "right_weight": right_weight,
        "nearby_count": nearby_count,
        "encirclement": encirclement,
        "dominant_side": dominant_side,
        "threat_center_x": threat_x,
        "threat_center_z": threat_z,
    }


class ThreatTracker:
    """Cache pressure samples to match ThreatAssessor's periodic refresh."""

    def __init__(self, sample_interval_frames: int):
        self.sample_interval_frames = sample_interval_frames
        self._last_sample_frame = -10**9
        self._cached = None

    def sample(self, agent, enemies, frame, config):
        if (
            self._cached is None
            or frame - self._last_sample_frame >= self.sample_interval_frames
        ):
            self._cached = _compute_enemy_pressure(agent, enemies, config)
            self._last_sample_frame = frame
        return self._cached


def _apply_pack_pressure(agent, config, pressure, want_x):
    """
    近似 EngageMovementStrategy 的 safeX + edgeEscapeX。

    目的不是完整复刻交战走位，而是在多敌追逐中模拟：
      1. 被包夹时向“敌人更少的一侧”突围
      2. 贴边时优先向场内回拉，避免沿边硬挤
    """
    edge_escape_x = 0
    if agent.bnd_left < config.edge_escape_margin:
        edge_escape_x = 1
    elif agent.bnd_right < config.edge_escape_margin:
        edge_escape_x = -1

    if edge_escape_x != 0:
        return edge_escape_x

    safe_x = 0
    dominant_side = pressure["dominant_side"]
    needs_evade = (
        pressure["encirclement"] > config.encirclement_evade_threshold
        or pressure["nearby_count"] >= config.evade_nearby_count
    )
    if needs_evade and dominant_side != 0:
        safe_x = -dominant_side
        if safe_x < 0 and agent.bnd_left < config.edge_safe_space:
            safe_x = 1 if agent.bnd_right > config.edge_safe_space else 0
        elif safe_x > 0 and agent.bnd_right < config.edge_safe_space:
            safe_x = -1 if agent.bnd_left > config.edge_safe_space else 0

    if safe_x != 0:
        return safe_x
    return want_x


class StrafePulsePlanner:
    """Approx EngageMovementStrategy's pulsed Z movement."""

    def __init__(self):
        self._strafe_dir = 0
        self._strafe_pulse_end = 0
        self._strafe_next_start = 0
        self._pulse_index = 0

    def _pick_dir(self, agent, config):
        z_pick = _pick_z_dir_by_space(agent, config.edge_escape_margin)
        if z_pick == 0:
            return 0

        direction = -1 if z_pick < 0 else 1
        if abs(z_pick) == 2:
            return direction
        if self._strafe_dir == 0:
            return direction
        return -self._strafe_dir

    def apply(self, agent, pressure, want_z, frame, config):
        in_pulse = frame < self._strafe_pulse_end
        if not in_pulse and frame >= self._strafe_next_start:
            self._strafe_dir = self._pick_dir(agent, config)
            span = max(0, config.strafe_pulse_max - config.strafe_pulse_min)
            pulse_len = config.strafe_pulse_min
            if span > 0:
                pulse_len += self._pulse_index % (span + 1)

            pressure_level = min(
                1.0,
                pressure["encirclement"] + pressure["nearby_count"] / 3.0,
            )
            gap = config.strafe_gap_base - int(math.floor(pressure_level * 5))
            gap = max(config.strafe_gap_min, gap)
            jitter = 0 if gap <= 1 else self._pulse_index % gap

            self._strafe_pulse_end = frame + pulse_len
            self._strafe_next_start = self._strafe_pulse_end + gap + jitter
            self._pulse_index += 1
            in_pulse = True

        if in_pulse and self._strafe_dir != 0:
            return self._strafe_dir
        return want_z


class EngageTacticalPlanner:
    """
    Approx EngageMovementStrategy for multi-enemy chase tests.

    This keeps the simulation movement-only, but ports the stateful parts that
    matter for offline tuning: periodic threat sampling, pulsed strafing,
    edge re-entry, and anti-pincer X-side selection.
    """

    def __init__(self):
        self._pulse = StrafePulsePlanner()

    def apply(
        self,
        agent,
        pressure,
        decision_x,
        nearest_dist,
        want_x,
        want_z,
        frame,
        config,
    ):
        decision_dx = decision_x - agent.x
        wants_kite = (want_x != 0 and abs(decision_dx) < config.kite_x_threshold)
        wants_evade = (
            pressure["encirclement"] > config.encirclement_evade_threshold
            or pressure["nearby_count"] >= config.evade_nearby_count
        )

        edge_escape_x = 0
        if agent.bnd_left < config.edge_escape_margin:
            edge_escape_x = 1
        elif agent.bnd_right < config.edge_escape_margin:
            edge_escape_x = -1

        if edge_escape_x != 0 and nearest_dist < config.kite_x_threshold * 1.5:
            wants_evade = True

        if not wants_kite and not wants_evade:
            return want_x, want_z

        move_x = want_x
        move_z = self._pulse.apply(agent, pressure, want_z, frame, config)

        safe_x = 0
        if pressure["encirclement"] > 0.25:
            left_count = pressure["left_count"]
            right_count = pressure["right_count"]
            if left_count > right_count + 1:
                safe_x = 1
            elif right_count > left_count + 1:
                safe_x = -1
            elif pressure["dominant_side"] != 0:
                safe_x = -pressure["dominant_side"]

            if safe_x < 0 and agent.bnd_left < config.edge_safe_space:
                safe_x = 1 if agent.bnd_right > config.edge_safe_space else 0
            elif safe_x > 0 and agent.bnd_right < config.edge_safe_space:
                safe_x = -1 if agent.bnd_left > config.edge_safe_space else 0

        kite_dir = -1 if decision_dx > 0 else 1
        kite_wall = (
            (kite_dir < 0 and agent.bnd_left < config.edge_escape_margin)
            or (kite_dir > 0 and agent.bnd_right < config.edge_escape_margin)
        )

        if wants_kite:
            if not kite_wall:
                move_x = kite_dir
            elif edge_escape_x != 0:
                move_x = edge_escape_x
        elif wants_evade and edge_escape_x != 0:
            move_x = edge_escape_x

        if wants_evade and safe_x != 0:
            if move_x == 0 or (
                move_x != safe_x
                and (
                    pressure["encirclement"] > 0.6
                    or pressure["dominant_side"] != 0
                )
            ):
                move_x = safe_x

        if move_x == 0 and edge_escape_x != 0:
            move_x = edge_escape_x

        return move_x, move_z


class PackEscapePlanner:
    """
    多敌逃逸承诺窗口。

    用于近似 EngageMovementStrategy 中：
      - safeX 选边
      - edgeEscapeX 贴边回拉
      - gap escape 缺口突围

    核心目的：避免在强压力场景里每 tick 重新改主意。
    """
    def __init__(self, window_frames: int = 20):
        self.window = window_frames
        self._until = 0
        self._esc_x = 0
        self._esc_z = 0

    def _commit(self, frame: int, esc_x: int, esc_z: int):
        self._until = frame + self.window
        self._esc_x = esc_x
        self._esc_z = esc_z
        return esc_x, esc_z

    def apply(self, agent, scenario, enemies, pressure, want_x, want_z, frame, config):
        if frame < self._until:
            return self._esc_x, self._esc_z

        edge_x_trapped = (
            agent.bnd_left < config.edge_escape_margin
            or agent.bnd_right < config.edge_escape_margin
        )
        min_bnd = min(agent.bnd_left, agent.bnd_right, agent.bnd_up, agent.bnd_down)
        strong_side = (pressure["dominant_side"] != 0)
        under_pack_pressure = (
            pressure["encirclement"] > config.encirclement_evade_threshold
            or pressure["nearby_count"] >= config.pack_escape_min_nearby
        )

        # 1) 贴边回场内：优先保留向场内的 X 承诺，并借缺口方向补 Z。
        if edge_x_trapped and under_pack_pressure:
            esc_x = _apply_pack_pressure(agent, config, pressure, want_x)
            gap_x, gap_z = _compute_survival_gap_dir(agent, enemies)
            esc_z = gap_z if gap_z != 0 else want_z
            if esc_x == 0:
                esc_x = 1 if agent.bnd_left < agent.bnd_right else -1
            return self._commit(frame, esc_x, esc_z)

        # 2) 无安全区的蜂群/包围：直接沿最大缺口突围，并保持一段时间。
        if (scenario.safe_zone is None
                and len(enemies) >= config.survival_gap_enemy_min
                and pressure["encirclement"] > config.encirclement_evade_threshold):
            gap_x, gap_z = _compute_survival_gap_dir(agent, enemies)
            return self._commit(frame, gap_x, gap_z)

        # 3) 单侧优势明显时：先朝安全侧持续突围，必要时借缺口方向补 Z。
        if strong_side and under_pack_pressure:
            esc_x = _apply_pack_pressure(agent, config, pressure, want_x)
            esc_z = want_z
            gap_x, gap_z = _compute_survival_gap_dir(agent, enemies)
            if gap_z != 0 and (esc_x != want_x or scenario.safe_zone is None):
                esc_z = gap_z
            if (agent.bnd_corner > 0
                    or min_bnd < config.edge_escape_margin * 2
                    or scenario.safe_zone is None):
                if gap_x != 0 and esc_x == want_x and min_bnd > config.edge_escape_margin:
                    esc_x = gap_x
                if gap_z != 0:
                    esc_z = gap_z
            if esc_x != want_x or esc_z != want_z:
                return self._commit(frame, esc_x, esc_z)

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
    threat_tracker = ThreatTracker(config.threat_sample_interval)
    tactical_planner = EngageTacticalPlanner()
    pack_planner = PackEscapePlanner(config.pack_escape_window)
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

        # ── 找最近敌人 + 包围压力（决策用）──
        nearest_ex, nearest_ez = enemies[0]["x"], enemies[0]["z"]
        nearest_dist = 9999.0
        for e in enemies:
            d = math.sqrt((agent.x - e["x"]) ** 2 + (agent.z - e["z"]) ** 2)
            if d < nearest_dist:
                nearest_dist = d
                nearest_ex, nearest_ez = e["x"], e["z"]

        result.min_enemy_dist = min(result.min_enemy_dist, nearest_dist)
        if nearest_dist < CAUGHT_DIST and not result.caught:
            result.caught = True
            result.caught_frame = frame
            break

        # ── agent 移动决策 ──
        agent.update_boundaries(scenario.map_data.bounds)
        pressure = threat_tracker.sample(agent, enemies, frame, config)

        if (scenario.safe_zone is None
                and len(enemies) >= config.survival_gap_enemy_min
                and pressure["encirclement"] > config.encirclement_evade_threshold):
            want_x, want_z = _compute_survival_gap_dir(agent, enemies)
        else:
            decision_ex = nearest_ex
            decision_ez = nearest_ez
            use_threat_center = (
                len(enemies) > 1
                and (pressure["nearby_count"] >= 2 or bool(scenario.map_data.collisions))
            )
            if use_threat_center:
                decision_ex = pressure["threat_center_x"]
                decision_ez = pressure["threat_center_z"]
            want_x, want_z = _compute_retreat_dir(
                agent, decision_ex, decision_ez, scenario.safe_zone, frame)
            want_x, want_z = tactical_planner.apply(
                agent,
                pressure,
                decision_ex,
                nearest_dist,
                want_x,
                want_z,
                frame,
                config,
            )
        want_x, want_z = pack_planner.apply(
            agent, scenario, enemies, pressure, want_x, want_z, frame, config)
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


def _spawn_enemy_runtime(scenario: CombatScenario):
    enemies = []
    if scenario.enemies:
        for ec in scenario.enemies:
            enemies.append({
                "x": ec.x,
                "z": ec.z,
                "speed": ec.speed,
                "chase_range": ec.chase_range,
                "attack_range": ec.attack_range,
                "attack_damage": ec.attack_damage,
                "attack_impact": ec.attack_impact,
                "attack_cooldown_frames": ec.attack_cooldown_frames,
                "attack_windup_frames": ec.attack_windup_frames,
                "attack_tag": ec.attack_tag,
                "_next_attack_frame": 0,
            })
    else:
        enemies.append({
            "x": scenario.enemy_pos[0],
            "z": scenario.enemy_pos[1],
            "speed": scenario.enemy_speed,
            "chase_range": 999.0,
            "attack_range": 0.0,
            "attack_damage": 0.0,
            "attack_impact": 0.0,
            "attack_cooldown_frames": 24,
            "attack_windup_frames": 4,
            "attack_tag": "hit",
            "_next_attack_frame": 0,
        })
    return enemies


def _step_enemy_motion(agent, enemies, coll):
    for e in enemies:
        dx = agent.x - e["x"]
        dz = agent.z - e["z"]
        dist = math.sqrt(dx * dx + dz * dz)
        if dist <= 1.0 or dist > e["chase_range"]:
            continue

        spd = e["speed"]
        for _ in range(4):
            step_dx = agent.x - e["x"]
            step_dz = agent.z - e["z"]
            step_dist = math.sqrt(step_dx * step_dx + step_dz * step_dz)
            if step_dist <= 1.0:
                break

            nx = e["x"] + (step_dx / step_dist) * spd
            nz = e["z"] + (step_dz / step_dist) * spd
            if coll.is_point_valid(nx, e["z"]):
                e["x"] = nx
            if coll.is_point_valid(e["x"], nz):
                e["z"] = nz


def _nearest_enemy(agent, enemies):
    nearest = None
    nearest_dist = float("inf")
    for e in enemies:
        dist = math.sqrt((agent.x - e["x"]) ** 2 + (agent.z - e["z"]) ** 2)
        if dist < nearest_dist:
            nearest = e
            nearest_dist = dist
    return nearest, nearest_dist


def _maybe_activate_shield(agent, enemies, pressure, frame, config):
    if agent.is_downed(frame):
        return False
    if agent.shield_active(frame):
        return False

    hp_ratio = agent.hp / max(1.0, agent.hp_max)
    recent_hit = frame - agent.last_hit_frame <= config.burst_guard_recent_hit_frames
    nearby_ok = pressure["nearby_count"] >= config.burst_guard_nearby_enemies
    imminent_damage, imminent_attackers = _estimate_imminent_burst(agent, enemies, frame)
    lethal_burst = imminent_damage >= agent.hp * config.overguard_imminent_damage_ratio
    overguard_ready = frame >= agent.last_shield_frame + config.overguard_recast_gap_frames

    if frame < agent.shield_cooldown_until_frame and not (lethal_burst and overguard_ready):
        return False

    heavy_threat = False
    for e in enemies:
        if e["attack_range"] <= 0 or e["attack_impact"] <= 0:
            continue
        dist = math.sqrt((agent.x - e["x"]) ** 2 + (agent.z - e["z"]) ** 2)
        if dist <= e["attack_range"] * 1.25 and (
            e["attack_impact"] >= agent.impact_cap * config.burst_guard_impact_ratio
        ):
            heavy_threat = True
            break

    should_guard = False
    if heavy_threat and nearby_ok:
        should_guard = True
    elif heavy_threat and recent_hit:
        should_guard = True
    elif hp_ratio <= config.burst_guard_hp_threshold and pressure["nearby_count"] >= 1:
        should_guard = True
    elif imminent_attackers >= 2 and imminent_damage >= agent.hp * config.burst_guard_imminent_damage_ratio:
        should_guard = True
    elif lethal_burst and overguard_ready:
        should_guard = True

    if not should_guard:
        return False

    agent.shield_until_frame = frame + config.shield_duration_frames
    agent.shield_cooldown_until_frame = frame + config.shield_cooldown_frames
    agent.last_shield_frame = frame
    agent.pure_move_until_frame = max(
        agent.pure_move_until_frame,
        frame + config.post_break_pure_move_frames,
    )
    agent.shield_uses += 1
    return True


def _estimate_imminent_burst(agent, enemies, frame, horizon_frames=16):
    total_damage = 0.0
    attacker_count = 0
    for e in enemies:
        if e["attack_range"] <= 0 or e["attack_damage"] <= 0:
            continue
        if e["_next_attack_frame"] > frame + horizon_frames:
            continue
        dist = math.sqrt((agent.x - e["x"]) ** 2 + (agent.z - e["z"]) ** 2)
        if dist > e["attack_range"] * 1.1:
            continue
        total_damage += e["attack_damage"]
        attacker_count += 1
    return total_damage, attacker_count


def _apply_escape_reposition(agent, coll, dash_x, dash_z):
    steps = 12
    step_x = dash_x / steps
    step_z = dash_z / steps
    for _ in range(steps):
        nx = agent.x + step_x
        nz = agent.z + step_z
        if coll.is_point_valid(nx, agent.z):
            agent.x = nx
        if coll.is_point_valid(agent.x, nz):
            agent.z = nz


def _push_enemy_away(agent, enemy, coll, distance):
    dx = enemy["x"] - agent.x
    dz = enemy["z"] - agent.z
    dist = math.sqrt(dx * dx + dz * dz)
    if dist <= 1e-6:
        dx, dz, dist = 1.0, 0.0, 1.0
    push_x = (dx / dist) * distance
    push_z = (dz / dist) * distance * 0.6
    steps = 10
    for _ in range(steps):
        nx = enemy["x"] + push_x / steps
        nz = enemy["z"] + push_z / steps
        if coll.is_point_valid(nx, enemy["z"]):
            enemy["x"] = nx
        if coll.is_point_valid(enemy["x"], nz):
            enemy["z"] = nz


def _compute_escape_skill_dir(agent, scenario, enemies, pressure, frame, config):
    if scenario.safe_zone is None and (
        len(enemies) >= config.survival_gap_enemy_min
        and pressure["encirclement"] > config.encirclement_evade_threshold
    ):
        return _compute_survival_gap_dir(agent, enemies)

    decision_ex = pressure["threat_center_x"]
    decision_ez = pressure["threat_center_z"]
    want_x, want_z = _compute_retreat_dir(
        agent, decision_ex, decision_ez, scenario.safe_zone, frame
    )
    tactical_planner = EngageTacticalPlanner()
    pack_planner = PackEscapePlanner(config.pack_escape_window)
    nearest_dist = min(
        math.sqrt((agent.x - e["x"]) ** 2 + (agent.z - e["z"]) ** 2)
        for e in enemies
    )
    want_x, want_z = tactical_planner.apply(
        agent,
        pressure,
        decision_ex,
        nearest_dist,
        want_x,
        want_z,
        frame,
        config,
    )
    want_x, want_z = pack_planner.apply(
        agent, scenario, enemies, pressure, want_x, want_z, frame, config
    )
    if want_x == 0 and want_z == 0:
        return _compute_survival_gap_dir(agent, enemies)
    return want_x, want_z


def _scrub_pending_hits(agent, pending_hits, frame, config):
    remaining = []
    cancelled = 0
    cancel_until = frame + config.combo_break_cancel_window_frames
    cancel_radius = config.combo_break_cancel_radius

    for hit in pending_hits:
        if hit["hit_frame"] > cancel_until:
            remaining.append(hit)
            continue
        source = hit.get("source")
        if source is None:
            remaining.append(hit)
            continue
        source_dist = math.sqrt((agent.x - source["x"]) ** 2 + (agent.z - source["z"]) ** 2)
        if source_dist > cancel_radius:
            remaining.append(hit)
            continue
        cancelled += 1

    if cancelled > 0:
        agent.evaded_hits += cancelled
    return remaining


def _maybe_cast_escape_skill(agent, scenario, enemies, pressure, frame, config, coll, pending_hits):
    if frame < agent.escape_cooldown_until_frame:
        return False
    if agent.is_downed(frame):
        return False

    hp_ratio = agent.hp / max(1.0, agent.hp_max)
    recent_hit = frame - agent.last_hit_frame <= config.burst_guard_recent_hit_frames
    edge_pinned = min(agent.bnd_left, agent.bnd_right) < config.edge_escape_margin
    imminent_damage, imminent_attackers = _estimate_imminent_burst(agent, enemies, frame)
    heavy_threat = False
    for e in enemies:
        if e["attack_range"] <= 0 or e["attack_impact"] <= 0:
            continue
        dist = math.sqrt((agent.x - e["x"]) ** 2 + (agent.z - e["z"]) ** 2)
        if dist <= e["attack_range"] * 1.25 and (
            e["attack_impact"] >= agent.impact_cap * config.escape_skill_impact_ratio
        ):
            heavy_threat = True
            break

    should_escape = False
    if heavy_threat and pressure["nearby_count"] >= config.escape_skill_nearby_enemies:
        should_escape = True
    elif recent_hit and (
        edge_pinned or pressure["encirclement"] > config.encirclement_evade_threshold
    ):
        should_escape = True
    elif hp_ratio <= config.escape_skill_hp_threshold and pressure["nearby_count"] >= 1:
        should_escape = True
    elif frame < agent.pure_move_until_frame and pressure["nearby_count"] >= 1:
        should_escape = True
    elif imminent_attackers >= config.escape_imminent_attackers and (
        imminent_damage >= agent.hp * config.escape_imminent_damage_ratio
    ):
        should_escape = True
    elif imminent_attackers >= 1 and hp_ratio <= config.escape_single_imminent_hp_threshold and (
        imminent_damage >= agent.hp * config.escape_single_imminent_damage_ratio
    ):
        should_escape = True

    if not should_escape:
        return False

    want_x, want_z = _compute_escape_skill_dir(agent, scenario, enemies, pressure, frame, config)
    if want_x == 0 and want_z == 0:
        return False

    dash_x = want_x * config.escape_dash_distance
    dash_z = want_z * config.escape_dash_distance * 0.6
    _apply_escape_reposition(agent, coll, dash_x, dash_z)
    agent.update_boundaries(scenario.map_data.bounds)
    agent.escape_invuln_until_frame = frame + config.escape_invuln_frames
    agent.escape_cooldown_until_frame = frame + config.escape_cooldown_frames
    agent.pure_move_until_frame = max(
        agent.pure_move_until_frame,
        frame + config.post_break_pure_move_frames,
    )
    agent.impact_force *= config.escape_impact_clear_ratio
    for enemy in enemies:
        dist = math.sqrt((agent.x - enemy["x"]) ** 2 + (agent.z - enemy["z"]) ** 2)
        if dist <= config.escape_push_radius:
            _push_enemy_away(agent, enemy, coll, config.escape_push_distance)
            enemy["_next_attack_frame"] = max(
                enemy["_next_attack_frame"],
                frame + config.escape_attack_delay_frames,
            )
    pending_hits[:] = _scrub_pending_hits(agent, pending_hits, frame, config)
    agent.escape_skill_uses += 1
    return True


def _activate_wakeup_guard(agent, scenario, enemies, pressure, frame, config, coll, pending_hits):
    imminent_damage, imminent_attackers = _estimate_imminent_burst(agent, enemies, frame)
    nearby = pressure["nearby_count"]
    if nearby <= 0 and imminent_attackers <= 0:
        return False

    want_x, want_z = _compute_escape_skill_dir(
        agent, scenario, enemies, pressure, frame, config
    )
    if want_x != 0 or want_z != 0:
        dash_x = want_x * config.wakeup_guard_dash_distance
        dash_z = want_z * config.wakeup_guard_dash_distance * 0.6
        _apply_escape_reposition(agent, coll, dash_x, dash_z)
        agent.update_boundaries(scenario.map_data.bounds)

    agent.escape_invuln_until_frame = max(
        agent.escape_invuln_until_frame,
        frame + config.wakeup_guard_invuln_frames,
    )
    agent.shield_until_frame = max(
        agent.shield_until_frame,
        frame + config.wakeup_guard_shield_frames,
    )
    agent.pure_move_until_frame = max(
        agent.pure_move_until_frame,
        frame + config.wakeup_guard_pure_move_frames,
    )
    agent.impact_force *= config.wakeup_guard_impact_clear_ratio

    push_radius = config.wakeup_guard_push_radius
    if imminent_attackers >= 2:
        push_radius += 20.0
    if imminent_damage >= agent.hp * 0.5:
        push_radius += 20.0
    for enemy in enemies:
        dist = math.sqrt((agent.x - enemy["x"]) ** 2 + (agent.z - enemy["z"]) ** 2)
        if dist <= push_radius:
            _push_enemy_away(agent, enemy, coll, config.wakeup_guard_push_distance)
            enemy["_next_attack_frame"] = max(
                enemy["_next_attack_frame"],
                frame + config.wakeup_guard_attack_delay_frames,
            )

    pending_hits[:] = _scrub_pending_hits(agent, pending_hits, frame, config)
    agent.wakeup_guard_uses += 1
    return True


def _schedule_enemy_attacks(agent, enemies, pending_hits, frame):
    for e in enemies:
        if e["attack_range"] <= 0 or e["attack_damage"] <= 0:
            continue
        if frame < e["_next_attack_frame"]:
            continue

        dist = math.sqrt((agent.x - e["x"]) ** 2 + (agent.z - e["z"]) ** 2)
        if dist > e["attack_range"]:
            continue

        pending_hits.append({
            "hit_frame": frame + e["attack_windup_frames"],
            "damage": e["attack_damage"],
            "impact": e["attack_impact"],
            "tag": e["attack_tag"],
            "range": e["attack_range"],
            "source": e,
        })
        e["_next_attack_frame"] = frame + e["attack_cooldown_frames"]


def _resolve_pending_hits(agent, pending_hits, result, frame, config):
    remaining = []
    for hit in pending_hits:
        if hit["hit_frame"] > frame:
            remaining.append(hit)
            continue
        if not agent.alive:
            continue

        source = hit.get("source")
        if source is not None:
            source_dist = math.sqrt((agent.x - source["x"]) ** 2 + (agent.z - source["z"]) ** 2)
            if source_dist > hit.get("range", 0.0) * 1.05:
                agent.evaded_hits += 1
                continue
        if agent.escape_active(frame):
            agent.evaded_hits += 1
            continue

        damage = hit["damage"]
        impact = hit["impact"]
        if agent.shield_active(frame):
            damage *= config.shield_damage_mult
            impact *= config.shield_impact_mult
        if agent.is_downed(frame):
            damage *= config.downed_damage_mult

        agent.last_hit_frame = frame
        agent.last_hit_tag = hit["tag"]
        agent.total_damage_taken += damage
        agent.total_impact_taken += impact
        agent.hp -= damage
        agent.impact_force += impact

        if agent.hp <= 0:
            agent.alive = False
            result.dead = True
            result.death_frame = frame
            result.death_reason = f"LETHAL:{hit['tag']}"
            continue

        if (not agent.is_downed(frame)) and agent.impact_force > agent.impact_cap:
            agent.tough_break_count += 1
            agent.down_count += 1
            agent.impact_force = 0.0
            agent.down_until_frame = frame + config.down_recovery_frames
            agent.pure_move_until_frame = max(
                agent.pure_move_until_frame,
                frame + config.post_break_pure_move_frames,
            )
        elif (not agent.is_downed(frame)) and agent.impact_force > agent.impact_stagger_boundary:
            agent.pure_move_until_frame = max(
                agent.pure_move_until_frame,
                frame + config.stagger_move_hold_frames,
            )
    return remaining


def run_burst_survival_sim(
    scenario: CombatScenario,
    config: Optional[MovementConfig] = None,
    max_ticks: int = 500,
    safe_radius: float = 80.0,
    wall_escape: bool = False,
    wall_escape_window: int = 30,
) -> SimResult:
    if config is None:
        config = MovementConfig()

    coll = CollisionWorld(scenario.map_data)
    agent = CombatAgent(
        x=scenario.agent_start[0],
        z=scenario.agent_start[1],
        speed=scenario.agent_speed,
        config=config,
        hp=scenario.agent_hp,
        hp_max=scenario.agent_hp,
        impact_cap=scenario.agent_impact_cap,
        impact_stagger_boundary=scenario.agent_stagger_boundary,
        down_until_frame=scenario.initial_down_frames,
        pure_move_until_frame=scenario.initial_down_frames,
    )
    agent.target_x = scenario.safe_zone[0] if scenario.safe_zone else None
    agent.target_z = scenario.safe_zone[1] if scenario.safe_zone else None

    enemies = _spawn_enemy_runtime(scenario)
    enemy_trajectories = [[(e["x"], e["z"])] for e in enemies]
    pending_hits = []

    result = SimResult(
        scenario_name=scenario.name,
        config=config,
        objective="burst_survival",
        hp_remaining=agent.hp,
        hp_max=agent.hp_max,
    )

    strategy = WallEscapeStrategy(wall_escape_window) if wall_escape else None
    threat_tracker = ThreatTracker(config.threat_sample_interval)
    tactical_planner = EngageTacticalPlanner()
    pack_planner = PackEscapePlanner(config.pack_escape_window)
    prev_move_x = 0
    prev_move_z = 0
    base_speed = agent.speed
    frame = 0
    limit_ticks = min(max_ticks, scenario.survival_ticks)
    prev_downed = agent.is_downed(0)

    for tick in range(limit_ticks):
        frame = tick * 4

        _step_enemy_motion(agent, enemies, coll)
        for idx, e in enumerate(enemies):
            enemy_trajectories[idx].append((e["x"], e["z"]))

        pending_hits = _resolve_pending_hits(agent, pending_hits, result, frame, config)
        if not agent.alive:
            break

        nearest, nearest_dist = _nearest_enemy(agent, enemies)
        result.min_enemy_dist = min(result.min_enemy_dist, nearest_dist)

        agent.update_boundaries(scenario.map_data.bounds)
        pressure = threat_tracker.sample(agent, enemies, frame, config)
        current_downed = agent.is_downed(frame)
        if prev_downed and not current_downed:
            agent.pure_move_until_frame = max(
                agent.pure_move_until_frame,
                frame + config.post_break_pure_move_frames,
            )
            if _activate_wakeup_guard(
                agent, scenario, enemies, pressure, frame, config, coll, pending_hits
            ):
                nearest, nearest_dist = _nearest_enemy(agent, enemies)
                result.min_enemy_dist = min(result.min_enemy_dist, nearest_dist)
                agent.update_boundaries(scenario.map_data.bounds)
                pressure = _compute_enemy_pressure(agent, enemies, config)
        cast_escape = _maybe_cast_escape_skill(
            agent, scenario, enemies, pressure, frame, config, coll, pending_hits
        )
        if cast_escape:
            nearest, nearest_dist = _nearest_enemy(agent, enemies)
            result.min_enemy_dist = min(result.min_enemy_dist, nearest_dist)
            agent.update_boundaries(scenario.map_data.bounds)
            pressure = _compute_enemy_pressure(agent, enemies, config)
        if not cast_escape:
            _maybe_activate_shield(agent, enemies, pressure, frame, config)

        if agent.is_downed(frame):
            agent.clear_input()
            cur_mx = 0
            cur_mz = 0
        else:
            decision_ex = nearest["x"] if nearest is not None else agent.x
            decision_ez = nearest["z"] if nearest is not None else agent.z
            use_threat_center = (
                len(enemies) > 1
                and (pressure["nearby_count"] >= 2 or bool(scenario.map_data.collisions))
            )
            if use_threat_center:
                decision_ex = pressure["threat_center_x"]
                decision_ez = pressure["threat_center_z"]

            if (scenario.safe_zone is None
                    and len(enemies) >= config.survival_gap_enemy_min
                    and pressure["encirclement"] > config.encirclement_evade_threshold):
                want_x, want_z = _compute_survival_gap_dir(agent, enemies)
            else:
                want_x, want_z = _compute_retreat_dir(
                    agent, decision_ex, decision_ez, scenario.safe_zone, frame)
                want_x, want_z = tactical_planner.apply(
                    agent,
                    pressure,
                    decision_ex,
                    nearest_dist,
                    want_x,
                    want_z,
                    frame,
                    config,
                )

            want_x, want_z = pack_planner.apply(
                agent, scenario, enemies, pressure, want_x, want_z, frame, config)
            if strategy and nearest is not None:
                want_x, want_z = strategy.apply(
                    agent, want_x, want_z, nearest["z"], config.margin, frame)

            agent.clear_input()
            apply_boundary_aware_movement(agent, coll, want_x, want_z, frame)

            cur_mx = -1 if agent.move_left else (1 if agent.move_right else 0)
            cur_mz = -1 if agent.move_up else (1 if agent.move_down else 0)

            agent.speed = (
                base_speed * config.emergency_speed_mult
                if frame < agent.pure_move_until_frame or agent.shield_active(frame)
                else base_speed
            )
            agent.apply_movement(coll)
            agent.speed = base_speed

        if cur_mx != prev_move_x or cur_mz != prev_move_z:
            result.direction_changes += 1
        prev_move_x = cur_mx
        prev_move_z = cur_mz

        agent.record_frame()
        _schedule_enemy_attacks(agent, enemies, pending_hits, frame)
        agent.impact_force = max(0.0, agent.impact_force - config.impact_recovery_per_tick)
        prev_downed = agent.is_downed(frame)

        if scenario.safe_zone and not result.reached_safe:
            sx, sz = scenario.safe_zone
            dist = math.sqrt((agent.x - sx) ** 2 + (agent.z - sz) ** 2)
            if dist < safe_radius:
                result.reached_safe = True
                result.escape_frames = frame
                if nearest_dist > config.threat_scan_range:
                    break

    result.total_frames = frame + 4
    result.stuck_frames = agent.stuck_frames
    result.corner_events = agent.corner_events
    result.slide_events = agent.slide_events
    result.trajectory = agent.trajectory
    result.down_count = agent.down_count
    result.tough_break_count = agent.tough_break_count
    result.shield_uses = agent.shield_uses
    result.escape_skill_uses = agent.escape_skill_uses
    result.wakeup_guard_uses = agent.wakeup_guard_uses
    result.evaded_hits = agent.evaded_hits
    result.total_damage_taken = agent.total_damage_taken
    result.total_impact_taken = agent.total_impact_taken
    result.hp_remaining = max(0.0, agent.hp)
    result.hp_max = agent.hp_max
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
            if getattr(s, "mode", "") == "burst_survival":
                r = run_burst_survival_sim(
                    s, config, max_ticks,
                    wall_escape=wall_escape,
                    wall_escape_window=wall_escape_window)
            elif s.enemies:
                r = run_chase_sim(s, config, max_ticks,
                                  wall_escape=wall_escape,
                                  wall_escape_window=wall_escape_window)
            else:
                r = run_retreat_sim(s, config, max_ticks,
                                    wall_escape=wall_escape,
                                    wall_escape_window=wall_escape_window)
            results.append(r)
    return results
