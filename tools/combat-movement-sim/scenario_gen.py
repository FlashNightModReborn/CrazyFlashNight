"""
Scenario generation for the combat movement / burst survival offline harness.

The same scenario module feeds three simulator modes:
  - retreat:   static enemy + safe-zone escape
  - chase:     moving enemies + movement-only survival
  - burst_survival: moving enemies + impact/down/death approximation
"""
from __future__ import annotations

from dataclasses import dataclass
import random
from typing import Callable, List, Optional, Tuple

from shapely.geometry import box as shapely_box

from shared import MapData


@dataclass
class EnemyConfig:
    """Enemy spawn plus a single simplified attack profile."""

    x: float
    z: float
    speed: float = 3.0
    chase_range: float = 999.0
    attack_range: float = 0.0
    attack_damage: float = 0.0
    attack_impact: float = 0.0
    attack_cooldown_frames: int = 24
    attack_windup_frames: int = 4
    attack_tag: str = "hit"


@dataclass
class CombatScenario:
    """One offline combat scenario."""

    name: str
    map_data: MapData
    agent_start: Tuple[float, float]
    enemy_pos: Tuple[float, float]
    safe_zone: Optional[Tuple[float, float]] = None
    description: str = ""
    enemies: Optional[List[EnemyConfig]] = None
    enemy_speed: float = 3.0
    mode: str = "retreat"
    survival_ticks: int = 220
    agent_hp: float = 100.0
    agent_speed: float = 6.0
    agent_impact_cap: float = 1800.0
    agent_stagger_boundary: float = 900.0
    initial_down_frames: int = 0


def _make_map(name: str, bounds, collisions, width: int = 1200, height: int = 600) -> MapData:
    return MapData(
        name=name,
        bounds=bounds,
        width=width,
        height=height,
        collisions=collisions,
        doors=[],
    )


def corner_trap_left() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    thickness = 60
    wall_h = shapely_box(xmin - 10, ymax - 150, xmin + 250, ymax - 150 + thickness)
    wall_v = shapely_box(xmin + 250 - thickness, ymax - 60, xmin + 250, ymax + 10)
    return CombatScenario(
        name="corner_trap_left",
        mode="retreat",
        map_data=_make_map("corner_trap_left", (xmin, xmax, ymin, ymax), [wall_h, wall_v]),
        agent_start=(xmin + 80, ymax - 60),
        enemy_pos=(xmin + 300, ymax - 200),
        safe_zone=(xmax - 100, (ymin + ymax) / 2),
        description="Left-bottom L trap forcing corner escape.",
    )


def corner_trap_right() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    thickness = 60
    wall_h = shapely_box(xmax - 250, ymin + 90, xmax + 10, ymin + 90 + thickness)
    wall_v = shapely_box(xmax - 250, ymin - 10, xmax - 250 + thickness, ymin + 60)
    return CombatScenario(
        name="corner_trap_right",
        mode="retreat",
        map_data=_make_map("corner_trap_right", (xmin, xmax, ymin, ymax), [wall_h, wall_v]),
        agent_start=(xmax - 80, ymin + 40),
        enemy_pos=(xmax - 300, ymin + 200),
        safe_zone=(xmin + 100, (ymin + ymax) / 2),
        description="Right-top mirrored L trap.",
    )


def wall_slide_long() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    obs = shapely_box(500, ymax - 120, 700, ymax + 10)
    return CombatScenario(
        name="wall_slide_long",
        mode="retreat",
        map_data=_make_map("wall_slide_long", (xmin, xmax, ymin, ymax), [obs]),
        agent_start=(xmin + 80, ymax - 40),
        enemy_pos=(xmin + 200, ymax - 100),
        safe_zone=(xmax - 80, ymax - 40),
        description="Long bottom-edge slide with a blocking obstacle.",
    )


def narrow_corridor_retreat() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cy = (ymin + ymax) / 2
    passage = 80
    thickness = 60
    wall_top = shapely_box(200, cy - passage / 2 - thickness, 900, cy - passage / 2)
    wall_bot = shapely_box(200, cy + passage / 2, 900, cy + passage / 2 + thickness)
    return CombatScenario(
        name="narrow_corridor",
        mode="retreat",
        map_data=_make_map("narrow_corridor", (xmin, xmax, ymin, ymax), [wall_top, wall_bot]),
        agent_start=(800, cy),
        enemy_pos=(300, cy),
        safe_zone=(xmax - 80, cy),
        description="Narrow corridor retreat with constrained Z movement.",
    )


