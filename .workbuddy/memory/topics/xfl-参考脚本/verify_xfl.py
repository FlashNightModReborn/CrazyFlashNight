#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""反向验证：读已安装的 足球图.xml，把 edges 字符串解析回几何并渲染。

这一步验证的是「落盘内容」而不是「内存对象」：
  * 每个 DOMShape/Edge 只含一条子路径（生成时已拆开）
  * ! = 设当前点，| = 直线到，[cx cy px py = 二次贝塞尔到
  * 坐标是 twips 且做了 (-CX,-CY) 平移，渲染时还原
并顺带检查每条轮廓的绕向是否都为正（fillStyle1 的前提）。

用系统 Python310（Pillow）。一次性脚本。
"""
import os
import re
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
XFL = r"E:\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\project\CrazyFlashNight\flashswf\arts\new\瓦巴杰克\LIBRARY\特效与子弹\足球图.xml"

NS = "{http://ns.adobe.com/xadobe/xfl/2008/}"
TW = 20.0
CX, CY = 992.0 / 2.0, 1056.0 / 2.0


def _nums(s, i, n):
    out, cur = [], ""
    while i < len(s) and len(out) < n:
        c = s[i]
        if c.isdigit() or c == "-" or c == ".":
            cur += c
        elif cur:
            out.append(float(cur))
            cur = ""
        i += 1
    if cur:
        out.append(float(cur))
    return out, i


def parse_edges(s, per=6):
    """返回点序列（px，已还原平移）。"""
    pts, pt = [], None
    i = 0
    while i < len(s):
        c = s[i]
        if c == "!":
            v, i = _nums(s, i + 1, 2)
            if len(v) == 2:
                pt = (v[0] / TW + CX, v[1] / TW + CY)
                pts.append(pt)
        elif c == "|":
            v, i = _nums(s, i + 1, 2)
            if len(v) == 2:
                pt = (v[0] / TW + CX, v[1] / TW + CY)
                pts.append(pt)
        elif c == "[":
            v, i = _nums(s, i + 1, 4)
            if len(v) == 4 and pt is not None:
                q = (v[0] / TW + CX, v[1] / TW + CY)
                end = (v[2] / TW + CX, v[3] / TW + CY)
                for k in range(1, per + 1):
                    t = k / float(per)
                    u = 1.0 - t
                    pts.append((u * u * pt[0] + 2 * u * t * q[0] + t * t * end[0],
                                u * u * pt[1] + 2 * u * t * q[1] + t * t * end[1]))
                pt = end
        else:
            i += 1
    return pts


def signed_area(pts):
    s = 0.0
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return s * 0.5


def main():
    raw = open(XFL, encoding="utf-8").read()
    # 用正则按图层切块（保持文档顺序），再取每层里的 DOMShape
    layers = []
    for lm in re.finditer(r'<DOMLayer[^>]*name="([^"]*)"[^>]*>(.*?)</DOMLayer>', raw, re.S):
        lname, body = lm.group(1), lm.group(2)
        items = []
        for sm in re.finditer(r'<DOMShape>(.*?)</DOMShape>', body, re.S):
            blk = sm.group(1)
            col = re.search(r'<SolidColor color="([^"]*)"', blk)
            em = re.search(r'<Edge\b[^>]*edges="([^"]*)"', blk)
            side = re.search(r'<Edge\b([^>]*?)edges=', blk)
            if not em:
                continue
            items.append((col.group(1) if col else "#000000", em.group(1),
                          "fillStyle1" in (side.group(1) if side else "")))
        layers.append((lname, items))
    print("图层数:", len(layers), " 图层顺序:", [l[0] for l in layers])
    total = sum(len(i) for _, i in layers)
    print("DOMShape 总数:", total)

    # 绕向检查（落盘内容）
    n_neg = 0
    n_style0 = 0
    for _, items in layers:
        for c, e, s1 in items:
            if not s1:
                n_style0 += 1
            if signed_area(parse_edges(e, 2)) <= 0:
                n_neg += 1
    print("用 fillStyle0 的 Edge:", n_style0, "(应为 0)")
    print("绕向非正的轮廓:", n_neg, "(应为 0)")

    # 渲染：图层从下到上 = layers 数组倒序
    OUT = 0.5
    SS = 3
    iw, ih = int(992 * OUT * SS), int(1056 * OUT * SS)
    k = OUT * SS
    img = Image.new("RGBA", (iw, ih), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    drawn = 0
    for _, items in reversed(layers):
        for c, e, s1 in items:
            pts = [(x * k, y * k) for x, y in parse_edges(e, 6)]
            if len(pts) < 3:
                continue
            dr.polygon(pts, fill=c)
            drawn += 1
    img = img.resize((int(992 * OUT), int(1056 * OUT)), Image.LANCZOS)
    white = Image.new("RGB", img.size, (255, 255, 255))
    white.paste(img, (0, 0), img)
    white.save(os.path.join(HERE, "verify_from_xfl.png"))
    print("渲染轮廓数:", drawn, " -> verify_from_xfl.png", img.size)


if __name__ == "__main__":
    main()
