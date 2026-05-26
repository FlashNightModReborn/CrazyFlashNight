"""
八门金锁射线视觉原型 - Python 概念验证

目的: 在投入 AS2 实现前, 用 Python 快速验证以下设计参数:
  1. 角速度 (deg/frame): 30 deg/frame 起点
  2. 黑白沿对角分界 + 偶/奇切片反向旋转 (DNA 双螺旋意象)
  3. 单层简化: 外八边形 + 4 主对角, 仅保留中枢线
  4. 切片大小: 首版统一 100%

输出: 八门金锁_视觉原型.mp4 (优先) 或 .gif (兜底)

锁定的是"概念参数"——角速度/相位/拓扑/分界方式。
不锁定渲染细节: 线宽/抗锯齿/精确颜色——这些必须在 Flash AVM1 里调。
"""

import math
import os
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from matplotlib.patches import Polygon
from matplotlib.lines import Line2D
import numpy as np


# ============================================================================
# 设计参数 (后续微调主要改这一段)
# ============================================================================
SLICES_COUNT      = 8            # 切片数 = 霰弹数基线
SLICE_SPACING     = 90           # 切片轴向间距 (v2: 60→90, 避免切片挤压)
SLICE_RADIUS      = 35           # 切片八边形半径
SLICE_COMPRESS_X  = 0.5          # 横向压缩比 (3D 透视感)
ANG_VEL_DEG       = 15.0         # 自旋角速度 (v4: 30→15, 让律动主导方向感)
COUNTER_ROTATE    = True         # 偶/奇切片反向自旋 (双螺旋)
PHASE_OFFSET_DEG  = 22.5         # 相邻切片初始相位差 (默认半个边)
DRAW_DIAGONALS    = True         # 是否绘制内部主对角
N_DIAGONALS       = 2            # 内部对角数 (v2: 4→2, 减内增外)
DRAW_SPINE        = True         # 是否绘制中枢贯穿线
DRAW_VERT_LINKERS = True         # 是否绘制相邻切片间的纵向连杆
LINKER_VERTEX_STRIDE = 1         # 取顶点的步长 (1=8 根全部, 2=4 根隔一个, 4=2 根上下)
COLOR_SPLIT_ROTATES = True       # 黑白分界是否跟随切片自旋
WHITE_GLOW        = True         # 暖白半边外发光

# v3/v4: 爆发模式 (匹配游戏内真实生命周期)
BURST_FRAMES      = 15           # 单次射线持续帧数 (v4: 12→15)
FADE_FRAMES       = 3            # 爆发末尾淡出帧 (v4: 4→3, 律动 α 已自然衰减)
DARK_FRAMES       = 6            # 暗场帧 (仅原型查看用, 游戏内无)
LOOP_CYCLES       = 3            # 原型视频中循环次数

# v3: 律动传递 (从源头到末端的尺寸脉冲)
PULSE_PROPAGATE   = True         # 启用律动
PULSE_AMP         = 0.55         # 峰值切片放大比例 (v4: 0.45→0.55, 配合宽脉冲)
PULSE_WIDTH       = 2.5          # 脉冲宽度 (v4: 1.5→2.5, 宽脉冲更有力)

# v4: 律动透明度调制 (脉冲同时改"激活度", 自然传达发射与衰减)
PULSE_ALPHA_MODULATE = True      # 启用 α 律动
BASE_PULSE_ALPHA  = 0.30         # 脉冲范围外的"待机"切片可见度
# 切片实际 α = BASE_PULSE_ALPHA + (1 - BASE_PULSE_ALPHA) × pulse_intensity

FPS               = 30

CANVAS_W_PX       = 1200
CANVAS_H_PX       = 320
BG_COLOR          = "#1a1a1a"    # 暗背景, 接近游戏内场景
# v2 配色: 暖白 + 深石墨, 替代纯黑白
WHITE_LINE        = "#FFE5C4"    # 暖白 (带金属余温)
BLACK_LINE        = "#36404A"    # 深石墨/gunmetal (在暗场上仍可见)
GLOW_COLOR        = "#FFE5C4"    # 同暖白, 低 α 厚描边
GLOW_ALPHA        = 0.18
GLOW_WIDTH_MULT   = 4.5
MIXED_EDGE        = "#7A6F66"    # 跨界边: 暖白与石墨的中性混色
SPINE_COLOR       = "#FFB347"    # 深金 (更饱和, 与暖白拉开)
STROKE_WIDTH      = 1.8