def u_trap_retreat() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cx, cy = 600, 350
    u_w, u_h, thickness = 300, 200, 60
    left = shapely_box(cx - u_w / 2, cy - u_h / 2, cx - u_w / 2 + thickness, cy + u_h / 2)
    bottom = shapely_box(cx - u_w / 2, cy + u_h / 2 - thickness, cx + u_w / 2, cy + u_h / 2)
    right = shapely_box(cx + u_w / 2 - thickness, cy - u_h / 2, cx + u_w / 2, cy + u_h / 2)
    return CombatScenario(
        name="u_trap",
        mode="retreat",
        map_data=_make_map("u_trap", (xmin, xmax, ymin, ymax), [left, bottom, right]),
        agent_start=(cx, cy + u_h / 2 - 80),
        enemy_pos=(cx, cy - u_h / 2 - 80),
        safe_zone=(xmin + 80, cy),
        description="U-trap retreat through the open mouth.",
    )


def l_shape_chase() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    thickness = 60
    h_wall = shapely_box(400, 300, 800, 300 + thickness)
    v_wall = shapely_box(800 - thickness, 300, 800, 510)
    return CombatScenario(
        name="l_shape_chase",
        mode="retreat",
        map_data=_make_map("l_shape_chase", (xmin, xmax, ymin, ymax), [h_wall, v_wall]),
        agent_start=(700, 400),
        enemy_pos=(500, 250),
        safe_zone=(xmin + 80, ymax - 40),
        description="L-shaped obstacle forcing wrap-around retreat.",
    )


def multi_obstacle() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    collisions = [
        shapely_box(200, 220, 320, 320),
        shapely_box(450, 350, 550, 480),
        shapely_box(650, 200, 780, 300),
        shapely_box(900, 380, 1020, 490),
        shapely_box(350, 420, 420, 510),
    ]
    return CombatScenario(
        name="multi_obstacle",
        mode="retreat",
        map_data=_make_map("multi_obstacle", (xmin, xmax, ymin, ymax), collisions),
        agent_start=(100, 350),
        enemy_pos=(1050, 350),
        safe_zone=(xmin + 80, ymin + 40),
        description="Multi-obstacle pathing and repeated unstuck pressure.",
    )


def edge_push() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    obs = shapely_box(1000, 250, 1150, 450)
    return CombatScenario(
        name="edge_push",
        mode="retreat",
        map_data=_make_map("edge_push", (xmin, xmax, ymin, ymax), [obs]),
        agent_start=(1050, 230),
        enemy_pos=(900, 350),
        safe_zone=(xmin + 100, (ymin + ymax) / 2),
        description="Right-edge squeeze testing edge escape.",
    )


def open_field() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    return CombatScenario(
        name="open_field",
        mode="retreat",
        map_data=_make_map("open_field", (xmin, xmax, ymin, ymax), []),
        agent_start=(600, 350),
        enemy_pos=(400, 350),
        safe_zone=(xmax - 80, 350),
        description="Open-field retreat baseline.",
    )


def chase_pack_open() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cx, cz = 600, 350
    return CombatScenario(
        name="chase_pack_open",
        mode="chase",
        map_data=_make_map("chase_pack_open", (xmin, xmax, ymin, ymax), []),
        agent_start=(cx, cz),
        enemy_pos=(cx - 200, cz),
        safe_zone=(xmax - 80, cz),
        description="Open-field 5-enemy chase.",
        enemies=[
            EnemyConfig(cx - 200, cz, speed=3.0),
            EnemyConfig(cx - 150, cz - 100, speed=2.5),
            EnemyConfig(cx - 150, cz + 100, speed=2.5),
            EnemyConfig(cx + 100, cz - 120, speed=3.0),
            EnemyConfig(cx + 100, cz + 120, speed=3.0),
        ],
    )


def chase_pack_corridor() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cy = (ymin + ymax) / 2
    thickness = 60
    passage = 100
    wall_top = shapely_box(150, cy - passage / 2 - thickness, 1000, cy - passage / 2)
    wall_bot = shapely_box(150, cy + passage / 2, 1000, cy + passage / 2 + thickness)
    return CombatScenario(
        name="chase_pack_corridor",
        mode="chase",
        map_data=_make_map("chase_pack_corridor", (xmin, xmax, ymin, ymax), [wall_top, wall_bot]),
        agent_start=(700, cy),
        enemy_pos=(400, cy),
        safe_zone=(xmax - 80, cy),
        description="3-enemy corridor chase.",
        enemies=[
            EnemyConfig(400, cy, speed=3.0),
            EnemyConfig(500, cy - 30, speed=2.5),
            EnemyConfig(500, cy + 30, speed=2.5),
        ],
    )


