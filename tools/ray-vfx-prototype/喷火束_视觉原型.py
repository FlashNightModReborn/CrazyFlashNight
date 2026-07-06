"""
喷火束射线视觉原型 - Python 概念验证

目的:
  1. 用接近 AS2 MovieClip 绘图 API 的包装层验证喷火束几何。
  2. 验证"目标长度 targetLength"与"当前长度 currentLength"的增长/缩回节奏。
  3. 锁定下放到 FlameStreamRenderer.as / TeslaRayConfig / VfxPresets 的核心参数。

输出:
  喷火束_视觉原型.mp4，若缺少 ffmpeg 则自动回退为 gif。
"""

from __future__ import annotations

import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.animation as animation
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Polygon


# ============================================================================
# 设计参数
# ============================================================================
FPS = 30
CANVAS_W_PX = 1100
CANVAS_H_PX = 360
BG_COLOR = "#151515"

MAX_LENGTH = 760.0
START_LENGTH = 70.0
GROW_SPEED = 96.0
RETRACT_SPEED = 240.0
BLOCKER_LENGTH = 430.0
BLOCK_START_FRAME = 24
BLOCK_END_FRAME = 52

POLY_STEPS = 28
TONGUE_STEPS = 18
TONGUE_LAYER_COUNT = 5
EDGE_STREAK_COUNT = 8
DETAIL_ALPHA_SCALE = 1.0
OUTER_BASE_HALF_WIDTH = 8.0
OUTER_MAX_HALF_WIDTH = 52.0
BODY_BASE_HALF_WIDTH = 4.2
BODY_MAX_HALF_WIDTH = 34.0
HOT_TONGUE_MAX_HALF_WIDTH = 18.0
CORE_THICKNESS = 2.8
WAVE_AMP = 28.0
OUTER_WAVE_AMP = 38.0
WAVE_FREQ = 12.0
OUTER_WAVE_FREQ = 8.0
WAVE_SPEED = 0.55
EDGE_NOISE_AMP = 6.5
EDGE_NOISE_FREQ = 20.0
EDGE_NOISE_SPEED = 1.1
TIP_BACKOFF = 8.0
BLOCKED_TIP_SCALE = 1.8
FREE_TIP_SCALE = 0.8
EMBER_COUNT = 7

LOOP_FRAMES = 90
LOOP_CYCLES = 2

OUTER_COLOR = "#9C2A00"
MID_COLOR = "#FF6A00"
CORE_COLOR = "#FFE650"
HOT_COLOR = "#FFF3B0"
SMOKE_COLOR = "#3A251B"
DEEP_COLOR = "#5A1400"
HOT_ORANGE_COLOR = "#FF9A12"
WHITE_CORE_COLOR = "#FFF8D2"

TONGUE_SPECS = (
    {
        "color": MID_COLOR,
        "alpha": 38,
        "start": 0.04,
        "end": 0.96,
        "width": 0.82,
        "amp": 0.92,
        "freq": 0.96,
        "phase": 0.4,
        "bias": -7.0,
    },
    {
        "color": HOT_ORANGE_COLOR,
        "alpha": 58,
        "start": 0.02,
        "end": 0.78,
        "width": 0.58,
        "amp": 0.56,
        "freq": 1.12,
        "phase": 2.4,
        "bias": 6.0,
    },
    {
        "color": CORE_COLOR,
        "alpha": 42,
        "start": 0.08,
        "end": 0.68,
        "width": 0.42,
        "amp": 0.34,
        "freq": 0.85,
        "phase": 4.0,
        "bias": -2.0,
    },
    {
        "color": HOT_ORANGE_COLOR,
        "alpha": 34,
        "start": 0.30,
        "end": 0.98,
        "width": 0.66,
        "amp": 1.12,
        "freq": 1.35,
        "phase": 5.3,
        "bias": 10.0,
    },
    {
        "color": WHITE_CORE_COLOR,
        "alpha": 26,
        "start": 0.10,
        "end": 0.56,
        "width": 0.24,
        "amp": 0.18,
        "freq": 0.70,
        "phase": 1.6,
        "bias": 1.0,
    },
)


