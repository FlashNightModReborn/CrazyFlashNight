"""
地图模型：解析 scene_environment.xml 中的真实地图，以及随机生成测试地图。

地图数据结构 MapData:
  - name: str              地图名
  - bounds: (xmin, xmax, ymin, ymax)  可行走边界
  - width, height: int     画布尺寸
  - collisions: list[Polygon]   碰撞多边形（不可通行区域）
  - doors: list[(x, y)]    门的位置（佣兵需要走到这里卸载）
"""

from __future__ import annotations

import os
import random
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from typing import List, Tuple, Optional

from shapely.geometry import Polygon, Point, box as _shapely_box
from shapely.ops import unary_union

# re-export for module-level use
box = _shapely_box


@dataclass
class MapData:
    name: str
    bounds: Tuple[float, float, float, float]  # xmin, xmax, ymin, ymax
    width: float
    height: float
    collisions: List[Polygon] = field(default_factory=list)
    doors: List[Tuple[float, float]] = field(default_factory=list)

    @property
    def xmin(self) -> float:
        return self.bounds[0]

    @property
    def xmax(self) -> float:
        return self.bounds[1]

    @property
    def ymin(self) -> float:
        return self.bounds[2]

    @property
    def ymax(self) -> float:
        return self.bounds[3]


# ---------------------------------------------------------------------------
# 解析真实地图
# ---------------------------------------------------------------------------

def _parse_collision(env_elem: ET.Element) -> List[Polygon]:
    """从 <Environment> 节点解析所有 <Collision> 多边形。"""
    polygons = []
    for coll in env_elem.findall("Collision"):
        pts = []
        for pt_elem in coll.findall("Point"):
            coords = pt_elem.text.strip().split(",")
            pts.append((float(coords[0]), float(coords[1])))
        if len(pts) >= 3:
            polygons.append(Polygon(pts))
    return polygons


def load_real_maps(xml_path: str) -> List[MapData]:
    """从 scene_environment.xml 加载所有有碰撞数据的真实地图。"""
    tree = ET.parse(xml_path)
    root = tree.getroot()
    maps = []

    for env in root.findall("Environment"):
        name_elem = env.find("BackgroundURL")
        if name_elem is None:
            continue
        name = name_elem.text.strip()

        xmin = float(env.findtext("Xmin", "0"))
        xmax = float(env.findtext("Xmax", "1024"))
        ymin = float(env.findtext("Ymin", "0"))
        ymax = float(env.findtext("Ymax", "512"))
        width = float(env.findtext("Width", str(xmax)))
        height = float(env.findtext("Height", str(ymax)))

        collisions = _parse_collision(env)

        # 真实地图的门位置不在XML中，稍后由 place_doors_randomly 补充
        maps.append(MapData(
            name=name,
            bounds=(xmin, xmax, ymin, ymax),
            width=width,
            height=height,
            collisions=collisions,
            doors=[],
        ))

    return maps


# ---------------------------------------------------------------------------
# 随机生成测试地图
# ---------------------------------------------------------------------------

def _random_convex_obstacle(bounds: Tuple[float, float, float, float],
                            max_size: float = 150) -> Polygon:
    """在边界内生成一个随机凸多边形障碍物。"""
    xmin, xmax, ymin, ymax = bounds
    cx = random.uniform(xmin + max_size, xmax - max_size)
    cy = random.uniform(ymin + max_size, ymax - max_size)

    import math
    n_verts = random.randint(3, 7)
    angles = sorted([random.uniform(0, 2 * math.pi) for _ in range(n_verts)])
    pts = []
    for a in angles:
        r = random.uniform(max_size * 0.3, max_size)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))

    poly = Polygon(pts)
    return poly if poly.is_valid else poly.convex_hull