def chase_pack_corner() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    return CombatScenario(
        name="chase_pack_corner",
        mode="chase",
        map_data=_make_map("chase_pack_corner", (xmin, xmax, ymin, ymax), []),
        agent_start=(200, 420),
        enemy_pos=(400, 350),
        safe_zone=(xmax - 80, (ymin + ymax) / 2),
        description="Corner squeeze under 4-enemy chase pressure.",
        enemies=[
            EnemyConfig(400, 350, speed=3.0),
            EnemyConfig(350, 450, speed=2.5),
            EnemyConfig(250, 250, speed=3.0),
            EnemyConfig(500, 400, speed=2.0),
        ],
    )


def chase_pack_obstacles() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    collisions = [
        shapely_box(300, 250, 420, 350),
        shapely_box(550, 380, 670, 490),
        shapely_box(800, 220, 920, 320),
    ]
    return CombatScenario(
        name="chase_pack_obstacles",
        mode="chase",
        map_data=_make_map("chase_pack_obstacles", (xmin, xmax, ymin, ymax), collisions),
        agent_start=(500, 350),
        enemy_pos=(300, 350),
        safe_zone=(xmax - 80, 250),
        description="4-enemy chase around blocking obstacles.",
        enemies=[
            EnemyConfig(300, 350, speed=3.0),
            EnemyConfig(350, 250, speed=2.5),
            EnemyConfig(350, 450, speed=2.5),
            EnemyConfig(600, 300, speed=2.0),
        ],
    )


def chase_pincer_lane() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cy = (ymin + ymax) / 2
    return CombatScenario(
        name="chase_pincer_lane",
        mode="chase",
        map_data=_make_map("chase_pincer_lane", (xmin, xmax, ymin, ymax), []),
        agent_start=(580, cy),
        enemy_pos=(520, cy),
        safe_zone=(xmin + 90, cy),
        description="Nearest enemy on the left, but right-side pack dominates.",
        enemies=[
            EnemyConfig(520, cy, speed=3.0),
            EnemyConfig(720, cy - 60, speed=3.0),
            EnemyConfig(720, cy + 60, speed=3.0),
            EnemyConfig(860, cy, speed=2.5),
        ],
    )


def chase_edge_reentry() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cy = (ymin + ymax) / 2
    return CombatScenario(
        name="chase_edge_reentry",
        mode="chase",
        map_data=_make_map("chase_edge_reentry", (xmin, xmax, ymin, ymax), []),
        agent_start=(xmin + 55, cy - 10),
        enemy_pos=(xmin + 170, cy - 10),
        safe_zone=(xmax - 80, cy),
        description="Left-edge spawn, forced to re-enter before retreating out.",
        enemies=[
            EnemyConfig(xmin + 170, cy - 10, speed=3.0),
            EnemyConfig(xmin + 230, cy - 80, speed=2.8),
            EnemyConfig(xmin + 230, cy + 60, speed=2.8),
            EnemyConfig(xmin + 330, cy - 10, speed=2.5),
        ],
    )


def chase_swarm() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cx, cz = 600, 350
    enemies: List[EnemyConfig] = []
    import math

    for idx in range(8):
        angle = idx * math.pi / 4
        ex = cx + 250 * math.cos(angle)
        ez = cz + 120 * math.sin(angle)
        enemies.append(EnemyConfig(ex, ez, speed=2.0))

    return CombatScenario(
        name="chase_swarm",
        mode="chase",
        map_data=_make_map("chase_swarm", (xmin, xmax, ymin, ymax), []),
        agent_start=(cx, cz),
        enemy_pos=(cx - 250, cz),
        safe_zone=None,
        description="8-enemy survival swarm without a safe zone.",
        enemies=enemies,
    )


def burst_elite_combo() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cy = (ymin + ymax) / 2
    return CombatScenario(
        name="burst_elite_combo",
        mode="burst_survival",
        map_data=_make_map("burst_elite_combo", (xmin, xmax, ymin, ymax), []),
        agent_start=(360, cy),
        enemy_pos=(520, cy),
        safe_zone=(xmax - 90, cy),
        description="One heavy melee breaker plus one ranged finisher.",
        survival_ticks=220,
        enemies=[
            EnemyConfig(
                520, cy, speed=3.1,
                attack_range=72, attack_damage=28, attack_impact=2600,
                attack_cooldown_frames=28, attack_windup_frames=4,
                attack_tag="elite_cleave",
            ),
            EnemyConfig(
                700, cy - 18, speed=2.6,
                attack_range=320, attack_damage=24, attack_impact=380,
                attack_cooldown_frames=20, attack_windup_frames=4,
                attack_tag="finisher_shot",
            ),
        ],
    )