# ============================================================================
# 几何
# ============================================================================
def octagon_vertices(cx, cy, R, compress_x, rotation_deg):
    """计算八边形 8 个顶点 (旋转应用在 local frame, 然后横向压缩)."""
    rot = math.radians(rotation_deg)
    pts = []
    for k in range(8):
        theta = rot + k * math.pi / 4
        x_local = math.cos(theta) * R
        y_local = math.sin(theta) * R
        pts.append((cx + x_local * compress_x, cy + y_local))
    return pts


def pulse_intensity(slice_idx, burst_frame):
    """返回 [0, 1] 的脉冲强度. 0 = 远离脉冲, 1 = 脉冲峰值正在该切片.
    脉冲中心从 progress=0 时的 -0.5 扫到 progress=1 时的 SLICES_COUNT-0.5.
    """
    if not PULSE_PROPAGATE:
        return 0.0
    progress = burst_frame / max(1, BURST_FRAMES - 1)
    pulse_center = -0.5 + progress * SLICES_COUNT
    dist = abs(slice_idx - pulse_center) / PULSE_WIDTH
    if dist >= 1.0:
        return 0.0
    return 0.5 * (1.0 + math.cos(math.pi * dist))


def slice_size_factor(slice_idx, burst_frame):
    """律动: 尺寸脉冲沿索引方向从源头(0)传递到末端(SLICES_COUNT-1).
    返回半径乘数 [1.0, 1.0 + PULSE_AMP]. cosine 波包形状.
    """
    return 1.0 + PULSE_AMP * pulse_intensity(slice_idx, burst_frame)


def slice_alpha_factor(slice_idx, burst_frame):
    """律动 α: 切片越接近脉冲峰值越亮, 远端衰减到 BASE_PULSE_ALPHA.
    PULSE_ALPHA_MODULATE 关闭时恒返回 1.0 (兼容旧行为).
    """
    if not PULSE_ALPHA_MODULATE or not PULSE_PROPAGATE:
        return 1.0
    intensity = pulse_intensity(slice_idx, burst_frame)
    return BASE_PULSE_ALPHA + (1.0 - BASE_PULSE_ALPHA) * intensity


def split_edges_by_axis(vertices, split_angle_deg):
    """
    将 8 个顶点沿一条过中心的对角分成"黑半"与"白半".
    split_angle_deg 是分界轴的角度 (跟随切片自旋, 实现"两极沿轴翻滚").
    """
    rot = math.radians(split_angle_deg)
    nx, ny = -math.sin(rot), math.cos(rot)   # 分界轴法向 (右侧为白)
    n_slice = len(vertices)
    cx = sum(p[0] for p in vertices) / n_slice
    cy = sum(p[1] for p in vertices) / n_slice
    sides = []  # True = white, False = black
    for vx, vy in vertices:
        side = (vx - cx) * nx + (vy - cy) * ny >= 0
        sides.append(side)
    return sides


def slice_rotation(slice_idx, frame):
    """每切片在当前帧的自旋角度."""
    direction = -1 if (COUNTER_ROTATE and slice_idx % 2 == 1) else 1
    return slice_idx * PHASE_OFFSET_DEG + direction * ANG_VEL_DEG * frame


# ============================================================================
# 渲染单帧
# ============================================================================
def cycle_state(global_frame):
    """根据 global_frame 算出当前在 burst cycle 的哪个阶段.
    返回 (phase, burst_frame, alpha_mult).
    phase: "burst" / "fade" / "dark"
    """
    cycle_len = BURST_FRAMES + FADE_FRAMES + DARK_FRAMES
    f = global_frame % cycle_len
    if f < BURST_FRAMES:
        return "burst", f, 1.0
    elif f < BURST_FRAMES + FADE_FRAMES:
        fade_t = (f - BURST_FRAMES) / max(1, FADE_FRAMES)
        return "fade", BURST_FRAMES - 1, max(0.0, 1.0 - fade_t)
    else:
        return "dark", 0, 0.0