# ============================================================================
# 极简 AS2 绘图 API 模拟
# ============================================================================
class AS2Canvas:
    def __init__(self, ax):
        self.ax = ax
        self._line = {
            "thickness": 1.0,
            "color": "#FFFFFF",
            "alpha": 1.0,
        }
        self._fill = None
        self._path = []
        self._cursor = (0.0, 0.0)

    def lineStyle(self, thickness, color, alpha=100, *_args):
        self._flush_path()
        self._line = {
            "thickness": float(thickness),
            "color": _as_color(color),
            "alpha": max(0.0, min(1.0, float(alpha) / 100.0)),
        }

    def moveTo(self, x, y):
        self._flush_path()
        self._cursor = (float(x), float(y))
        self._path = [self._cursor]

    def lineTo(self, x, y):
        p = (float(x), float(y))
        if not self._path:
            self._path = [self._cursor]
        self._path.append(p)
        self._cursor = p

    def curveTo(self, cx, cy, x, y):
        if not self._path:
            self._path = [self._cursor]
        x0, y0 = self._cursor
        cx = float(cx)
        cy = float(cy)
        x = float(x)
        y = float(y)
        for i in range(1, 9):
            t = i / 8.0
            mt = 1.0 - t
            qx = mt * mt * x0 + 2 * mt * t * cx + t * t * x
            qy = mt * mt * y0 + 2 * mt * t * cy + t * t * y
            self._path.append((qx, qy))
        self._cursor = (x, y)

    def beginFill(self, color, alpha=100):
        self._flush_path()
        self._fill = {
            "color": _as_color(color),
            "alpha": max(0.0, min(1.0, float(alpha) / 100.0)),
        }

    def endFill(self):
        if self._fill is not None and len(self._path) >= 3:
            self.ax.add_patch(
                Polygon(
                    self._path,
                    closed=True,
                    facecolor=self._fill["color"],
                    edgecolor="none",
                    alpha=self._fill["alpha"],
                )
            )
        self._path = []
        self._fill = None

    def drawCircle(self, x, y, radius, color, alpha=100):
        self._flush_path()
        self.ax.add_patch(
            Circle(
                (x, y),
                radius,
                facecolor=_as_color(color),
                edgecolor="none",
                alpha=max(0.0, min(1.0, float(alpha) / 100.0)),
            )
        )

    def _flush_path(self):
        if self._fill is not None:
            return
        if len(self._path) >= 2 and self._line["alpha"] > 0:
            xs = [p[0] for p in self._path]
            ys = [p[1] for p in self._path]
            self.ax.plot(
                xs,
                ys,
                color=self._line["color"],
                linewidth=self._line["thickness"],
                alpha=self._line["alpha"],
                solid_capstyle="round",
                solid_joinstyle="round",
            )
        self._path = []

    def finish(self):
        self._flush_path()


def _as_color(value):
    if isinstance(value, str):
        return value
    return f"#{int(value) & 0xFFFFFF:06X}"


# ============================================================================
# 动画状态
# ============================================================================
def blocker_target_length(frame):
    phase = frame % LOOP_FRAMES
    if BLOCK_START_FRAME <= phase <= BLOCK_END_FRAME:
        return BLOCKER_LENGTH
    return MAX_LENGTH


def length_at_frame(frame):
    current = START_LENGTH
    for f in range((frame % LOOP_FRAMES) + 1):
        target = blocker_target_length(f)
        if target > current:
            current = min(target, current + GROW_SPEED)
        else:
            current = max(target, current - RETRACT_SPEED)
    return current


def stable_noise(seed):
    return math.sin(seed * 12.9898) * 43758.5453 % 1.0


def axis_wave(t, age, amp, freq, speed, phase=0.0):
    """喷流主轴扰动。t^2 保证枪口稳定，尾端翻卷。"""
    t2 = t * t
    primary = math.sin(t * freq - age * speed + phase)
    secondary = 0.35 * math.sin(t * freq * 1.83 + age * speed * 0.72 + phase * 0.5)
    return (primary + secondary) * amp * t2


def edge_noise(t, age, phase=0.0):
    """火焰边缘毛刺，只在中后段明显。"""
    return math.sin(t * EDGE_NOISE_FREQ - age * EDGE_NOISE_SPEED + phase) * EDGE_NOISE_AMP * t