def burst_edge_pin_combo() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cy = (ymin + ymax) / 2
    return CombatScenario(
        name="burst_edge_pin_combo",
        mode="burst_survival",
        map_data=_make_map("burst_edge_pin_combo", (xmin, xmax, ymin, ymax), []),
        agent_start=(xmin + 70, cy + 15),
        enemy_pos=(xmin + 170, cy),
        safe_zone=(xmax - 90, cy),
        description="Edge-pinned target facing a melee breaker and close follow-up.",
        survival_ticks=220,
        enemies=[
            EnemyConfig(
                xmin + 170, cy, speed=3.0,
                attack_range=68, attack_damage=22, attack_impact=2800,
                attack_cooldown_frames=28, attack_windup_frames=4,
                attack_tag="edge_breaker",
            ),
            EnemyConfig(
                xmin + 250, cy - 70, speed=2.8,
                attack_range=280, attack_damage=22, attack_impact=320,
                attack_cooldown_frames=18, attack_windup_frames=4,
                attack_tag="close_shot",
            ),
            EnemyConfig(
                xmin + 250, cy + 65, speed=2.8,
                attack_range=72, attack_damage=14, attack_impact=2800,
                attack_cooldown_frames=24, attack_windup_frames=4,
                attack_tag="edge_hook",
            ),
        ],
    )


def burst_retreat_crossfire() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cy = (ymin + ymax) / 2
    return CombatScenario(
        name="burst_retreat_crossfire",
        mode="burst_survival",
        map_data=_make_map("burst_retreat_crossfire", (xmin, xmax, ymin, ymax), []),
        agent_start=(760, cy),
        enemy_pos=(560, cy),
        safe_zone=(xmax - 80, cy),
        description="Retreating target gets clipped by melee on one side and ranged crossfire.",
        survival_ticks=240,
        enemies=[
            EnemyConfig(
                560, cy, speed=3.0,
                attack_range=70, attack_damage=22, attack_impact=2100,
                attack_cooldown_frames=24, attack_windup_frames=4,
                attack_tag="gap_bash",
            ),
            EnemyConfig(
                620, cy - 95, speed=2.4,
                attack_range=340, attack_damage=18, attack_impact=260,
                attack_cooldown_frames=16, attack_windup_frames=4,
                attack_tag="upper_fire",
            ),
            EnemyConfig(
                690, cy + 100, speed=2.4,
                attack_range=340, attack_damage=18, attack_impact=260,
                attack_cooldown_frames=16, attack_windup_frames=4,
                attack_tag="lower_fire",
            ),
        ],
    )


def burst_post_down_recovery() -> CombatScenario:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cy = (ymin + ymax) / 2
    return CombatScenario(
        name="burst_post_down_recovery",
        mode="burst_survival",
        map_data=_make_map("burst_post_down_recovery", (xmin, xmax, ymin, ymax), []),
        agent_start=(420, cy + 5),
        enemy_pos=(520, cy),
        safe_zone=(xmax - 90, cy),
        description="Target survives first break, then must live through wake-up chase.",
        survival_ticks=240,
        enemies=[
            EnemyConfig(
                520, cy, speed=3.0,
                attack_range=70, attack_damage=20, attack_impact=3200,
                attack_cooldown_frames=32, attack_windup_frames=4,
                attack_tag="launcher",
            ),
            EnemyConfig(
                650, cy + 12, speed=3.0,
                attack_range=90, attack_damage=14, attack_impact=2400,
                attack_cooldown_frames=20, attack_windup_frames=4,
                attack_tag="wake_chaser",
            ),
            EnemyConfig(
                760, cy - 24, speed=2.5,
                attack_range=320, attack_damage=21, attack_impact=320,
                attack_cooldown_frames=18, attack_windup_frames=4,
                attack_tag="wake_shot",
            ),
        ],
    )


