"""
碰撞检测与可达性判定 —— 精确复刻 AS2 Mover 的逻辑。

AS2 原始逻辑（Mover.as）:
  isReachable 尝试 3 条路径:
    1. 直线 start → end
    2. L 形 HV: start → (endX, startY) → end
    3. L 形 VH: start → (startX, endY) → end
  每条路径用 checkSegment 按步长采样，hitTest 碰撞层。

本模块用 shapely 多边形替代 Flash hitTest。
"""

from __future__ import annotations

from typing import List, Tuple, Optional
from shapely.geometry import Polygon, Point, LineString, MultiPolygon
from shapely.ops import unary_union
import math

from map_model import MapData


class CollisionWorld:
    """管理碰撞检测和可达性，对应 AS2 的 _root.collisionLayer.hitTest。"""

    def __init__(self, map_data: MapData):
        self.map = map_data
        # 合并所有碰撞多边形为一个 union，加速 contains 查询
        if map_data.collisions:
            self._obstacle_union = unary_union(map_data.collisions)
        else:
            self._obstacle_union = Polygon()  # 空多边形

    def is_point_valid(self, x: float, y: float) -> bool:
        """对应 Mover.isPointValid: 点不在碰撞体内 且 在地图边界内。"""
        xmin, xmax, ymin, ymax = self.map.bounds
        if x < xmin or x > xmax or y < ymin or y > ymax:
            return False
        return not self._obstacle_union.contains(Point(x, y))

    def check_segment(self, x1: float, y1: float, x2: float, y2: float,
                      step: float = 10) -> bool:
        """
        对应 Mover.checkSegment: 沿线段每隔 step 像素采样，检测是否全部可通行。
        返回 True = 通畅, False = 被阻挡。
        """
        dx = x2 - x1
        dy = y2 - y1
        dist = math.sqrt(dx * dx + dy * dy)
        if dist < 0.01:
            return self.is_point_valid(x1, y1)

        steps = max(1, int(dist / step))
        for i in range(steps + 1):
            t = i / steps
            px = x1 + dx * t
            py = y1 + dy * t
            if not self.is_point_valid(px, py):
                return False
        return True

    def is_reachable(self, sx: float, sy: float, ex: float, ey: float,
                     step: float = 10) -> Tuple[bool, Optional[str]]:
        """
        精确复刻 AS2 Mover.isReachable 的 3 条路径策略。
        返回 (可达, 路径类型) —— 路径类型: "direct" / "L_HV" / "L_VH" / None
        """
        # 1) 直线
        if self.check_segment(sx, sy, ex, ey, step):
            return True, "direct"

        # 2) L 形: 先横后纵
        if (self.check_segment(sx, sy, ex, sy, step) and
                self.check_segment(ex, sy, ex, ey, step)):
            return True, "L_HV"

        # 3) L 形: 先纵后横
        if (self.check_segment(sx, sy, sx, ey, step) and
                self.check_segment(sx, ey, ex, ey, step)):
            return True, "L_VH"

        return False, None

    def is_reachable_to_point(self, sx: float, sy: float, ex: float, ey: float,
                              step: float = 30) -> bool:
        """对应 Mover.isReachableToPoint，用于漫游目标验证。"""
        ok, _ = self.is_reachable(sx, sy, ex, ey, step)
        return ok

    # ------------------------------------------------------------------
    # Grid BFS 寻路 —— 只依赖 is_point_valid，不需要碰撞体顶点信息
    # ------------------------------------------------------------------

    def build_grid(self, cell_size: float = 20) -> 'NavigationGrid':
        """
        将可行走区域按 cell_size 离散化为格栅，预计算每个格子的可通行性。
        返回 NavigationGrid 实例，可多次查询不同 start→end 的路径。
        """
        return NavigationGrid(self, cell_size)


