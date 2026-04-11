"""
佣兵 AI 状态机 —— 精确复刻 MecenaryBehavior.as 的逻辑。

状态: Sleeping → Thinking → Idle / Walking / Wandering → Thinking → ...

关键参数（对应 AS2 静态变量，可被外部调参覆盖）:
  IDLE_MIN/MAX, WALK_MIN/MAX, WANDER_MIN/MAX, ALIVE_MAX_TIME, STUCK_COUNT_MAX
"""

from __future__ import annotations

import random
import math
from dataclasses import dataclass, field
from typing import Optional, Tuple, List

from map_model import MapData
from collision import CollisionWorld, NavigationGrid


# ---------------------------------------------------------------------------
# 配置参数（可被外部 override）
# ---------------------------------------------------------------------------

@dataclass
class AIConfig:
    """对应 MecenaryBehavior 的静态常量 + Mover 的 step 参数。"""
    idle_min: int = 10
    idle_max: int = 40
    walk_min: int = 8
    walk_max: int = 40
    wander_min: int = 15
    wander_max: int = 50
    alive_max_time: int = 30 * 30     # 900 帧 = 30 秒 @30fps
    stuck_count_max: int = 3
    reachable_step: float = 50        # isReachable 的采样步长（AS2 传 50）
    reachable_to_point_step: float = 30   # isReachableToPoint 的步长
    walk_decision_interval: int = 4   # 每 N 帧判定一次方向
    move_speed: float = 4.0           # 每帧移动像素（近似 AS2 单位速度）
    arrive_dist_x: float = 50         # walk 到达判定距离
    arrive_dist_z: float = 25
    near_door_x: float = 100          # think 中"靠近门"判定
    near_door_z: float = 50


# ---------------------------------------------------------------------------
# AI Agent
# ---------------------------------------------------------------------------

@dataclass
class MercenaryAgent:
    """一个佣兵 AI 实例。"""
    x: float
    y: float   # 2.5D 中的 z 轴（地面坐标），对应 AS2 的 Z轴坐标
    config: AIConfig = field(default_factory=AIConfig)

    # 内部状态
    state: str = "Thinking"
    action_count: int = 0
    think_threshold: int = 0
    alive_frames: int = 0
    target_door: Optional[Tuple[float, float]] = None
    stuck_count: int = 0

    # 移动方向
    move_left: bool = False
    move_right: bool = False
    move_up: bool = False
    move_down: bool = False

    # 上一帧位置（用于卡死检测）
    prev_x: float = 0
    prev_y: float = 0

    # 统计
    exited: bool = False         # 是否已成功到达门
    trajectory: List[Tuple[float, float]] = field(default_factory=list)

    def __post_init__(self):
        self.prev_x = self.x
        self.prev_y = self.y
        self.trajectory = [(self.x, self.y)]


