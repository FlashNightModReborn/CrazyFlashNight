"""
战斗移动对抗场景生成器 — 专门设计击败 MovementResolver 的场景。

每个场景包含：
  - 地图（碰撞体 + 边界）
  - 出生点（agent 初始位置）
  - 目标位置（追击者/安全区域）
  - 预期行为（agent 应该撤退到的位置）

场景重点覆盖 MovementResolver 的薄弱环节：
  - 墙角陷阱（三面封闭，被堵口）
  - 贴边长距离滑行
  - L形/U形拐角追逐
  - 狭窄通道对冲
  - 多障碍物迷宫
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Tuple
from shapely.geometry import box as shapely_box
from shapely.ops import unary_union

from shared import MapData


@dataclass
class EnemyConfig:
    """一个追逐敌人的配置。"""
    x: float
    z: float
    speed: float = 3.0       # 每帧移动像素（慢于 agent 的 6.0）
    chase_range: float = 999  # 追逐范围（超出则不追）

@dataclass
class CombatScenario:
    """一个战斗移动测试场景。"""
    name: str
    map_data: MapData
    agent_start: Tuple[float, float]      # (x, z)
    enemy_pos: Tuple[float, float]        # 主追击者位置（向后兼容）
    safe_zone: Tuple[float, float] = None # 安全区域（可选，评估是否到达）
    description: str = ""
    enemies: List[EnemyConfig] = None     # 多敌人列表（None=使用 enemy_pos 单敌人）
    enemy_speed: float = 3.0              # 默认敌人速度（enemies 为 None 时用）


def _make_map(name: str, bounds, collisions, width=1200, height=600):
    return MapData(
        name=name, bounds=bounds,
        width=width, height=height,
        collisions=collisions, doors=[])


# ═══════ 场景生成函数 ═══════

def corner_trap_left() -> CombatScenario:
    """左下角陷阱：agent 被压到左下角，敌人堵住唯一出口。"""
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    t = 60
    # L 形墙 + 右侧窄出口
    wall_h = shapely_box(xmin - 10, ymax - 150, xmin + 250, ymax - 150 + t)
    wall_v = shapely_box(xmin + 250 - t, ymax - 60, xmin + 250, ymax + 10)
    collisions = [wall_h, wall_v]

    return CombatScenario(
        name="corner_trap_left",
        map_data=_make_map("corner_trap_left", (xmin, xmax, ymin, ymax), collisions),
        agent_start=(xmin + 80, ymax - 60),   # 角落里
        enemy_pos=(xmin + 300, ymax - 200),    # 堵住出口
        safe_zone=(xmax - 100, (ymin + ymax) / 2),
        description="左下角 L 形墙陷阱，测试角落脱困 + edgeEscape",
    )


def corner_trap_right() -> CombatScenario:
    """右上角陷阱：对称版本。"""
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    t = 60
    wall_h = shapely_box(xmax - 250, ymin + 90, xmax + 10, ymin + 90 + t)
    wall_v = shapely_box(xmax - 250, ymin - 10, xmax - 250 + t, ymin + 60)
    collisions = [wall_h, wall_v]

    return CombatScenario(
        name="corner_trap_right",
        map_data=_make_map("corner_trap_right", (xmin, xmax, ymin, ymax), collisions),
        agent_start=(xmax - 80, ymin + 40),
        enemy_pos=(xmax - 300, ymin + 200),
        safe_zone=(xmin + 100, (ymin + ymax) / 2),
        description="右上角 L 形墙陷阱",
    )


def wall_slide_long() -> CombatScenario:
    """长距离贴边滑行：agent 在地图底边被追，需要沿底边滑行到另一端。"""
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    # 底部中间有障碍物，迫使 agent 绕行
    obs = shapely_box(500, ymax - 120, 700, ymax + 10)
    collisions = [obs]

    return CombatScenario(
        name="wall_slide_long",
        map_data=_make_map("wall_slide_long", (xmin, xmax, ymin, ymax), collisions),
        agent_start=(xmin + 80, ymax - 40),
        enemy_pos=(xmin + 200, ymax - 100),
        safe_zone=(xmax - 80, ymax - 40),
        description="底边长距离滑行 + 中间障碍物绕行",
    )


def narrow_corridor_retreat() -> CombatScenario:
    """狭窄通道撤退：两道平行墙形成窄通道，agent 在通道内被追。"""
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cy = (ymin + ymax) / 2
    passage = 80
    t = 60
    wall_top = shapely_box(200, cy - passage / 2 - t, 900, cy - passage / 2)
    wall_bot = shapely_box(200, cy + passage / 2, 900, cy + passage / 2 + t)
    collisions = [wall_top, wall_bot]

    return CombatScenario(
        name="narrow_corridor",
        map_data=_make_map("narrow_corridor", (xmin, xmax, ymin, ymax), collisions),
        agent_start=(800, cy),
        enemy_pos=(300, cy),
        safe_zone=(xmax - 80, cy),
        description="窄通道内被追，测试 Z 轴受限时的 X 轴撤退",
    )


def u_trap_retreat() -> CombatScenario:
    """U 形陷阱撤退：agent 在 U 形内，需要从开口方向逃出。"""
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cx, cy = 600, 350
    u_w, u_h, t = 300, 200, 60
    left = shapely_box(cx - u_w / 2, cy - u_h / 2, cx - u_w / 2 + t, cy + u_h / 2)
    bottom = shapely_box(cx - u_w / 2, cy + u_h / 2 - t, cx + u_w / 2, cy + u_h / 2)
    right = shapely_box(cx + u_w / 2 - t, cy - u_h / 2, cx + u_w / 2, cy + u_h / 2)
    collisions = [left, bottom, right]

    return CombatScenario(
        name="u_trap",
        map_data=_make_map("u_trap", (xmin, xmax, ymin, ymax), collisions),
        agent_start=(cx, cy + u_h / 2 - 80),     # U 形底部
        enemy_pos=(cx, cy - u_h / 2 - 80),         # U 形外上方
        safe_zone=(xmin + 80, cy),
        description="U 形陷阱，agent 需从开口逃出（开口朝上）",
    )


def l_shape_chase() -> CombatScenario:
    """L 形拐角追逐：agent 需要绕过 L 形墙。"""
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    t = 60
    # L 形：横墙 + 垂直墙
    h_wall = shapely_box(400, 300, 800, 300 + t)
    v_wall = shapely_box(800 - t, 300, 800, 510)
    collisions = [h_wall, v_wall]

    return CombatScenario(
        name="l_shape_chase",
        map_data=_make_map("l_shape_chase", (xmin, xmax, ymin, ymax), collisions),
        agent_start=(700, 400),
        enemy_pos=(500, 250),
        safe_zone=(xmin + 80, ymax - 40),
        description="L 形墙拐角追逐，测试绕障碍物能力",
    )


def multi_obstacle() -> CombatScenario:
    """多障碍物迷宫：散布多个障碍物，测试连续脱困能力。"""
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
        map_data=_make_map("multi_obstacle", (xmin, xmax, ymin, ymax), collisions),
        agent_start=(100, 350),
        enemy_pos=(1050, 350),
        safe_zone=(xmin + 80, ymin + 40),
        description="多障碍物环境，测试连续绕障和方向切换",
    )


def edge_push() -> CombatScenario:
    """边缘推挤：agent 被压到右边界，需要沿边反向撤退。"""
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    # 右侧有个大障碍缩小有效空间
    obs = shapely_box(1000, 250, 1150, 450)
    collisions = [obs]

    return CombatScenario(
        name="edge_push",
        map_data=_make_map("edge_push", (xmin, xmax, ymin, ymax), collisions),
        agent_start=(1050, 230),      # 障碍物上方窄缝
        enemy_pos=(900, 350),
        safe_zone=(xmin + 100, (ymin + ymax) / 2),
        description="右边界障碍物窄缝，测试 edgeEscape + 反向撤退",
    )


def open_field() -> CombatScenario:
    """开阔地形基准：无障碍物，纯撤退。用于对照。"""
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    return CombatScenario(
        name="open_field",
        map_data=_make_map("open_field", (xmin, xmax, ymin, ymax), []),
        agent_start=(600, 350),
        enemy_pos=(400, 350),
        safe_zone=(xmax - 80, 350),
        description="开阔地形基准测试（无障碍物）",
    )


# ═══════ 多敌人追逐场景 ═══════

def chase_pack_open() -> CombatScenario:
    """开阔地形 5 敌追逐：慢速敌人从四面八方包围。"""
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cx, cz = 600, 350
    return CombatScenario(
        name="chase_pack_open",
        map_data=_make_map("chase_pack_open", (xmin, xmax, ymin, ymax), []),
        agent_start=(cx, cz),
        enemy_pos=(cx - 200, cz),  # 主参考敌人（兼容旧接口）
        safe_zone=(xmax - 80, cz),
        description="开阔地形 5 敌追逐（速度 3.0，agent 速度 6.0）",
        enemies=[
            EnemyConfig(cx - 200, cz, speed=3.0),       # 正左
            EnemyConfig(cx - 150, cz - 100, speed=2.5),  # 左上
            EnemyConfig(cx - 150, cz + 100, speed=2.5),  # 左下
            EnemyConfig(cx + 100, cz - 120, speed=3.0),  # 右上（包抄）
            EnemyConfig(cx + 100, cz + 120, speed=3.0),  # 右下（包抄）
        ],
    )


def chase_pack_corridor() -> CombatScenario:
    """走廊内 3 敌追逐：在窄通道里被多个敌人堵截。"""
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cy = (ymin + ymax) / 2
    t = 60
    passage = 100
    wall_top = shapely_box(150, cy - passage / 2 - t, 1000, cy - passage / 2)
    wall_bot = shapely_box(150, cy + passage / 2, 1000, cy + passage / 2 + t)
    collisions = [wall_top, wall_bot]

    return CombatScenario(
        name="chase_pack_corridor",
        map_data=_make_map("chase_pack_corridor", (xmin, xmax, ymin, ymax), collisions),
        agent_start=(700, cy),
        enemy_pos=(400, cy),
        safe_zone=(xmax - 80, cy),
        description="走廊 3 敌追逐，测试窄空间多敌应对",
        enemies=[
            EnemyConfig(400, cy, speed=3.0),         # 正后方
            EnemyConfig(500, cy - 30, speed=2.5),    # 偏上追
            EnemyConfig(500, cy + 30, speed=2.5),    # 偏下追
        ],
    )


def chase_pack_corner() -> CombatScenario:
    """角落 4 敌追逐：agent 被逼向左下角，敌人从右侧和上方逼近。"""
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510

    return CombatScenario(
        name="chase_pack_corner",
        map_data=_make_map("chase_pack_corner", (xmin, xmax, ymin, ymax), []),
        agent_start=(200, 420),
        enemy_pos=(400, 350),
        safe_zone=(xmax - 80, (ymin + ymax) / 2),
        description="角落 4 敌追逐，测试边界逃脱承诺窗口在多敌下的表现",
        enemies=[
            EnemyConfig(400, 350, speed=3.0),    # 右上
            EnemyConfig(350, 450, speed=2.5),    # 右侧同高
            EnemyConfig(250, 250, speed=3.0),    # 正上方
            EnemyConfig(500, 400, speed=2.0),    # 远处包抄
        ],
    )


def chase_pack_obstacles() -> CombatScenario:
    """障碍物环境 4 敌追逐：散布障碍物的地图中被追。"""
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    collisions = [
        shapely_box(300, 250, 420, 350),
        shapely_box(550, 380, 670, 490),
        shapely_box(800, 220, 920, 320),
    ]

    return CombatScenario(
        name="chase_pack_obstacles",
        map_data=_make_map("chase_pack_obstacles", (xmin, xmax, ymin, ymax), collisions),
        agent_start=(500, 350),
        enemy_pos=(300, 350),
        safe_zone=(xmax - 80, 250),
        description="障碍物环境 4 敌追逐，测试绕障 + 多敌应对",
        enemies=[
            EnemyConfig(300, 350, speed=3.0),
            EnemyConfig(350, 250, speed=2.5),
            EnemyConfig(350, 450, speed=2.5),
            EnemyConfig(600, 300, speed=2.0),   # 侧面拦截
        ],
    )


def chase_swarm() -> CombatScenario:
    """蜂群追逐：8 个极慢敌人全方位包围，测试生存能力。"""
    xmin, xmax, ymin, ymax = 50, 1150, 180, 510
    cx, cz = 600, 350
    import math as _m
    enemies = []
    for i in range(8):
        angle = i * _m.pi / 4
        ex = cx + 250 * _m.cos(angle)
        ez = cz + 120 * _m.sin(angle)
        enemies.append(EnemyConfig(ex, ez, speed=2.0))

    return CombatScenario(
        name="chase_swarm",
        map_data=_make_map("chase_swarm", (xmin, xmax, ymin, ymax), []),
        agent_start=(cx, cz),
        enemy_pos=(cx - 250, cz),
        safe_zone=None,  # 无安全区，纯生存测试
        description="8 敌全方位包围，测试生存能力（无安全区）",
        enemies=enemies,
    )


# ═══════ 全部场景列表 ═══════

ALL_SCENARIOS = [
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

CHASE_SCENARIOS = [
    chase_pack_open,
    chase_pack_corridor,
    chase_pack_corner,
    chase_pack_obstacles,
    chase_swarm,
]


def get_all_scenarios() -> List[CombatScenario]:
    return [fn() for fn in ALL_SCENARIOS]


def get_scenario_by_name(name: str) -> CombatScenario:
    for fn in ALL_SCENARIOS + CHASE_SCENARIOS:
        s = fn()
        if s.name == name:
            return s
    raise ValueError(f"Unknown scenario: {name}")