def _random_corridor_obstacle(bounds: Tuple[float, float, float, float]) -> Polygon:
    """生成一个长条形障碍（模拟墙壁/走廊），这是佣兵AI最难处理的类型。"""
    xmin, xmax, ymin, ymax = bounds
    w = xmax - xmin
    h = ymax - ymin

    if random.random() < 0.5:
        # 水平墙
        wall_y = random.uniform(ymin + h * 0.2, ymax - h * 0.2)
        wall_x1 = random.uniform(xmin, xmin + w * 0.3)
        wall_x2 = random.uniform(xmax - w * 0.3, xmax)
        thickness = random.uniform(55, 80)  # 必须 > 步长50
        gap_x = random.uniform(wall_x1 + 50, wall_x2 - 50)
        gap_w = random.uniform(50, 90)
        # 墙有缺口 → 两段
        left = box(wall_x1, wall_y, gap_x - gap_w / 2, wall_y + thickness)
        right = box(gap_x + gap_w / 2, wall_y, wall_x2, wall_y + thickness)
        return unary_union([left, right])
    else:
        # 垂直墙
        wall_x = random.uniform(xmin + w * 0.2, xmax - w * 0.2)
        wall_y1 = random.uniform(ymin, ymin + h * 0.3)
        wall_y2 = random.uniform(ymax - h * 0.3, ymax)
        thickness = random.uniform(55, 80)  # 必须 > 步长50
        gap_y = random.uniform(wall_y1 + 50, wall_y2 - 50)
        gap_h = random.uniform(50, 90)
        top = box(wall_x, wall_y1, wall_x + thickness, gap_y - gap_h / 2)
        bottom = box(wall_x, gap_y + gap_h / 2, wall_x + thickness, wall_y2)
        return unary_union([top, bottom])


