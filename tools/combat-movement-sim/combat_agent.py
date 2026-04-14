"""
战斗移动 Agent 数据模型 — 对应 AS2 的 UnitAIData + MovieClip 移动状态。

将 AS2 中分散在 UnitAIData / MovieClip / Mover 中的移动相关状态
收敛到一个纯 Python dataclass，供 MovementResolver 和仿真器使用。
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import List, Tuple, Optional

from shared import CollisionWorld


@dataclass
class MovementConfig:
    """MovementResolver 可调参数（对应 AS2 中的硬编码常量）。"""
    margin: float = 80.0             # 边界安全余量（AS2: MARGIN=80）
    probe_min: float = 20.0          # 最小探测距离
    probe_max: float = 60.0          # 最大探测距离
    probe_speed_mult: float = 5.0    # 当前 AS2 基线：probe = speed * 5
    no_progress_threshold: int = 2   # 当前 AS2 基线：_noProgressCount >= 2
    probe_fail_trigger: int = 3      # 探测全败触发 pushOut 的次数
    unstuck_base_window: int = 24    # 当前 AS2 基线：基础脱困窗口（帧）
    unstuck_mid_window: int = 36     # 当前 AS2 基线：中等卡死脱困窗口
    unstuck_high_window: int = 48    # 当前 AS2 基线：严重卡死脱困窗口
    unstuck_mid_thresh: int = 6      # 中等卡死阈值（stuckCheckCount）
    unstuck_high_thresh: int = 12    # 严重卡死阈值
    pushout_radius: float = 120.0    # pushOut 搜索半径
    pushout_steps: int = 10          # pushOut 径向步数
    pushout_angles: int = 45         # pushOut 角度数（每步几度间隔→360/angles）

    # ── 动态追逐 / 交战走位近似参数（ThreatAssessor + EngageMovementStrategy）──
    threat_scan_range: float = 250.0           # ThreatAssessor.scanRange
    nearby_enemy_range: float = 150.0          # ThreatAssessor.nearby 窗口
    encirclement_evade_threshold: float = 0.25 # 接近 EngageMovementStrategy 的包围压力启动线
    pincer_side_advantage: int = 1             # 左右敌人数差多少才判定“安全侧”
    edge_escape_margin: float = 80.0           # EngageMovementStrategy.edgeMargin
    edge_safe_space: float = 60.0              # safeX 可用空间门槛
    survival_gap_enemy_min: int = 3            # 多敌无安全区时启用缺口突围的最小敌人数
    pressure_dominance_ratio: float = 1.15     # 左右压力权重优势达到该比值才判定单侧更挤
    pack_escape_window: int = 20               # 多敌逃逸承诺窗口（帧）
    pack_escape_min_nearby: int = 1            # 触发多敌逃逸承诺的最小近距敌人数
    threat_sample_interval: int = 16           # ThreatAssessor 风格采样周期（帧）
    kite_x_threshold: float = 180.0            # EngageMovementStrategy 近似 X 风筝阈值
    evade_nearby_count: int = 2                # wantsEvade 的近距敌人数门槛
    strafe_pulse_min: int = 8                  # 蛇形走位脉冲最短持续
    strafe_pulse_max: int = 15                 # 蛇形走位脉冲最长持续
    strafe_gap_base: int = 12                  # 脉冲基础间歇
    strafe_gap_min: int = 3                    # 脉冲最短间歇


@dataclass
class CombatAgent:
    """一个战斗单位的移动状态。"""
    x: float
    z: float                         # 2.5D 的 Z 轴（对应 AS2 的 _y）
    speed: float = 6.0               # 每帧移动像素（AS2: 行走X速度）
    config: MovementConfig = field(default_factory=MovementConfig)

    # ── 边界距离（每 tick 由 update_boundaries 计算）──
    bnd_left: float = 0.0
    bnd_right: float = 0.0
    bnd_up: float = 0.0
    bnd_down: float = 0.0
    bnd_corner: float = 0.0          # 角落度 [0,1]

    # ── 脱困状态（对应 UnitAIData._unstuck*）──
    unstuck_until_frame: int = 0
    unstuck_x: int = 0
    unstuck_z: int = 0
    no_progress_count: int = 0
    last_progress_x: Optional[float] = None
    last_progress_z: Optional[float] = None
    probe_fail_count: int = 0

    # ── 卡死检测（对应 UnitAIData.stuckProbeByCurrentPosition）──
    _pos_history: List[Tuple[float, float]] = field(default_factory=list)
    _stuck_check_count: int = 0

    # ── 移动标志输出（对应 AS2 self.左行/右行/上行/下行）──
    move_left: bool = False
    move_right: bool = False
    move_up: bool = False
    move_down: bool = False

    # ── 目标信息 ──
    target_x: Optional[float] = None
    target_z: Optional[float] = None

    # ── 统计 ──
    trajectory: List[Tuple[float, float]] = field(default_factory=list)
    stuck_frames: int = 0            # 累计卡死帧数
    corner_events: int = 0           # 角落突围触发次数
    slide_events: int = 0            # 沿墙滑行触发次数
    total_frames: int = 0

    def __post_init__(self):
        self.trajectory = [(self.x, self.z)]

    # ═══════ 边界距离计算 ═══════

    def update_boundaries(self, bounds: Tuple[float, float, float, float]) -> None:
        """计算到地图四边的距离 + 角落度。"""
        xmin, xmax, ymin, ymax = bounds
        self.bnd_left = self.x - xmin
        self.bnd_right = xmax - self.x
        self.bnd_up = self.z - ymin
        self.bnd_down = ymax - self.z

        # 角落度：两轴中较小边界距离的归一化乘积
        margin = self.config.margin
        x_close = min(self.bnd_left, self.bnd_right) / margin
        z_close = min(self.bnd_up, self.bnd_down) / margin
        x_close = max(0.0, 1.0 - x_close)
        z_close = max(0.0, 1.0 - z_close)
        self.bnd_corner = x_close * z_close

    # ═══════ 卡死检测 ═══════

    def stuck_probe(self, record: bool = True,
                    tolerance: float = 6.0,
                    threshold: int = 3,
                    window: int = 4) -> bool:
        """
        对应 UnitAIData.stuckProbeByCurrentPosition。
        检查最近 window 帧内位移是否低于 tolerance。
        """
        if record:
            self._pos_history.append((self.x, self.z))
            if len(self._pos_history) > window + 1:
                self._pos_history = self._pos_history[-(window + 1):]

        if len(self._pos_history) < 2:
            return False

        stuck_count = 0
        for i in range(1, len(self._pos_history)):
            dx = abs(self._pos_history[i][0] - self._pos_history[i - 1][0])
            dz = abs(self._pos_history[i][1] - self._pos_history[i - 1][1])
            if dx < tolerance and dz < tolerance:
                stuck_count += 1

        is_stuck = stuck_count >= threshold
        if is_stuck:
            self._stuck_check_count += 1
        return is_stuck

    def get_stuck_check_count(self) -> int:
        return self._stuck_check_count

    # ═══════ 移动标志清除 ═══════

    def clear_input(self) -> None:
        self.move_left = False
        self.move_right = False
        self.move_up = False
        self.move_down = False

    # ═══════ 移动执行（4 子帧独立轴）═══════

    def apply_movement(self, coll: CollisionWorld, n_subframes: int = 4) -> None:
        """执行一个 action tick 的移动（4 子帧，每帧独立轴碰撞检测）。"""
        spd = self.speed
        dx = 0.0
        dz = 0.0
        if self.move_left:
            dx = -spd
        elif self.move_right:
            dx = spd
        if self.move_up:
            dz = -spd
        elif self.move_down:
            dz = spd

        for _ in range(n_subframes):
            if dx != 0:
                nx = self.x + dx
                if coll.is_point_valid(nx, self.z):
                    self.x = nx
            if dz != 0:
                nz = self.z + dz
                if coll.is_point_valid(self.x, nz):
                    self.z = nz

    def record_frame(self) -> None:
        """记录当前位置到轨迹。"""
        self.trajectory.append((self.x, self.z))
        self.total_frames += 4  # 每 action = 4 帧