class MercenarySimulator:
    """
    模拟一个佣兵在地图上的完整生命周期。

    tick() 对应 AS2 的一次 action（每 4 帧一次）。
    """

    def __init__(self, map_data: MapData, collision: CollisionWorld,
                 agent: MercenaryAgent):
        self.map = map_data
        self.coll = collision
        self.agent = agent
        self._walk_tick = 0

    def tick(self) -> bool:
        """
        执行一次 AI 逻辑（= AS2 中一次 action，每 4 帧触发一次）。
        返回 True 表示佣兵仍在场上，False 表示已卸载或超时。
        """
        a = self.agent
        if a.exited:
            return False

        a.alive_frames += 4  # 每次 action = 4 帧

        if a.state == "Thinking":
            self._think()
        elif a.state == "Idle":
            self._idle()
        elif a.state == "Walking":
            self._walking()
        elif a.state == "Wandering":
            self._wandering()

        # 记录轨迹
        a.trajectory.append((a.x, a.y))
        return not a.exited

    def _think(self):
        """对应 MecenaryBehavior.think()"""
        a = self.agent
        cfg = a.config

        # 超时卸载
        if a.alive_frames > cfg.alive_max_time:
            a.exited = True
            return

        # 搜索可达的门
        reachable_doors = []
        for door in self.map.doors:
            ok, _ = self.coll.is_reachable(a.x, a.y, door[0], door[1],
                                           cfg.reachable_step)
            if ok:
                reachable_doors.append(door)

        new_state = None

        if a.target_door is None:
            if reachable_doors:
                a.target_door = random.choice(reachable_doors)

                diff_x = abs(a.target_door[0] - a.x)
                diff_z = abs(a.target_door[1] - a.y)

                if diff_x < cfg.near_door_x and diff_z < cfg.near_door_z:
                    # 已经靠近门 —— 基于存活时间的概率逻辑（复刻 AS2）
                    if a.alive_frames <= 100:
                        new_state = "Wandering" if random.random() < 0.33 else "Idle"
                    elif a.alive_frames <= 200:
                        p = 0.33 * (200 - a.alive_frames) / 100
                        new_state = "Wandering" if random.random() < p else "Idle"
                    elif a.alive_frames <= 300:
                        new_state = "Idle"
                    else:
                        new_state = "Walking"
                else:
                    new_state = "Idle" if random.random() < 0.5 else "Walking"
            else:
                # 没有可达门 → 漫游
                new_state = "Wandering"

        if new_state is None:
            new_state = "Idle" if random.random() < 0.5 else "Walking"

        self._change_state(new_state)

    def _idle(self):
        """Idle 状态：停止移动，计数器到达后回 Thinking。"""
        a = self.agent
        a.move_left = a.move_right = a.move_up = a.move_down = False
        a.action_count += 1
        if a.action_count >= a.think_threshold:
            self._change_state("Thinking")

    def _walking(self):
        """Walking 状态：朝目标门移动，复刻 walk() 的判定帧逻辑。"""
        a = self.agent
        cfg = a.config
        self._walk_tick += 1

        on_decision = (self._walk_tick % cfg.walk_decision_interval == 0)

        if on_decision:
            # 卡死检测
            dx = abs(a.x - a.prev_x)
            dy = abs(a.y - a.prev_y)
            if dx < 8 and dy < 3:
                a.stuck_count += 1
                if a.stuck_count >= cfg.stuck_count_max:
                    a.stuck_count = 0
                    self._change_state("Wandering")
                    return
            else:
                a.stuck_count = 0

            a.prev_x = a.x
            a.prev_y = a.y

            # 设置移动方向
            if a.target_door is not None:
                diff_x = a.target_door[0] - a.x
                diff_z = a.target_door[1] - a.y
                a.move_left = diff_x < -20
                a.move_right = diff_x > 20
                a.move_up = diff_z < -10
                a.move_down = diff_z > 10

        # 执行移动
        self._apply_movement()

        # 到达判定
        if a.target_door is not None:
            if (abs(a.target_door[0] - a.x) < cfg.arrive_dist_x and
                    abs(a.target_door[1] - a.y) < cfg.arrive_dist_z):
                a.exited = True
                return

        a.action_count += 1
        if a.action_count >= a.think_threshold:
            self._change_state("Thinking")

    def _wandering(self):
        """Wandering 状态：随机方向移动，复刻 wander_enter() 的逻辑。"""
        a = self.agent

        # 执行移动（方向在 enter 时已设定）
        self._apply_movement()

        a.action_count += 1
        if a.action_count >= a.think_threshold:
            self._change_state("Thinking")

    def _change_state(self, new_state: str):
        a = self.agent
        cfg = a.config
        a.state = new_state
        a.action_count = 0
        self._walk_tick = 0

        if new_state == "Idle":
            a.think_threshold = random.randint(cfg.idle_min, cfg.idle_max)
            a.move_left = a.move_right = a.move_up = a.move_down = False

        elif new_state == "Walking":
            a.think_threshold = random.randint(cfg.walk_min, cfg.walk_max)

        elif new_state == "Wandering":
            a.target_door = None  # 清除目标
            a.think_threshold = random.randint(cfg.wander_min, cfg.wander_max)

            # 随机选一个方向
            xmin, xmax, ymin, ymax = self.map.bounds
            # 尝试找可达的随机点（复刻 AS2 的 10 次尝试）
            found = False
            for _ in range(10):
                rx = random.uniform(xmin, xmax)
                ry = random.uniform(ymin, ymax)
                if self.coll.is_reachable_to_point(a.x, a.y, rx, ry,
                                                   cfg.reachable_to_point_step):
                    a.move_left = rx < a.x
                    a.move_right = not a.move_left
                    a.move_up = ry < a.y
                    a.move_down = ry > a.y
                    found = True
                    break

            if not found:
                rx = random.uniform(xmin, xmax)
                ry = random.uniform(ymin, ymax)
                a.move_left = rx < a.x
                a.move_right = not a.move_left
                a.move_up = ry < a.y
                a.move_down = ry > a.y

        elif new_state == "Thinking":
            self._think()

    def _apply_movement(self):
        """根据方向标志移动 agent，碰撞时不移动（简化 Mover.move2D）。"""
        a = self.agent
        cfg = a.config
        speed = cfg.move_speed

        dx = 0
        dy = 0
        if a.move_left:
            dx -= speed
        if a.move_right:
            dx += speed
        if a.move_up:
            dy -= speed
        if a.move_down:
            dy += speed

        # 对角线归一化
        if dx != 0 and dy != 0:
            factor = speed / math.sqrt(dx * dx + dy * dy)
            dx *= factor
            dy *= factor

        new_x = a.x + dx
        new_y = a.y + dy

        # 碰撞检测：如果目标点不可通行，尝试分轴移动
        if self.coll.is_point_valid(new_x, new_y):
            a.x = new_x
            a.y = new_y
        elif dx != 0 and self.coll.is_point_valid(a.x + dx, a.y):
            a.x += dx
        elif dy != 0 and self.coll.is_point_valid(a.x, a.y + dy):
            a.y += dy
        # else: 完全被卡住，不动