def generate_random_map(name: str = "random",
                        width: float = 1200,
                        height: float = 600,
                        n_obstacles: int = 3,
                        n_doors: int = 2,
                        difficulty: str = "medium") -> MapData:
    """
    生成随机测试地图。

    difficulty:
      - "easy"   : 少量小凸障碍
      - "medium" : 混合凸障碍+走廊墙
      - "hard"   : 多走廊墙，窄通道，U形等
    """
    margin = 50
    xmin, xmax = margin, width - margin
    ymin, ymax = int(height * 0.4), int(height * 0.85)
    bounds = (xmin, xmax, ymin, ymax)

    collisions = []
    walkable = box(xmin, ymin, xmax, ymax)

    if difficulty == "easy":
        for _ in range(n_obstacles):
            collisions.append(_random_convex_obstacle(bounds, max_size=80))
    elif difficulty == "medium":
        for _ in range(max(1, n_obstacles // 2)):
            collisions.append(_random_convex_obstacle(bounds, max_size=120))
        for _ in range(max(1, n_obstacles - n_obstacles // 2)):
            c = _random_corridor_obstacle(bounds)
            if not c.is_empty:
                collisions.append(c)
    else:  # hard
        for _ in range(n_obstacles):
            c = _random_corridor_obstacle(bounds)
            if not c.is_empty:
                collisions.append(c)
        # 加一个U形障碍
        u_cx = random.uniform(xmin + 200, xmax - 200)
        u_cy = random.uniform(ymin + 80, ymax - 80)
        u_w, u_h, u_t = 200, 150, 60
        left = box(u_cx - u_w / 2, u_cy - u_h / 2, u_cx - u_w / 2 + u_t, u_cy + u_h / 2)
        bottom = box(u_cx - u_w / 2, u_cy + u_h / 2 - u_t, u_cx + u_w / 2, u_cy + u_h / 2)
        right = box(u_cx + u_w / 2 - u_t, u_cy - u_h / 2, u_cx + u_w / 2, u_cy + u_h / 2)
        collisions.append(unary_union([left, bottom, right]))

    # 放置门：确保门在可行走区域内（不在碰撞体内）
    obstacle_union = unary_union(collisions) if collisions else Polygon()
    doors = []
    for _ in range(n_doors):
        for _attempt in range(200):
            dx = random.uniform(xmin + 20, xmax - 20)
            dy = random.uniform(ymin + 10, ymax - 10)
            if not obstacle_union.contains(Point(dx, dy)):
                doors.append((dx, dy))
                break

    return MapData(
        name=name,
        bounds=bounds,
        width=width,
        height=height,
        collisions=collisions,
        doors=doors,
    )


def generate_adversarial_map(name: str = "adversarial",
                            pattern: str = "wall_gap") -> MapData:
    """
    生成专门设计来击败 L-path 算法的对抗性地图。

    pattern:
      - "wall_gap": 横墙隔断+中间缺口，门在墙另一侧 → L路径全被墙挡
      - "zigzag": Z字形走廊 → 需要多次转弯
      - "u_trap": 门在U形障碍内部 → 需要绕到U开口
      - "spiral": 螺旋走廊，门在中心
      - "double_wall": 两道平行墙，缺口不对齐
    """
    width, height = 1200, 600
    margin = 50
    xmin, xmax = margin, width - margin
    ymin, ymax = int(height * 0.3), int(height * 0.85)
    bounds = (xmin, xmax, ymin, ymax)

    collisions = []
    doors = []
    t = 60  # 墙壁厚度（必须 > isReachable 步长 50px，否则采样跳过）

    if pattern == "wall_gap":
        # 一道横墙把地图分为左右两半，中间有一个缺口
        wall_x = (xmin + xmax) / 2
        gap_y = random.uniform(ymin + 80, ymax - 80)
        gap_h = 60  # 缺口高度
        # 上半墙
        collisions.append(box(wall_x - t / 2, ymin - 10, wall_x + t / 2, gap_y - gap_h / 2))
        # 下半墙
        collisions.append(box(wall_x - t / 2, gap_y + gap_h / 2, wall_x + t / 2, ymax + 10))
        # 佣兵生成在左侧，门在右侧
        doors.append((xmax - 60, (ymin + ymax) / 2))

    elif pattern == "zigzag":
        # 三道交替墙形成Z字通道
        third_w = (xmax - xmin) / 3
        gap = 70
        # 第1墙：从上到下，留底部缺口
        x1 = xmin + third_w
        collisions.append(box(x1 - t / 2, ymin - 10, x1 + t / 2, ymax - gap))
        # 第2墙：从下到上，留顶部缺口
        x2 = xmin + 2 * third_w
        collisions.append(box(x2 - t / 2, ymin + gap, x2 + t / 2, ymax + 10))
        # 门在最右
        doors.append((xmax - 60, (ymin + ymax) / 2))

    elif pattern == "u_trap":
        # U形障碍，开口朝上，门在U的底部内侧
        cx = (xmin + xmax) / 2
        cy = (ymin + ymax) / 2
        u_w, u_h = 300, 200
        # 左壁
        collisions.append(box(cx - u_w / 2, cy - u_h / 2, cx - u_w / 2 + t, cy + u_h / 2))
        # 底壁
        collisions.append(box(cx - u_w / 2, cy + u_h / 2 - t, cx + u_w / 2, cy + u_h / 2))
        # 右壁
        collisions.append(box(cx + u_w / 2 - t, cy - u_h / 2, cx + u_w / 2, cy + u_h / 2))
        # 门在U内部底部
        doors.append((cx, cy + u_h / 2 - 40))

    elif pattern == "spiral":
        # 回旋走廊：两道嵌套的L墙，迫使佣兵走"回"字路线
        cx = (xmin + xmax) / 2
        cy = (ymin + ymax) / 2
        corridor = 70  # 走廊宽（必须容得下佣兵通行）
        # 外层：顶墙+左墙（开口在右下）
        ow, oh = 500, 280
        collisions.append(box(cx - ow / 2, cy - oh / 2, cx + ow / 2, cy - oh / 2 + t))  # 顶
        collisions.append(box(cx - ow / 2, cy - oh / 2, cx - ow / 2 + t, cy + oh / 2))  # 左
        # 内层：底墙+右墙（开口在左上，与外层开口相反）
        iw = ow - 2 * (t + corridor)
        ih = oh - 2 * (t + corridor)
        if iw > 80 and ih > 40:
            collisions.append(box(cx - iw / 2, cy + ih / 2 - t, cx + iw / 2, cy + ih / 2))  # 底
            collisions.append(box(cx + iw / 2 - t, cy - ih / 2, cx + iw / 2, cy + ih / 2))  # 右
        # 门在内层内部
        doors.append((cx - 20, cy))

    elif pattern == "double_wall":
        # 两道平行纵墙，缺口不对齐（一个在上，一个在下）
        third_w = (xmax - xmin) / 3
        gap = 70
        x1 = xmin + third_w
        x2 = xmin + 2 * third_w
        # 墙1缺口在底部
        collisions.append(box(x1 - t / 2, ymin - 10, x1 + t / 2, ymax - gap))
        # 墙2缺口在顶部
        collisions.append(box(x2 - t / 2, ymin + gap, x2 + t / 2, ymax + 10))
        # 门在最右
        doors.append((xmax - 60, ymin + 40))

    elif pattern == "narrow_maze":
        # 3道交替横墙+纵墙组成简易迷宫，缺口很窄
        gap = 55  # 窄缺口
        h_range = ymax - ymin
        # 横墙1（上方，缺口在右）
        hy1 = ymin + h_range * 0.33
        collisions.append(box(xmin - 10, hy1, xmax - gap - 60, hy1 + t))
        # 横墙2（下方，缺口在左）
        hy2 = ymin + h_range * 0.66
        collisions.append(box(xmin + gap + 60, hy2, xmax + 10, hy2 + t))
        # 纵墙（中间，缺口在底）
        vx = (xmin + xmax) / 2
        collisions.append(box(vx - t / 2, ymin - 10, vx + t / 2, ymax - gap))
        # 门在右下角
        doors.append((xmax - 40, ymax - 30))

    elif pattern == "bottleneck":
        # 两个大障碍物中间留一个极窄通道，门在通道对面的空地上
        cx = (xmin + xmax) / 2
        cy = (ymin + ymax) / 2
        passage = 55  # 通道宽
        block_len = (xmax - xmin) * 0.35  # 每个障碍物长度（不要太大）
        block_h = t * 1.5
        # 左侧块
        collisions.append(box(cx - passage / 2 - block_len, cy - block_h / 2,
                              cx - passage / 2, cy + block_h / 2))
        # 右侧块
        collisions.append(box(cx + passage / 2, cy - block_h / 2,
                              cx + passage / 2 + block_len, cy + block_h / 2))
        # 门在右侧空地（障碍物之后）
        doors.append((cx + passage / 2 + block_len + 60, cy))

    elif pattern == "pocket":
        # 门在口袋内部：三面墙封闭，开口朝左（但门在右下角）
        # 佣兵需要先向左走找到开口再绕进去
        px = xmax - 200  # 口袋右边界
        py = ymin + 30    # 口袋上边界
        pw, ph = 250, 200  # 口袋宽高
        gap = 60           # 开口宽
        # 上壁
        collisions.append(box(px - pw, py, px, py + t))
        # 右壁
        collisions.append(box(px - t, py, px, py + ph))
        # 下壁（留左侧开口）
        collisions.append(box(px - pw + gap, py + ph - t, px, py + ph))
        # 门在口袋内部右下
        doors.append((px - 40, py + ph - 50))

    elif pattern == "long_corridor":
        # 蛇形走廊：4段交替横向通道，佣兵需要走完整个蛇形才能到门
        gap = 60
        n_turns = 4
        seg_h = (ymax - ymin - t * n_turns) / (n_turns + 1)
        for i in range(n_turns):
            wy = ymin + (i + 1) * (seg_h + t) - t
            if i % 2 == 0:
                # 缺口在右
                collisions.append(box(xmin - 10, wy, xmax - gap, wy + t))
            else:
                # 缺口在左
                collisions.append(box(xmin + gap, wy, xmax + 10, wy + t))
        # 门在最底部（蛇形末端）
        if n_turns % 2 == 0:
            doors.append((xmin + 40, ymax - 20))
        else:
            doors.append((xmax - 40, ymax - 20))

    elif pattern == "multi_room":
        # 3个房间通过窄门连通
        h_range = ymax - ymin
        room_w = (xmax - xmin) / 3
        gap = 60
        # 墙1（房间1-2之间），缺口在下方
        x1 = xmin + room_w
        collisions.append(box(x1 - t / 2, ymin - 10, x1 + t / 2, ymax - gap))
        # 墙2（房间2-3之间），缺口在上方
        x2 = xmin + 2 * room_w
        collisions.append(box(x2 - t / 2, ymin + gap, x2 + t / 2, ymax + 10))
        # 每个房间加一个内部障碍增加复杂度
        for rx in [xmin + room_w * 0.5, xmin + room_w * 1.5, xmin + room_w * 2.5]:
            oy = random.uniform(ymin + 40, ymax - 40)
            ow = random.uniform(60, 100)
            oh = random.uniform(40, 70)
            collisions.append(box(rx - ow / 2, oy - oh / 2, rx + ow / 2, oy + oh / 2))
        # 门在最右房间
        doors.append((xmax - 40, (ymin + ymax) / 2))

    return MapData(
        name=f"{name}_{pattern}",
        bounds=bounds,
        width=width,
        height=height,
        collisions=collisions,
        doors=doors,
    )


def place_doors_on_bounds(map_data: MapData, n_doors: int = 2) -> None:
    """
    在地图边界附近放置门（模拟真实场景中门在地图边缘的情况）。
    佣兵通常从地图中部生成，需要走到边缘的门才能卸载。
    """
    obstacle_union = unary_union(map_data.collisions) if map_data.collisions else Polygon()
    xmin, xmax, ymin, ymax = map_data.bounds
    doors = []

    edges = ["left", "right", "top", "bottom"]
    for i in range(n_doors):
        edge = edges[i % len(edges)]
        for _attempt in range(200):
            if edge == "left":
                dx, dy = xmin + 15, random.uniform(ymin + 20, ymax - 20)
            elif edge == "right":
                dx, dy = xmax - 15, random.uniform(ymin + 20, ymax - 20)
            elif edge == "top":
                dx, dy = random.uniform(xmin + 20, xmax - 20), ymin + 15
            else:
                dx, dy = random.uniform(xmin + 20, xmax - 20), ymax - 15

            if not obstacle_union.contains(Point(dx, dy)):
                doors.append((dx, dy))
                break

    map_data.doors = doors