def center_y(start_y, t, age, amp=WAVE_AMP, freq=WAVE_FREQ, speed=WAVE_SPEED, phase=0.0):
    return start_y + axis_wave(t, age, amp, freq, speed, phase)


def draw_flame_polygon(
    mc,
    start_x,
    start_y,
    length,
    age,
    color,
    alpha,
    base_half_width,
    max_half_width,
    wave_amp,
    wave_freq,
    phase=0.0,
    length_scale=1.0,
    steps=None,
    edge_noise_scale=1.0,
    tip_extension=0.0,
):
    """用填充锥形多边形画火焰体积，避免等宽线条的能量束感。"""
    draw_len = max(1.0, length * length_scale)
    steps = max(4, int(POLY_STEPS if steps is None else steps))
    bottom = []

    mc.beginFill(color, alpha)
    mc.moveTo(start_x, start_y - base_half_width)

    for i in range(steps + 1):
        t = i / steps
        x = start_x + draw_len * t
        y = center_y(start_y, t, age, wave_amp, wave_freq, WAVE_SPEED, phase)
        cone_w = base_half_width + (max_half_width - base_half_width) * t
        ripple = edge_noise(t, age, phase) * edge_noise_scale
        top_w = max(1.0, cone_w + ripple)
        bot_w = max(1.0, cone_w - ripple * 0.65)
        mc.lineTo(x, y - top_w)
        bottom.append((x, y + bot_w))

    if tip_extension > 0:
        tip_y = center_y(start_y, 1.0, age, wave_amp, wave_freq, WAVE_SPEED, phase)
        tip_y += edge_noise(1.0, age, phase + 1.1) * 0.45
        mc.lineTo(start_x + draw_len + tip_extension, tip_y)

    for x, y in reversed(bottom):
        mc.lineTo(x, y)

    mc.endFill()


def draw_tongue_polygon(
    mc,
    start_x,
    start_y,
    length,
    age,
    color,
    alpha,
    start_t,
    end_t,
    max_half_width,
    wave_amp,
    wave_freq,
    phase=0.0,
    y_bias=0.0,
):
    """局部火舌层：短、错相位、带尖端收束，用来补燃烧体积。"""
    if length < 80:
        return

    start_t = max(0.0, min(0.96, start_t))
    end_t = max(start_t + 0.04, min(1.0, end_t))
    steps = max(4, int(TONGUE_STEPS))
    top = []
    bottom = []

    for i in range(steps + 1):
        u = i / steps
        t = start_t + (end_t - start_t) * u
        x = start_x + length * t
        y = center_y(start_y, t, age, wave_amp, wave_freq, WAVE_SPEED, phase)
        y += y_bias * math.sin(math.pi * u) * (0.35 + t * 0.75)

        envelope = math.sin(math.pi * u)
        tail_bias = 0.70 + t * 0.42
        pulse = 0.92 + 0.10 * math.sin(age * 0.78 + phase)
        half_w = max(1.4, max_half_width * (0.16 + 0.84 * envelope ** 0.62) * tail_bias * pulse)
        ripple = edge_noise(t, age, phase + 2.7) * 0.55

        top.append((x, y - max(1.0, half_w + ripple)))
        bottom.append((x, y + max(1.0, half_w - ripple * 0.75)))

    mc.beginFill(color, int(alpha * DETAIL_ALPHA_SCALE))
    mc.moveTo(top[0][0], top[0][1])
    for x, y in top[1:]:
        mc.lineTo(x, y)
    if max_half_width > 2:
        tip_u = 1.0
        tip_t = end_t
        tip_y = center_y(start_y, tip_t, age, wave_amp, wave_freq, WAVE_SPEED, phase)
        tip_y += y_bias * math.sin(math.pi * tip_u) * (0.35 + tip_t * 0.75)
        tip_y += edge_noise(tip_t, age, phase + 1.4) * 0.28
        mc.lineTo(start_x + length * end_t + max_half_width * 0.42, tip_y)
    for x, y in reversed(bottom):
        mc.lineTo(x, y)
    mc.endFill()