def get_burst_elite_variant_scenarios(
    count: int = 24,
    seed: int = 1337,
) -> List[CombatScenario]:
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cy = (ymin + ymax) / 2
    rng = random.Random(seed)
    scenarios: List[CombatScenario] = []

    for idx in range(count):
        agent_x = 340 + rng.uniform(-40, 60)
        agent_z = cy + rng.uniform(-18, 18)

        elite_gap = rng.uniform(135, 220)
        elite_x = min(xmax - 280, agent_x + elite_gap)
        elite_z = cy + rng.uniform(-26, 26)

        shooter_gap = rng.uniform(120, 250)
        shooter_x = min(xmax - 110, elite_x + shooter_gap)
        shooter_z = cy + rng.uniform(-64, 64)

        elite_speed = 2.8 + rng.uniform(0.0, 0.7)
        elite_range = 68 + rng.uniform(-4, 8)
        elite_damage = 26 + rng.uniform(-4, 8)
        elite_impact = 2400 + rng.uniform(-250, 750)
        elite_cooldown = rng.choice([24, 28, 32])
        elite_windup = rng.choice([4, 8])

        shot_speed = 2.3 + rng.uniform(0.0, 0.6)
        shot_range = 300 + rng.uniform(-30, 50)
        shot_damage = 21 + rng.uniform(-3, 7)
        shot_impact = 320 + rng.uniform(-40, 140)
        shot_cooldown = rng.choice([16, 20, 24])
        shot_windup = rng.choice([4, 8, 12])

        survival_ticks = rng.choice([220, 240, 260])
        safe_zone_x = xmax - 90 - rng.uniform(0, 30)
        scenario_name = f"burst_elite_variant_{idx + 1:02d}"
        description = (
            f"Elite variant {idx + 1}: "
            f"gap={elite_gap:.0f}, shooter_gap={shooter_gap:.0f}, "
            f"cleave_cd={elite_cooldown}, shot_cd={shot_cooldown}"
        )

        scenarios.append(
            CombatScenario(
                name=scenario_name,
                mode="burst_survival",
                map_data=_make_map(scenario_name, (xmin, xmax, ymin, ymax), []),
                agent_start=(agent_x, agent_z),
                enemy_pos=(elite_x, elite_z),
                safe_zone=(safe_zone_x, cy),
                description=description,
                survival_ticks=survival_ticks,
                enemies=[
                    EnemyConfig(
                        elite_x,
                        elite_z,
                        speed=elite_speed,
                        attack_range=elite_range,
                        attack_damage=elite_damage,
                        attack_impact=elite_impact,
                        attack_cooldown_frames=elite_cooldown,
                        attack_windup_frames=elite_windup,
                        attack_tag="elite_cleave",
                    ),
                    EnemyConfig(
                        shooter_x,
                        shooter_z,
                        speed=shot_speed,
                        attack_range=shot_range,
                        attack_damage=shot_damage,
                        attack_impact=shot_impact,
                        attack_cooldown_frames=shot_cooldown,
                        attack_windup_frames=shot_windup,
                        attack_tag="finisher_shot",
                    ),
                ],
            )
        )

    return scenarios


ALL_SCENARIOS: List[Callable[[], CombatScenario]] = [
    open_field,
    corner_trap_left,
    corner_trap_right,
    wall_slide_long,
    narrow_corridor_retreat,
    u_trap_retreat,
    l_shape_chase,
    multi_obstacle,
    edge_push,
]

CHASE_SCENARIOS: List[Callable[[], CombatScenario]] = [
    chase_pack_open,
    chase_pack_corridor,
    chase_pack_corner,
    chase_pack_obstacles,
    chase_pincer_lane,
    chase_edge_reentry,
    chase_swarm,
]

SURVIVAL_SCENARIOS: List[Callable[[], CombatScenario]] = [
    burst_elite_combo,
    burst_edge_pin_combo,
    burst_retreat_crossfire,
    burst_post_down_recovery,
]


def get_all_scenarios() -> List[CombatScenario]:
    return [factory() for factory in ALL_SCENARIOS]


def get_chase_scenarios() -> List[CombatScenario]:
    return [factory() for factory in CHASE_SCENARIOS]


def get_burst_scenarios() -> List[CombatScenario]:
    return [factory() for factory in SURVIVAL_SCENARIOS]


def get_scenario_by_name(name: str) -> CombatScenario:
    for factory in ALL_SCENARIOS + CHASE_SCENARIOS + SURVIVAL_SCENARIOS:
        scenario = factory()
        if scenario.name == name:
            return scenario
    for scenario in get_burst_elite_variant_scenarios():
        if scenario.name == name:
            return scenario
    raise ValueError(f"Unknown scenario: {name}")
