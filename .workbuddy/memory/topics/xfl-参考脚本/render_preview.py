#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""读取 gen_football_xfl.py 导出的 subpaths.json，按 SVG 顺序填充渲染，肉眼确认形象。
用系统 Python310（有 Pillow）。一次性脚本。"""
import json
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
data = json.load(open(os.path.join(HERE, "subpaths.json"), encoding="utf-8"))
W, H = data["w"], data["h"]

OUT_SCALE = 0.5      # 输出 496x528
SS = 3               # 超采样

iw, ih = int(W * OUT_SCALE * SS), int(H * OUT_SCALE * SS)
k = OUT_SCALE * SS

img = Image.new("RGBA", (iw, ih), (0, 0, 0, 0))
dr = ImageDraw.Draw(img)
n = 0
for s in data["subs"]:
    pts = [(x * k, y * k) for x, y in s["p"]]
    if len(pts) < 3:
        continue
    dr.polygon(pts, fill=s["c"])
    n += 1

img = img.resize((int(W * OUT_SCALE), int(H * OUT_SCALE)), Image.LANCZOS)

# 白底合成图（看原始形象）
white = Image.new("RGB", img.size, (255, 255, 255))
white.paste(img, (0, 0), img)
white.save(os.path.join(HERE, "preview_on_white.png"))

# 深灰底合成图（看透明区域）
dark = Image.new("RGB", img.size, (40, 44, 52))
dark.paste(img, (0, 0), img)
dark.save(os.path.join(HERE, "preview_on_dark.png"))

print("填充子路径:", n, "/", len(data["subs"]))
print("输出尺寸:", img.size)