# ---------------------------------------------------------------------------
# 改进版 AI：Grid BFS 寻路
# ---------------------------------------------------------------------------

class BFSMercenarySimulator(MercenarySimulator):
    """
    使用 Grid BFS 寻路的改进版佣兵 AI。

    与原版的区别:
      - think() 中如果 L-path 不可达，回退到 Grid BFS 寻路
      - Walking 状态沿 BFS 路径的 waypoint 逐点移动，而非直线朝目标
      - 仍然兼容原版的所有状态和参数

    AS2 移植方案:
      - 场景加载时对 collisionLayer 做一次格栅采样（可分帧执行）
      - BFS 只在 think() 中执行一次，路径缓存在 data 中
      - Walking 状态按 waypoint 列表逐点走
    """

    def __init__(self, map_data: MapData, collision: CollisionWorld,
                 agent: MercenaryAgent, nav_grid: NavigationGrid):
        super().__init__(map_data, collision, agent)
        self.nav = nav_grid
        self._waypoints: Optional[List[Tuple[float, float]]] = None
        self._wp_index: int = 0

    def _think(self):
        """改进版 think：L-path 失败时用 Grid BFS。"""
        a = self.agent
        cfg = a.config

        # 超时卸载
        if a.alive_frames > cfg.alive_max_time:
            a.exited = True
            return

        # 搜索门 —— 先试 L-path（快），失败再试 BFS（慢但可靠）
        best_door = None
        best_path = None
        best_method = None

        for door in self.map.doors:
            ok, method = self.coll.is_reachable(a.x, a.y, door[0], door[1],
                                                cfg.reachable_step)
            if ok:
                best_door = door
                best_method = method
                best_path = None  # L-path 可达，不需要 waypoint
                break

        if best_door is None:
            # L-path 全部失败 → Grid BFS
            for door in self.map.doors:
                path = self.nav.find_path_with_waypoints(
                    a.x, a.y, door[0], door[1],
                    simplify_tolerance=cfg.move_speed * 2
                )
                if path is not None:
                    best_door = door
                    best_path = path
                    best_method = "BFS"
                    break

        new_state = None

        if best_door is not None:
            a.target_door = best_door
            self._waypoints = best_path
            self._wp_index = 0

            diff_x = abs(best_door[0] - a.x)
            diff_z = abs(best_door[1] - a.y)

            if diff_x < cfg.near_door_x and diff_z < cfg.near_door_z:
                # 已靠近门 —— 存活时间概率逻辑（同原版）
                if a.alive_frames <= 100:
                    new_state = "Wandering" if random.random() < 0.33 else "Idle"
                elif a.alive_frames <= 200:
                    p = 0.33 * (200 - a.alive_frames) / 100
                    new_state = "Wandering" if random.random() < p else "Idle"
                elif a.alive_frames <= 300:
                    new_state = "Idle"
                else:
                    new_state = "Walking"
            else:
                new_state = "Idle" if random.random() < 0.5 else "Walking"
        else:
            new_state = "Wandering"

        if new_state is None:
            new_state = "Idle" if random.random() < 0.5 else "Walking"

        self._change_state(new_state)

    def _walking(self):
        """改进版 Walking：有 waypoints 时沿路径走，否则退化为原版逻辑。"""
        a = self.agent
        cfg = a.config
        self._walk_tick += 1

        on_decision = (self._walk_tick % cfg.walk_decision_interval == 0)

        if on_decision:
            # 卡死检测
            dx = abs(a.x - a.prev_x)
            dy = abs(a.y - a.prev_y)
            if dx < 8 and dy < 3:
                a.stuck_count += 1
                if a.stuck_count >= cfg.stuck_count_max:
                    a.stuck_count = 0
                    self._change_state("Wandering")
                    return
            else:
                a.stuck_count = 0

            a.prev_x = a.x
            a.prev_y = a.y

            # 设置移动方向 —— 优先跟随 waypoint
            if self._waypoints and self._wp_index < len(self._waypoints):
                wp = self._waypoints[self._wp_index]
                diff_x = wp[0] - a.x
                diff_z = wp[1] - a.y

                # 到达当前 waypoint → 推进到下一个
                if abs(diff_x) < 15 and abs(diff_z) < 15:
                    self._wp_index += 1
                    if self._wp_index < len(self._waypoints):
                        wp = self._waypoints[self._wp_index]
                        diff_x = wp[0] - a.x
                        diff_z = wp[1] - a.y
                    else:
                        # 所有 waypoint 走完，直奔目标
                        if a.target_door is not None:
                            diff_x = a.target_door[0] - a.x
                            diff_z = a.target_door[1] - a.y

                a.move_left = diff_x < -10
                a.move_right = diff_x > 10
                a.move_up = diff_z < -5
                a.move_down = diff_z > 5

            elif a.target_door is not None:
                # 无 waypoint（L-path 可达），原版逻辑
                diff_x = a.target_door[0] - a.x
                diff_z = a.target_door[1] - a.y
                a.move_left = diff_x < -20
                a.move_right = diff_x > 20
                a.move_up = diff_z < -10
                a.move_down = diff_z > 10

        # 执行移动
        self._apply_movement()

        # 到达判定
        if a.target_door is not None:
            if (abs(a.target_door[0] - a.x) < cfg.arrive_dist_x and
                    abs(a.target_door[1] - a.y) < cfg.arrive_dist_z):
                a.exited = True
                return

        a.action_count += 1
        if a.action_count >= a.think_threshold:
            self._change_state("Thinking")