class NavigationGrid:
    """
    格栅化导航图 —— 只依赖 hitTest 点查询，适配运行时绘制的碰撞层。

    原理:
      1. 把地图按 cell_size 划分格子
      2. 预计算每个格子中心点的可通行性 → bool 数组
      3. BFS/A* 在格子图上搜索路径
      4. 返回格子中心坐标序列作为路径点

    AS2 移植时:
      - 初始化阶段对 collisionLayer 做一次全局 hitTest 采样（可分帧）
      - 路径搜索用 BFS，队列用数组模拟
      - 路径点缓存，不需要每帧重算
    """

    # 8 方向偏移：上下左右 + 4 对角线
    _DIRS_8 = [
        (-1, 0), (1, 0), (0, -1), (0, 1),
        (-1, -1), (-1, 1), (1, -1), (1, 1),
    ]
    # 4 方向偏移
    _DIRS_4 = [(-1, 0), (1, 0), (0, -1), (0, 1)]

    def __init__(self, coll: CollisionWorld, cell_size: float = 20):
        self.coll = coll
        self.cell_size = cell_size
        m = coll.map

        self.ox = m.xmin  # 格栅原点 x
        self.oy = m.ymin  # 格栅原点 y
        self.cols = max(1, int((m.xmax - m.xmin) / cell_size) + 1)
        self.rows = max(1, int((m.ymax - m.ymin) / cell_size) + 1)

        # 预计算可通行性 (row-major flat array)
        self.walkable = [False] * (self.rows * self.cols)
        for r in range(self.rows):
            for c in range(self.cols):
                wx, wy = self._cell_to_world(r, c)
                self.walkable[r * self.cols + c] = coll.is_point_valid(wx, wy)

    def _cell_to_world(self, r: int, c: int) -> Tuple[float, float]:
        """格子坐标 → 世界坐标（格子中心）。"""
        return (self.ox + (c + 0.5) * self.cell_size,
                self.oy + (r + 0.5) * self.cell_size)

    def _world_to_cell(self, x: float, y: float) -> Tuple[int, int]:
        """世界坐标 → 格子坐标。"""
        c = int((x - self.ox) / self.cell_size)
        r = int((y - self.oy) / self.cell_size)
        c = max(0, min(self.cols - 1, c))
        r = max(0, min(self.rows - 1, r))
        return r, c

    def _is_walkable(self, r: int, c: int) -> bool:
        if r < 0 or r >= self.rows or c < 0 or c >= self.cols:
            return False
        return self.walkable[r * self.cols + c]

    def find_path(self, sx: float, sy: float, ex: float, ey: float,
                  use_8dir: bool = True) -> Optional[List[Tuple[float, float]]]:
        """
        BFS 寻路。

        Args:
            sx, sy: 起点世界坐标
            ex, ey: 终点世界坐标
            use_8dir: True=8方向, False=4方向

        Returns:
            路径点列表 [(x,y), ...] 从起点到终点，或 None 表示不可达。
        """
        sr, sc = self._world_to_cell(sx, sy)
        er, ec = self._world_to_cell(ex, ey)

        # 起点或终点不可走 → 找最近的可走格子
        if not self._is_walkable(sr, sc):
            found = self._find_nearest_walkable(sr, sc)
            if found is None:
                return None
            sr, sc = found

        if not self._is_walkable(er, ec):
            found = self._find_nearest_walkable(er, ec)
            if found is None:
                return None
            er, ec = found

        if sr == er and sc == ec:
            return [self._cell_to_world(sr, sc)]

        dirs = self._DIRS_8 if use_8dir else self._DIRS_4

        # BFS
        visited = set()
        visited.add((sr, sc))
        # parent 记录来路，用于回溯路径
        parent = {}
        queue = [(sr, sc)]
        head = 0
        found = False

        while head < len(queue):
            r, c = queue[head]
            head += 1

            if r == er and c == ec:
                found = True
                break

            for dr, dc in dirs:
                nr, nc = r + dr, c + dc
                if (nr, nc) in visited:
                    continue
                if not self._is_walkable(nr, nc):
                    continue
                # 对角线移动时检查两个相邻格是否可通行（防止穿角）
                if dr != 0 and dc != 0:
                    if not self._is_walkable(r + dr, c) or not self._is_walkable(r, c + dc):
                        continue
                visited.add((nr, nc))
                parent[(nr, nc)] = (r, c)
                queue.append((nr, nc))

        if not found:
            return None

        # 回溯路径
        path = []
        cur = (er, ec)
        while cur in parent:
            path.append(self._cell_to_world(cur[0], cur[1]))
            cur = parent[cur]
        path.append(self._cell_to_world(sr, sc))
        path.reverse()

        return path

    def _find_nearest_walkable(self, r: int, c: int, max_dist: int = 5
                                ) -> Optional[Tuple[int, int]]:
        """在 (r,c) 附近找最近的可走格子。"""
        for d in range(1, max_dist + 1):
            for dr in range(-d, d + 1):
                for dc in range(-d, d + 1):
                    if abs(dr) != d and abs(dc) != d:
                        continue  # 只检查外圈
                    nr, nc = r + dr, c + dc
                    if self._is_walkable(nr, nc):
                        return (nr, nc)
        return None

    def _axis_smooth(self, path: List[Tuple[float, float]]
                      ) -> List[Tuple[float, float]]:
        """
        轴对齐路径平滑：只保留方向变化的拐点。

        格栅路径会有大量同方向的连续点（如一直向右走 10 格），
        合并为起点→拐点→拐点→终点，减少 waypoint 数量。
        与 4 方向移动系统完全兼容（不引入斜线）。
        """
        if len(path) <= 2:
            return path

        smoothed = [path[0]]
        for i in range(1, len(path) - 1):
            # 计算前后方向
            prev_dx = path[i][0] - path[i-1][0]
            prev_dy = path[i][1] - path[i-1][1]
            next_dx = path[i+1][0] - path[i][0]
            next_dy = path[i+1][1] - path[i][1]

            # 方向发生变化 → 保留为拐点
            if (prev_dx != next_dx) or (prev_dy != next_dy):
                smoothed.append(path[i])

        smoothed.append(path[-1])
        return smoothed

    def _los_smooth(self, path: List[Tuple[float, float]]
                     ) -> List[Tuple[float, float]]:
        """
        视线路径平滑（Line-of-Sight smoothing）。

        从路径起点开始，尝试跳过中间 waypoint 直接连到更远的点。
        如果两点之间的直线全部在可通行区域内（checkSegment），就跳过中间的点。
        显著缩短格栅路径在开阔区域的锯齿绕行。
        """
        if len(path) <= 2:
            return path

        smoothed = [path[0]]
        current = 0

        while current < len(path) - 1:
            # 从当前点尽量跳到最远的可直达点
            farthest = current + 1
            for candidate in range(len(path) - 1, current + 1, -1):
                if self.coll.check_segment(
                    path[current][0], path[current][1],
                    path[candidate][0], path[candidate][1],
                    step=self.cell_size * 0.7  # 比格子小的步长确保精度
                ):
                    farthest = candidate
                    break

            smoothed.append(path[farthest])
            current = farthest

        return smoothed

    def find_path_with_waypoints(self, sx: float, sy: float, ex: float, ey: float,
                                  simplify_tolerance: float = 0
                                  ) -> Optional[List[Tuple[float, float]]]:
        """
        寻路 + LOS 路径平滑 + 可选 Douglas-Peucker 简化。
        """
        path = self.find_path(sx, sy, ex, ey)
        if path is None or len(path) <= 2:
            return path

        # 轴对齐路径平滑：合并同方向连续段，只保留拐点
        path = self._axis_smooth(path)

        if simplify_tolerance > 0 and len(path) > 2:
            from shapely.geometry import LineString
            line = LineString(path)
            simplified = line.simplify(simplify_tolerance, preserve_topology=True)
            return list(simplified.coords)

        return path
