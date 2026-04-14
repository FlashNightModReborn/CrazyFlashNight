"""
Combat movement agent state shared by the offline simulators.

The original tool started as a MovementResolver-only harness. This model now
also carries a lightweight survival runtime so we can tune the "burst
survival" loop without introducing a second simulator island.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional, Tuple

from shared import CollisionWorld


@dataclass
class MovementConfig:
    """Movement heuristics plus a minimal survival-tuning surface."""

    # MovementResolver parity
    margin: float = 80.0
    probe_min: float = 20.0
    probe_max: float = 60.0
    probe_speed_mult: float = 5.0
    no_progress_threshold: int = 2
    probe_fail_trigger: int = 3
    unstuck_base_window: int = 24
    unstuck_mid_window: int = 36
    unstuck_high_window: int = 48
    unstuck_mid_thresh: int = 6
    unstuck_high_thresh: int = 12
    pushout_radius: float = 120.0
    pushout_steps: int = 10
    pushout_angles: int = 45

    # Threat / engage surrogate
    threat_scan_range: float = 250.0
    nearby_enemy_range: float = 150.0
    encirclement_evade_threshold: float = 0.25
    pincer_side_advantage: int = 1
    edge_escape_margin: float = 80.0
    edge_safe_space: float = 60.0
    survival_gap_enemy_min: int = 3
    pressure_dominance_ratio: float = 1.15
    pack_escape_window: int = 20
    pack_escape_min_nearby: int = 1
    threat_sample_interval: int = 16
    kite_x_threshold: float = 180.0
    evade_nearby_count: int = 2
    strafe_pulse_min: int = 8
    strafe_pulse_max: int = 15
    strafe_gap_base: int = 12
    strafe_gap_min: int = 3

    # Burst survival heuristics
    burst_guard_hp_threshold: float = 0.45
    burst_guard_impact_ratio: float = 0.55
    burst_guard_nearby_enemies: int = 2
    burst_guard_recent_hit_frames: int = 16
    burst_guard_imminent_damage_ratio: float = 0.3
    overguard_imminent_damage_ratio: float = 0.85
    overguard_recast_gap_frames: int = 24
    shield_duration_frames: int = 20
    shield_cooldown_frames: int = 120
    shield_damage_mult: float = 0.45
    shield_impact_mult: float = 0.35
    impact_recovery_per_tick: float = 180.0
    down_recovery_frames: int = 24
    stagger_move_hold_frames: int = 12
    post_break_pure_move_frames: int = 24
    emergency_speed_mult: float = 1.15
    downed_damage_mult: float = 1.25
    escape_skill_hp_threshold: float = 0.6
    escape_skill_impact_ratio: float = 0.45
    escape_skill_nearby_enemies: int = 1
    escape_imminent_damage_ratio: float = 0.25
    escape_imminent_attackers: int = 2
    escape_single_imminent_damage_ratio: float = 0.8
    escape_single_imminent_hp_threshold: float = 0.35
    escape_dash_distance: float = 140.0
    escape_invuln_frames: int = 8
    escape_cooldown_frames: int = 120
    escape_impact_clear_ratio: float = 0.2
    escape_push_radius: float = 120.0
    escape_push_distance: float = 90.0
    escape_attack_delay_frames: int = 20
    wakeup_guard_invuln_frames: int = 12
    wakeup_guard_shield_frames: int = 24
    wakeup_guard_pure_move_frames: int = 32
    wakeup_guard_impact_clear_ratio: float = 0.0
    wakeup_guard_dash_distance: float = 100.0
    wakeup_guard_push_radius: float = 140.0
    wakeup_guard_push_distance: float = 110.0
    wakeup_guard_attack_delay_frames: int = 28
    combo_break_cancel_window_frames: int = 20
    combo_break_cancel_radius: float = 220.0


@dataclass
class CombatAgent:
    """Movement state plus the minimal runtime needed for survival tuning."""

    x: float
    z: float
    speed: float = 6.0
    config: MovementConfig = field(default_factory=MovementConfig)

    # Boundary state
    bnd_left: float = 0.0
    bnd_right: float = 0.0
    bnd_up: float = 0.0
    bnd_down: float = 0.0
    bnd_corner: float = 0.0

    # MovementResolver unstuck state
    unstuck_until_frame: int = 0
    unstuck_x: int = 0
    unstuck_z: int = 0
    no_progress_count: int = 0
    last_progress_x: Optional[float] = None
    last_progress_z: Optional[float] = None
    probe_fail_count: int = 0

    # Stuck probe state
    _pos_history: List[Tuple[float, float]] = field(default_factory=list)
    _stuck_check_count: int = 0

    # Movement output
    move_left: bool = False
    move_right: bool = False
    move_up: bool = False
    move_down: bool = False

    # Optional target hint
    target_x: Optional[float] = None
    target_z: Optional[float] = None

    # Statistics
    trajectory: List[Tuple[float, float]] = field(default_factory=list)
    stuck_frames: int = 0
    corner_events: int = 0
    slide_events: int = 0
    total_frames: int = 0

    # Survival runtime
    hp: float = 100.0
    hp_max: float = 100.0
    impact_force: float = 0.0
    impact_cap: float = 1800.0
    impact_stagger_boundary: float = 900.0
    alive: bool = True
    down_until_frame: int = 0
    pure_move_until_frame: int = 0
    shield_until_frame: int = 0
    shield_cooldown_until_frame: int = 0
    last_shield_frame: int = -10**9
    escape_invuln_until_frame: int = 0
    escape_cooldown_until_frame: int = 0
    last_hit_frame: int = -10**9
    last_hit_tag: str = ""
    total_damage_taken: float = 0.0
    total_impact_taken: float = 0.0
    tough_break_count: int = 0
    down_count: int = 0
    shield_uses: int = 0
    escape_skill_uses: int = 0
    wakeup_guard_uses: int = 0
    evaded_hits: int = 0

    def __post_init__(self) -> None:
        self.trajectory = [(self.x, self.z)]

    def update_boundaries(self, bounds: Tuple[float, float, float, float]) -> None:
        """Compute distance to each map edge and a coarse corner factor."""
        xmin, xmax, ymin, ymax = bounds
        self.bnd_left = self.x - xmin
        self.bnd_right = xmax - self.x
        self.bnd_up = self.z - ymin
        self.bnd_down = ymax - self.z

        margin = self.config.margin
        x_close = min(self.bnd_left, self.bnd_right) / margin
        z_close = min(self.bnd_up, self.bnd_down) / margin
        x_close = max(0.0, 1.0 - x_close)
        z_close = max(0.0, 1.0 - z_close)
        self.bnd_corner = x_close * z_close

    def stuck_probe(
        self,
        record: bool = True,
        tolerance: float = 6.0,
        threshold: int = 3,
        window: int = 4,
    ) -> bool:
        """Approximate UnitAIData.stuckProbeByCurrentPosition."""
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

    def clear_input(self) -> None:
        self.move_left = False
        self.move_right = False
        self.move_up = False
        self.move_down = False

    def apply_movement(self, coll: CollisionWorld, n_subframes: int = 4) -> None:
        """Apply one action tick worth of movement using axis-separated checks."""
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
        self.trajectory.append((self.x, self.z))
        self.total_frames += 4

    def is_downed(self, frame: int) -> bool:
        return frame < self.down_until_frame

    def shield_active(self, frame: int) -> bool:
        return frame < self.shield_until_frame

    def escape_active(self, frame: int) -> bool:
        return frame < self.escape_invuln_until_frame