# ---------------------------------------------------------------------------
# 批量模拟工具
# ---------------------------------------------------------------------------

def _generate_spawn_points(coll: CollisionWorld, map_data: MapData,
                            n: int) -> List[Tuple[float, float]]:
    """在地图中央附近生成 n 个可行走的出生点。"""
    xmin, xmax, ymin, ymax = map_data.bounds
    cx = (xmin + xmax) / 2
    cy = (ymin + ymax) / 2
    spread_x = (xmax - xmin) * 0.3
    spread_y = (ymax - ymin) * 0.3

    points = []
    for _ in range(n):
        for _attempt in range(50):
            sx = random.gauss(cx, spread_x)
            sy = random.gauss(cy, spread_y)
            sx = max(xmin + 10, min(xmax - 10, sx))
            sy = max(ymin + 10, min(ymax - 10, sy))
            if coll.is_point_valid(sx, sy):
                break
        points.append((sx, sy))
    return points


def run_single_sim(map_data: MapData, spawn_x: float, spawn_y: float,
                   config: Optional[AIConfig] = None,
                   max_ticks: int = 1000,
                   use_bfs: bool = False,
                   nav_grid: Optional[NavigationGrid] = None
                   ) -> MercenaryAgent:
    """
    在指定地图上跑一次佣兵模拟。
    use_bfs=True 时使用 BFS 改进版 AI。
    """
    if config is None:
        config = AIConfig()

    coll = CollisionWorld(map_data)
    agent = MercenaryAgent(x=spawn_x, y=spawn_y, config=config)

    if use_bfs:
        if nav_grid is None:
            nav_grid = coll.build_grid(cell_size=20)
        sim = BFSMercenarySimulator(map_data, coll, agent, nav_grid)
    else:
        sim = MercenarySimulator(map_data, coll, agent)

    for _ in range(max_ticks):
        if not sim.tick():
            break

    return agent