def draw_frame(ax, global_frame):
    ax.clear()
    ax.set_facecolor(BG_COLOR)
    ax.set_xlim(0, CANVAS_W_PX)
    ax.set_ylim(-CANVAS_H_PX / 2, CANVAS_H_PX / 2)
    ax.set_aspect("equal")
    ax.set_xticks([]); ax.set_yticks([])
    for spine in ax.spines.values():
        spine.set_visible(False)

    phase, burst_frame, alpha_mult = cycle_state(global_frame)

    # 标题水印 (无论何相位都显示, 便于参数核对)
    ax.text(
        10, CANVAS_H_PX / 2 - 18,
        f"ω={ANG_VEL_DEG:.0f}°/f  counter={COUNTER_ROTATE}  "
        f"split-rot={COLOR_SPLIT_ROTATES}  pulse={PULSE_PROPAGATE}  "
        f"burst={BURST_FRAMES}f  frame={global_frame:03d} [{phase}]",
        color="#888888", fontsize=8, family="monospace", zorder=10
    )

    if phase == "dark":
        return

    # 切片中心 X 坐标 (从左到右等距)
    left_margin = (CANVAS_W_PX - (SLICES_COUNT - 1) * SLICE_SPACING) / 2
    slice_centers_x = [left_margin + i * SLICE_SPACING for i in range(SLICES_COUNT)]
    slice_cy = 0.0

    # 预计算所有切片当前半径与 α 因子 (含律动)
    slice_radii = [SLICE_RADIUS * slice_size_factor(i, burst_frame)
                   for i in range(SLICES_COUNT)]
    slice_alphas = [slice_alpha_factor(i, burst_frame)
                    for i in range(SLICES_COUNT)]

    # 中枢线 (跟随律动峰值, 但保留较高的"轴线常驻"基线)
    if DRAW_SPINE:
        # 中枢 α: 由律动最强切片决定, 保证脉冲在场时轴线醒目
        peak_alpha = max(slice_alphas) if slice_alphas else 1.0
        spine_alpha = 0.45 + 0.40 * peak_alpha  # 0.45 (待机) → 0.85 (脉冲峰值)
        ax.plot(
            [slice_centers_x[0], slice_centers_x[-1]], [slice_cy, slice_cy],
            color=SPINE_COLOR, linewidth=STROKE_WIDTH * 1.4,
            alpha=spine_alpha * alpha_mult, zorder=1
        )

    # 相邻切片纵向连杆 (顶点对顶点, 按顶点黑白属性染色 → 双螺旋编织)
    # α 取两端较小值 (linker 与较暗端绑定衰减)
    if DRAW_VERT_LINKERS:
        for i in range(SLICES_COUNT - 1):
            rot_a = slice_rotation(i, burst_frame)
            rot_b = slice_rotation(i + 1, burst_frame)
            verts_a = octagon_vertices(slice_centers_x[i], slice_cy, slice_radii[i],
                                       SLICE_COMPRESS_X, rot_a)
            verts_b = octagon_vertices(slice_centers_x[i + 1], slice_cy, slice_radii[i + 1],
                                       SLICE_COMPRESS_X, rot_b)
            split_a = rot_a if COLOR_SPLIT_ROTATES else 0.0
            split_b = rot_b if COLOR_SPLIT_ROTATES else 0.0
            sides_a = split_edges_by_axis(verts_a, split_a)
            sides_b = split_edges_by_axis(verts_b, split_b)
            linker_a = min(slice_alphas[i], slice_alphas[i + 1])
            for k in range(0, 8, LINKER_VERTEX_STRIDE):
                # 同一顶点 k: 若两端同色, 用对应色; 不同则走中性 (相邻切片反旋时常见)
                if sides_a[k] == sides_b[k]:
                    color = WHITE_LINE if sides_a[k] else BLACK_LINE
                    base_alpha = 0.7
                else:
                    color = MIXED_EDGE
                    base_alpha = 0.45
                ax.plot(
                    [verts_a[k][0], verts_b[k][0]],
                    [verts_a[k][1], verts_b[k][1]],
                    color=color, linewidth=STROKE_WIDTH * 0.7,
                    alpha=base_alpha * linker_a * alpha_mult, zorder=2
                )

    # 逐切片绘制
    for i in range(SLICES_COUNT):
        cx = slice_centers_x[i]
        rot = slice_rotation(i, burst_frame)
        verts = octagon_vertices(cx, slice_cy, slice_radii[i], SLICE_COMPRESS_X, rot)
        alpha_i = slice_alphas[i]

        # 黑白分界: 分界轴跟随切片自旋 (旋进式分界, 而非死板左右切半)
        split_angle = rot if COLOR_SPLIT_ROTATES else 0.0
        sides = split_edges_by_axis(verts, split_angle)

        # 律动放大额外加成: 峰值切片 glow 更强 (放大比例越大 α 越高)
        radius_boost = slice_radii[i] / SLICE_RADIUS - 1.0  # 0 ~ PULSE_AMP
        glow_boost = 1.0 + radius_boost * 1.5

        # 外轮廓 (8 条边)
        # 暖白半边: 先铺一层低 α 厚描边作外发光, 再叠主线
        for k in range(8):
            v0 = verts[k]
            v1 = verts[(k + 1) % 8]
            s0, s1 = sides[k], sides[(k + 1) % 8]
            if s0 == s1:
                color = WHITE_LINE if s0 else BLACK_LINE
                # 暖白半边的外发光 (峰值切片更亮)
                if WHITE_GLOW and s0:
                    ax.plot([v0[0], v1[0]], [v0[1], v1[1]],
                            color=GLOW_COLOR, linewidth=STROKE_WIDTH * GLOW_WIDTH_MULT,
                            alpha=GLOW_ALPHA * glow_boost * alpha_i * alpha_mult, zorder=3.5,
                            solid_capstyle="round")
            else:
                color = MIXED_EDGE
            ax.plot([v0[0], v1[0]], [v0[1], v1[1]],
                    color=color, linewidth=STROKE_WIDTH,
                    alpha=alpha_i * alpha_mult, zorder=4)

        # 内部主对角 (顶点过中心, k 与 k+4 相连)
        # v2: 数量从 4 减到 2, 仅取等间隔的对角 (k=0,4 和 k=2,6)
        if DRAW_DIAGONALS:
            diag_stride = max(1, 4 // N_DIAGONALS)
            for k in range(0, 4, diag_stride):
                v0 = verts[k]
                v1 = verts[k + 4]
                s0 = sides[k]
                color = WHITE_LINE if s0 else BLACK_LINE
                ax.plot([v0[0], v1[0]], [v0[1], v1[1]],
                        color=color, linewidth=STROKE_WIDTH * 0.75,
                        alpha=0.9 * alpha_i * alpha_mult, zorder=3)

    return None


# ============================================================================
# 视频生成
# ============================================================================
def build_video(out_path: Path):
    # v3: 总帧数 = (爆发 + 淡出 + 暗场) × 循环次数
    cycle_len = BURST_FRAMES + FADE_FRAMES + DARK_FRAMES
    total_frames = cycle_len * LOOP_CYCLES

    fig, ax = plt.subplots(
        figsize=(CANVAS_W_PX / 100, CANVAS_H_PX / 100), dpi=100
    )
    fig.patch.set_facecolor(BG_COLOR)
    fig.subplots_adjust(left=0, right=1, top=1, bottom=0)

    def update(frame_idx):
        draw_frame(ax, frame_idx)
        return []

    anim = animation.FuncAnimation(
        fig, update, frames=total_frames, interval=1000 / FPS, blit=False
    )

    # 优先尝试 mp4 (需 ffmpeg), 失败则回退到 gif
    saved_path = None
    try:
        writer = animation.FFMpegWriter(fps=FPS, bitrate=2000,
                                        codec="libx264",
                                        extra_args=["-pix_fmt", "yuv420p"])
        mp4_path = out_path.with_suffix(".mp4")
        anim.save(str(mp4_path), writer=writer)
        saved_path = mp4_path
    except Exception as exc:
        print(f"[fallback] mp4 失败 ({exc.__class__.__name__}: {exc}), 改写 gif")
        gif_path = out_path.with_suffix(".gif")
        anim.save(str(gif_path), writer=animation.PillowWriter(fps=FPS))
        saved_path = gif_path

    plt.close(fig)
    return saved_path


if __name__ == "__main__":
    out = Path(__file__).parent / "八门金锁_视觉原型"
    saved = build_video(out)
    print(f"[ok] 视觉原型已生成: {saved}")
    print(f"     爆发={BURST_FRAMES}帧  律动={PULSE_PROPAGATE}(amp={PULSE_AMP},w={PULSE_WIDTH})  "
          f"ω={ANG_VEL_DEG}°/帧  反旋={COUNTER_ROTATE}")