def draw_hot_tongues(mc, start_x, start_y, length, age):
    count = max(0, min(len(TONGUE_SPECS), int(TONGUE_LAYER_COUNT)))
    for spec in TONGUE_SPECS[:count]:
        draw_tongue_polygon(
            mc,
            start_x,
            start_y,
            length,
            age,
            spec["color"],
            spec["alpha"],
            spec["start"],
            spec["end"],
            HOT_TONGUE_MAX_HALF_WIDTH * spec["width"],
            WAVE_AMP * spec["amp"],
            WAVE_FREQ * spec["freq"],
            phase=spec["phase"],
            y_bias=spec["bias"],
        )


def draw_edge_streaks(mc, start_x, start_y, length, age, is_blocked):
    if length < 180:
        return

    count = max(0, int(EDGE_STREAK_COUNT))
    for k in range(count):
        drift = (age * 0.016 + stable_noise(k * 3.7) * 0.12) % 0.18
        t = 0.30 + (k + 0.5) / max(1, count) * 0.62 + drift
        if t > 0.98:
            t -= 0.28
        if is_blocked and t > 0.92:
            t = 0.88

        side = -1.0 if k % 2 == 0 else 1.0
        x = start_x + length * t
        center = center_y(start_y, t, age, OUTER_WAVE_AMP, OUTER_WAVE_FREQ, WAVE_SPEED, 0.6)
        width = OUTER_BASE_HALF_WIDTH + (OUTER_MAX_HALF_WIDTH - OUTER_BASE_HALF_WIDTH) * t
        y = center + side * (width + 3.0 + stable_noise(k + 9.0) * 10.0)
        line_len = 14.0 + stable_noise(k + int(age) * 0.11) * 24.0
        dy = side * (3.0 + 8.0 * stable_noise(k + 4.0))
        color = HOT_ORANGE_COLOR if k % 3 else CORE_COLOR
        alpha = int((36 + stable_noise(k + 1.0) * 28) * DETAIL_ALPHA_SCALE)

        mc.lineStyle(1.1 + stable_noise(k + 2.0) * 1.4, color, alpha)
        mc.moveTo(x, y)
        mc.lineTo(x + line_len, y + dy)


def draw_core_line(mc, start_x, start_y, length, age):
    """高压内核，短、直、亮；不能跟外焰一样大幅波动。"""
    core_len = max(20.0, length * 0.50)
    core_t_max = min(1.0, core_len / max(1.0, length))
    steps = 5

    layers = (
        (CORE_COLOR, CORE_THICKNESS * 1.40, 46, ((0.00, 0.58),)),
        (HOT_COLOR, CORE_THICKNESS * 0.82, 72, ((0.00, 0.28), (0.36, 0.46), (0.54, 0.60))),
        (WHITE_CORE_COLOR, CORE_THICKNESS * 0.32, 86, ((0.00, 0.20), (0.34, 0.40))),
    )

    for color, thickness, alpha, ranges in layers:
        mc.lineStyle(thickness, color, alpha)
        for start_u, end_u in ranges:
            for i in range(steps + 1):
                u = start_u + (end_u - start_u) * (i / steps)
                x = start_x + core_len * u
                t = core_t_max * u
                y = center_y(start_y, t, age, 2.2, 9.0, WAVE_SPEED * 0.48, 0.0)
                if i == 0:
                    mc.moveTo(x, y)
                else:
                    mc.lineTo(x, y)


def draw_tip_pile(mc, start_x, start_y, length, age, is_blocked):
    tip_scale = BLOCKED_TIP_SCALE if is_blocked else FREE_TIP_SCALE
    tip_x = start_x + length - (TIP_BACKOFF if is_blocked else 0.0)
    tip_y = center_y(
        start_y,
        1.0,
        age,
        WAVE_AMP if not is_blocked else WAVE_AMP * 0.45,
        WAVE_FREQ,
        WAVE_SPEED,
        1.3,
    )
    pulse = 1.0 + math.sin(age * 1.7) * (0.18 if is_blocked else 0.08)

    mc.drawCircle(tip_x - 9 * tip_scale, tip_y + 5 * tip_scale, 32 * tip_scale * pulse, DEEP_COLOR, 26)
    mc.drawCircle(tip_x + 4 * tip_scale, tip_y - 3 * tip_scale, 24 * tip_scale * pulse, OUTER_COLOR, 36)
    mc.drawCircle(tip_x + 8 * tip_scale, tip_y + 4 * tip_scale, 17 * tip_scale * pulse, MID_COLOR, 86)
    mc.drawCircle(tip_x - 2 * tip_scale, tip_y - 2 * tip_scale, 11 * tip_scale, HOT_ORANGE_COLOR, 92)
    mc.drawCircle(tip_x + 3 * tip_scale, tip_y, 6 * tip_scale, HOT_COLOR, 100)