def run_batch_sim(map_data: MapData, n_agents: int = 50,
                  config: Optional[AIConfig] = None,
                  max_ticks: int = 1000,
                  use_bfs: bool = False) -> List[MercenaryAgent]:
    """
    在同一张地图上批量模拟多个佣兵，返回所有 agent。
    use_bfs=True 时使用 BFS 改进版 AI。
    """
    coll = CollisionWorld(map_data)
    nav_grid = coll.build_grid(cell_size=20) if use_bfs else None

    spawn_points = _generate_spawn_points(coll, map_data, n_agents)

    agents = []
    for sx, sy in spawn_points:
        agent = run_single_sim(map_data, sx, sy, config, max_ticks,
                               use_bfs=use_bfs, nav_grid=nav_grid)
        agents.append(agent)

    return agents


def run_compare_sim(map_data: MapData, n_agents: int = 50,
                    config: Optional[AIConfig] = None,
                    max_ticks: int = 1000
                    ) -> Tuple[List[MercenaryAgent], List[MercenaryAgent]]:
    """
    在同一张地图、同一批出生点上分别跑 baseline 和 BFS，保证公平对比。
    返回 (baseline_agents, bfs_agents)。
    """
    coll = CollisionWorld(map_data)
    nav_grid = coll.build_grid(cell_size=20)

    # 生成一批共享出生点
    spawn_points = _generate_spawn_points(coll, map_data, n_agents)

    baseline_agents = []
    bfs_agents = []

    for sx, sy in spawn_points:
        # Baseline
        agent_b = run_single_sim(map_data, sx, sy, config, max_ticks,
                                 use_bfs=False)
        baseline_agents.append(agent_b)

        # BFS
        agent_a = run_single_sim(map_data, sx, sy, config, max_ticks,
                                 use_bfs=True, nav_grid=nav_grid)
        bfs_agents.append(agent_a)

    return baseline_agents, bfs_agents