def draw_muzzle_bloom(mc, start_x, start_y, age):
    pulse = 1.0 + math.sin(age * 1.2) * 0.08
    mc.drawCircle(start_x + 5, start_y, 13 * pulse, WHITE_CORE_COLOR, 78)
    mc.drawCircle(start_x + 12, start_y, 20 * pulse, HOT_COLOR, 54)
    mc.drawCircle(start_x + 20, start_y, 31 * pulse, MID_COLOR, 24)


def draw_embers(mc, start_x, start_y, length, age, is_blocked):
    if is_blocked or length < 140:
        return
    mc.lineStyle(2.0, CORE_COLOR, 92)
    for k in range(EMBER_COUNT):
        t = (age * 0.055 + k * 0.27) % 1.0
        if t < 0.22:
            continue
        x = start_x + length * t
        y = center_y(start_y, t, age, WAVE_AMP, WAVE_FREQ, WAVE_SPEED, 0.0)
        y += math.sin(k * 17.0) * 18.0 * t
        spark_len = 4.0 + 3.0 * stable_noise(k + int(age))
        mc.moveTo(x, y)
        mc.lineTo(x + spark_len, y - 1.0)


def draw_frame(ax, global_frame):
    ax.clear()
    ax.set_facecolor(BG_COLOR)
    ax.set_xlim(0, CANVAS_W_PX)
    ax.set_ylim(-CANVAS_H_PX / 2, CANVAS_H_PX / 2)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    for spine in ax.spines.values():
        spine.set_visible(False)

    phase = global_frame % LOOP_FRAMES
    length = length_at_frame(global_frame)
    target = blocker_target_length(global_frame)
    origin_x = 140.0
    origin_y = 0.0
    mc = AS2Canvas(ax)

    ax.text(
        12,
        CANVAS_H_PX / 2 - 22,
        f"len={length:5.1f} target={target:5.1f} grow={GROW_SPEED:.0f}/f retract={RETRACT_SPEED:.0f}/f frame={phase:02d}",
        color="#8A8A8A",
        fontsize=8,
        family="monospace",
    )

    if target < MAX_LENGTH:
        ax.axvline(origin_x + target, color="#5C6B5C", linewidth=1.0, alpha=0.55)

    is_blocked = target < MAX_LENGTH

    # Layer 0: 暗烟/热浪底色，极低透明度，只负责暗场轮廓。
    draw_flame_polygon(
        mc,
        origin_x,
        origin_y + 3,
        length,
        global_frame,
        SMOKE_COLOR,
        16,
        OUTER_BASE_HALF_WIDTH + 3,
        OUTER_MAX_HALF_WIDTH + 22,
        OUTER_WAVE_AMP * 1.08,
        OUTER_WAVE_FREQ * 0.85,
        phase=2.1,
        edge_noise_scale=1.22,
        tip_extension=34.0,
    )

    # Layer 1: 更深的外缘补一层，让轮廓有烧灼厚度。
    draw_flame_polygon(
        mc,
        origin_x,
        origin_y - 2,
        length * 0.94,
        global_frame,
        DEEP_COLOR,
        24,
        OUTER_BASE_HALF_WIDTH + 1,
        OUTER_MAX_HALF_WIDTH + 10,
        OUTER_WAVE_AMP * 1.18,
        OUTER_WAVE_FREQ * 1.05,
        phase=3.6,
        edge_noise_scale=1.10,
        tip_extension=28.0,
    )

    # Layer 2: 暗红外焰，锥形扩散，尾端翻卷。
    draw_flame_polygon(
        mc,
        origin_x,
        origin_y,
        length,
        global_frame,
        OUTER_COLOR,
        42,
        OUTER_BASE_HALF_WIDTH,
        OUTER_MAX_HALF_WIDTH,
        OUTER_WAVE_AMP,
        OUTER_WAVE_FREQ,
        phase=0.6,
        edge_noise_scale=1.0,
        tip_extension=24.0,
    )

    # Layer 3: 错相外焰，补掉规则锥形的机械感。
    draw_flame_polygon(
        mc,
        origin_x,
        origin_y + 2,
        length * 0.88,
        global_frame,
        OUTER_COLOR,
        30,
        OUTER_BASE_HALF_WIDTH * 0.70,
        OUTER_MAX_HALF_WIDTH * 0.72,
        OUTER_WAVE_AMP * 0.78,
        OUTER_WAVE_FREQ * 1.28,
        phase=4.8,
        edge_noise_scale=1.35,
        tip_extension=18.0,
    )

    # Layer 4: 橙色主体，错相位的中等宽度锥形面。
    draw_flame_polygon(
        mc,
        origin_x,
        origin_y,
        length * 0.96,
        global_frame,
        MID_COLOR,
        72,
        BODY_BASE_HALF_WIDTH,
        BODY_MAX_HALF_WIDTH,
        WAVE_AMP,
        WAVE_FREQ,
        phase=1.9,
        edge_noise_scale=0.82,
        tip_extension=18.0,
    )

    # Layer 5: 多条局部火舌，长度、相位、偏移都不同，增强燃烧体积。
    draw_hot_tongues(mc, origin_x, origin_y, length, global_frame)

    # Layer 6: 短黄焰面，只覆盖前中段，避免一根白线贯穿到端点。
    draw_flame_polygon(
        mc,
        origin_x,
        origin_y,
        length * 0.64,
        global_frame,
        CORE_COLOR,
        36,
        BODY_BASE_HALF_WIDTH * 0.45,
        HOT_TONGUE_MAX_HALF_WIDTH * 0.72,
        WAVE_AMP * 0.38,
        WAVE_FREQ * 0.8,
        phase=3.2,
        steps=TONGUE_STEPS,
        edge_noise_scale=0.45,
        tip_extension=8.0,
    )

    # Layer 7: 高压黄白内核，只保留前段，且几乎笔直。
    draw_core_line(mc, origin_x, origin_y, length, global_frame)

    # 炮口、端点堆火、边缘短焰和少量短线余烬。
    draw_muzzle_bloom(mc, origin_x, origin_y, global_frame)
    draw_tip_pile(mc, origin_x, origin_y, length, global_frame, is_blocked)
    draw_edge_streaks(mc, origin_x, origin_y, length, global_frame, is_blocked)
    draw_embers(mc, origin_x, origin_y, length, global_frame, is_blocked)

    mc.finish()


def build_video(out_path: Path):
    total_frames = LOOP_FRAMES * LOOP_CYCLES
    fig, ax = plt.subplots(
        figsize=(CANVAS_W_PX / 100, CANVAS_H_PX / 100),
        dpi=100,
    )
    fig.patch.set_facecolor(BG_COLOR)
    fig.subplots_adjust(left=0, right=1, top=1, bottom=0)

    def update(frame_idx):
        draw_frame(ax, frame_idx)
        return []

    anim = animation.FuncAnimation(
        fig,
        update,
        frames=total_frames,
        interval=1000 / FPS,
        blit=False,
    )

    saved_path = None
    try:
        writer = animation.FFMpegWriter(
            fps=FPS,
            bitrate=3200,
            codec="libx264",
            extra_args=["-pix_fmt", "yuv420p"],
        )
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
    out = Path(__file__).parent / "喷火束_视觉原型"
    saved = build_video(out)
    print(f"[ok] 喷火束视觉原型已生成: {saved}")
    print(
        f"     max={MAX_LENGTH}px start={START_LENGTH}px grow={GROW_SPEED}/f "
        f"retract={RETRACT_SPEED}/f blocker={BLOCKER_LENGTH}px"
    )
