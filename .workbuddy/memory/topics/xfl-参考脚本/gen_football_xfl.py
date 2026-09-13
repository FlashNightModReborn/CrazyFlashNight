#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
直接编辑瓦巴杰克 XFL：为「足球」手工雷补上 4 个元件。

生成物（写入 flashswf/arts/new/瓦巴杰克/LIBRARY/特效与子弹/）：
  1) 足球图.xml     —— 足球形象本体（1192 条 path 拆成 1323 个子路径，按 SVG 顺序分 24 层）
  2) 足球.xml       —— 投掷物（照 公共素材位0/其他武器/砖 的骨架；linkage 足球）
  3) 手雷-足球.xml  —— 手持外观（照 手雷-砖；linkage 手雷-足球）
  4) 图标-足球.xml  —— 图标（照 瓦巴杰克/武器/刀剑/图标-舞；linkage 图标-足球）
并在 DOMDocument.xml 的 <symbols> 里登记 4 条 <Include>。

关键格式结论（全部来自对本库现有 XFL 的实测，见 .workbuddy/memory/topics/）：
  * <Edge fillStyle1="1" edges="..."/> 的紧凑几何：
      !x y = moveto（设当前点）   |x y = lineto   [cx cy px py = 二次贝塞尔
    每个段前重复一次 !当前点，与 CS6 自己输出的风格一致。
  * 坐标单位 twips（1px = 20twips），样本里是整数。
  * Flash 内部只用二次贝塞尔，SVG 的三次 C 必须细分（本脚本用解析误差上界判定）。
  * 填充方向：边有 fillStyle0（左）/fillStyle1（右）两侧，取哪个由轮廓绕向决定。
  * 同一帧内多个元素的先后不易判定 => 用「图层」承载顺序（图层数组第 0 项 = 最上层），
    SVG 顺序靠后的 path 放更上面的图层。

用法：
  python gen_football_xfl.py            # 只写到 tmp/足球手雷-XFL/out/ 供检查
  python gen_football_xfl.py --install  # 写进 flashswf（主文档自动备份）
"""
import json
import math
import os
import re
import shutil
import sys

ROOT = r"E:\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\project\CrazyFlashNight"
SVG_SRC = r"E:\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\project\素材\足球.svg"
XFL_DIR = os.path.join(ROOT, r"flashswf\arts\new\瓦巴杰克")
LIB_DIR = os.path.join(XFL_DIR, "LIBRARY")
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "out")

TS = 1789321558
PREFIX = "特效与子弹/"
N_LAYERS = 24

ITEM_IDS = {
    "足球图": "6f5a0101-0000f001",
    "足球": "6f5a0102-0000f002",
    "手雷-足球": "6f5a0103-0000f003",
    "图标-足球": "6f5a0104-0000f004",
}

TWIPS = 20.0
TOL_PX = 0.03
MAX_DEPTH = 20
K_MAXDEV = 0.04811252243246881

CX_PX, CY_PX = 992.0 / 2.0, 1056.0 / 2.0      # 图形中心 -> 元件注册点

SCALE_BULLET = 50.0 / 992.0
SCALE_DRESS = 30.0 / 992.0
SCALE_ICON_MASK = 22.0 / 992.0
SCALE_ICON_BIG = 0.12


# --------------------------------------------------------------- SVG 解析
def parse_svg_paths(d_text):
    subpaths, cur, cur_pt, start_pt = [], None, None, None
    for m in re.finditer(r"([MLCZmlcz])([^MLCZmlcz]*)", d_text):
        cmd = m.group(1)
        nums = [float(x) for x in re.findall(r"-?\d*\.?\d+(?:[eE][-+]?\d+)?", m.group(2))]
        if cmd in "Mm":
            for i in range(0, len(nums) - 1, 2):
                x, y = nums[i], nums[i + 1]
                if i == 0:
                    cur = [("M", (x, y))]
                    subpaths.append(cur)
                    start_pt = (x, y)
                else:
                    cur.append(("L", (x, y)))
                cur_pt = (x, y)
        elif cmd in "Ll":
            if cur is None:
                continue
            for i in range(0, len(nums) - 1, 2):
                cur.append(("L", (nums[i], nums[i + 1])))
                cur_pt = (nums[i], nums[i + 1])
        elif cmd in "Cc":
            if cur is None:
                continue
            for i in range(0, len(nums) - 5, 6):
                c1 = (nums[i], nums[i + 1])
                c2 = (nums[i + 2], nums[i + 3])
                p3 = (nums[i + 4], nums[i + 5])
                cur.append(("C", (cur_pt, c1, c2, p3)))
                cur_pt = p3
        elif cmd in "Zz":
            if cur is not None:
                cur.append(("Z",))
                cur_pt = start_pt
    return subpaths


def read_svg():
    """返回 [(color, ops), ...]，按 SVG 出现顺序；每个元素是一个子路径。"""
    with open(SVG_SRC, encoding="utf-8") as fh:
        svg = fh.read()
    out = []
    for tag in re.findall(r"<path\b([^>]*?)/>", svg):
        fm = re.search(r'fill="([^"]*)"', tag)
        dm = re.search(r'\bd="([^"]*)"', tag)
        color = (fm.group(1) if fm else "#000000").upper()
        if len(color) == 4:
            color = "#" + "".join(c * 2 for c in color[1:])
        for ops in parse_svg_paths(dm.group(1) if dm else ""):
            out.append((color, ops))
    return out


# ---------------------------------------------------------- 曲线/几何工具
def _split_cubic(p0, c1, c2, p3):
    mid = lambda a, b: ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
    m01, m12, m23 = mid(p0, c1), mid(c1, c2), mid(c2, p3)
    m012, m123 = mid(m01, m12), mid(m12, m23)
    m = mid(m012, m123)
    return (p0, m01, m012, m), (m, m123, m23, p3)


def cubic_to_quads(p0, c1, c2, p3, out, tol=TOL_PX, depth=0):
    bx = p0[0] - 3.0 * c1[0] + 3.0 * c2[0] - p3[0]
    by = p0[1] - 3.0 * c1[1] + 3.0 * c2[1] - p3[1]
    qx = (3.0 * c1[0] - p0[0] + 3.0 * c2[0] - p3[0]) / 4.0
    qy = (3.0 * c1[1] - p0[1] + 3.0 * c2[1] - p3[1]) / 4.0
    if K_MAXDEV * math.hypot(bx, by) <= tol or depth >= MAX_DEPTH:
        out.append(((qx, qy), p3))
        return
    left, right = _split_cubic(p0, c1, c2, p3)
    cubic_to_quads(*left, out, tol, depth + 1)
    cubic_to_quads(*right, out, tol, depth + 1)


def subpath_points(ops, per_seg=6):
    """采样子路径轮廓点（px），用于绕向判定与预览渲染。"""
    pts, cur = [], None
    for op in ops:
        if op[0] == "M":
            cur = op[1]
            pts.append(cur)
        elif op[0] == "L":
            cur = op[1]
            pts.append(cur)
        elif op[0] == "C":
            p0, c1, c2, p3 = op[1]
            for i in range(1, per_seg + 1):
                t = i / float(per_seg)
                u = 1.0 - t
                pts.append((
                    u * u * u * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t * t * t * p3[0],
                    u * u * u * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t * t * t * p3[1],
                ))
            cur = p3
    return pts


def signed_area(pts):
    s = 0.0
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return s * 0.5


# ------------------------------------------------------------ edges 编码
def to_tw(pt):
    x, y = pt
    return int(round((x - CX_PX) * TWIPS)), int(round((y - CY_PX) * TWIPS))


def subpath_edges(ops):
    pieces, cur = [], None
    for op in ops:
        k = op[0]
        if k == "M":
            cur = to_tw(op[1])
            pieces.append("!%d %d" % cur)
        elif k == "L":
            p = to_tw(op[1])
            pieces.append("|%d %d" % p)
            cur = p
            pieces.append("!%d %d" % cur)
        elif k == "C":
            p0, c1, c2, p3 = op[1]
            grid = []
            cubic_to_quads(p0, c1, c2, p3, grid)
            for q, end in grid:
                qq, ee = to_tw(q), to_tw(end)
                pieces.append("[%d %d %d %d" % (qq[0], qq[1], ee[0], ee[1]))
                cur = ee
                pieces.append("!%d %d" % cur)
    return "".join(pieces)


def reverse_ops(ops):
    """把子路径的走向整体反过来（M/L/C 序列倒序，三次曲线的两个控制点交换）。"""
    pts, segs = [], []
    for op in ops:
        if op[0] == "M":
            pts.append(op[1])
        elif op[0] == "L":
            pts.append(op[1])
            segs.append(("L", None, None))
        elif op[0] == "C":
            p0, c1, c2, p3 = op[1]
            segs.append(("C", c1, c2))
            pts.append(p3)
    out = [("M", pts[-1])]
    for i in range(len(segs) - 1, -1, -1):
        s = segs[i]
        a, b = pts[i], pts[i + 1]
        if s[0] == "L":
            out.append(("L", a))
        else:
            out.append(("C", (b, s[2], s[1], a)))
    return out


def normalize_ops(ops):
    """统一成顺时针走向（面积 > 0）。

    这样所有边都落在 fillStyle1（边右侧 = 轮廓内部）这一侧，只依赖
    「顺时针 + fillStyle1 = 填充内部」这一条已在库里多个元件上验证过的语义，
    不必去猜 fillStyle0 的行为。
    """
    if signed_area(subpath_points(ops)) > 0:
        return ops, False
    return reverse_ops(ops), True


def make_shape_xml(color, ops, indent):
    """一个子路径 -> 一个 DOMShape（统一顺时针 + fillStyle1）。"""
    ops, flipped = normalize_ops(ops)
    edges = subpath_edges(ops)
    i = " " * indent
    return (
        '%s<DOMShape>\n'
        '%s  <fills>\n'
        '%s    <FillStyle index="1">\n'
        '%s      <SolidColor color="%s"/>\n'
        '%s    </FillStyle>\n'
        '%s  </fills>\n'
        '%s  <edges>\n'
        '%s    <Edge fillStyle1="1" edges="%s"/>\n'
        '%s  </edges>\n'
        '%s</DOMShape>' % (i, i, i, i, color, i, i, i, i, edges, i, i)
    ), flipped


# ------------------------------------------------------------ 元件模板
def sym_item(name, body, symbol_type=None, linkage=None, item_id=None):
    a = ['xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"',
         'xmlns="http://ns.adobe.com/xfl/2008/"',
         'name="%s"' % name]
    if item_id:
        a.append('itemID="%s"' % item_id)
    if symbol_type:
        a.append('symbolType="%s"' % symbol_type)
    if linkage:
        a.append('linkageExportForAS="true"')
        a.append('linkageIdentifier="%s"' % linkage)
    a.append('lastModified="%d"' % TS)
    return ("<DOMSymbolItem %s>\n  <timeline>\n    <DOMTimeline name=\"%s\">\n      <layers>\n%s\n"
            "      </layers>\n    </DOMTimeline>\n  </timeline>\n</DOMSymbolItem>\n"
            % (" ".join(a), name.split("/")[-1], body))


def layer_xml(name, frames, color="#4F4FFF", extra="", current=False):
    cur = ' current="true" isSelected="true"' if current else ""
    return ('        <DOMLayer name="%s" color="%s"%s%s>\n'
            '          <frames>\n%s\n          </frames>\n        </DOMLayer>'
            % (name, color, extra, cur, frames))


def frame_xml(idx, elements, duration=None, key_mode="9728", name=None, script=None):
    a = ' index="%d"' % idx
    if name:
        a += ' name="%s" labelType="name"' % name
    a += ' keyMode="%s"' % key_mode
    if duration:
        a += ' duration="%d"' % duration
    out = ['            <DOMFrame%s>' % a]
    if script is not None:
        out.append('              <Actionscript>\n                <script><![CDATA[%s]]></script>\n              </Actionscript>' % script)
    if elements:
        out.append('              <elements>\n%s\n              </elements>' % elements)
    else:
        out.append('              <elements/>')
    out.append('            </DOMFrame>')
    return "\n".join(out)


def inst_xml(lib_name, name=None, matrix=None, tp=None, symbol_type=None, loop=None,
             script=None, cpx=None, cpy=None):
    a = ['libraryItemName="%s"' % lib_name]
    if name:
        a.append('name="%s"' % name)
    if cpx is not None:
        a.append('centerPoint3DX="%s"' % cpx)
    if cpy is not None:
        a.append('centerPoint3DY="%s"' % cpy)
    if symbol_type:
        a.append('symbolType="%s"' % symbol_type)
    if loop:
        a.append('loop="%s"' % loop)
    out = ['                <DOMSymbolInstance %s>' % " ".join(a)]
    if matrix:
        # 与 CS6 的输出风格一致：b/c 为 0 时省略
        a_, b_, c_, d_, tx_, ty_ = matrix
        m = ['a="%s"' % a_]
        if float(b_) != 0:
            m.append('b="%s"' % b_)
        if float(c_) != 0:
            m.append('c="%s"' % c_)
        m.append('d="%s"' % d_)
        m.append('tx="%s"' % tx_)
        m.append('ty="%s"' % ty_)
        out.append('                  <matrix>\n                    <Matrix %s/>\n                  </matrix>' % " ".join(m))
    if tp:
        out.append('                  <transformationPoint>\n                    <Point x="%s" y="%s"/>\n                  </transformationPoint>' % tp)
    else:
        out.append('                  <transformationPoint>\n                    <Point/>\n                  </transformationPoint>')
    if script:
        out.append('                  <Actionscript>\n                    <script><![CDATA[%s]]></script>\n                  </Actionscript>' % script)
    out.append('                </DOMSymbolInstance>')
    return "\n".join(out)


AREA_SCRIPT = """onClipEvent(load){
   垂直速度 = -5;
   起始Y = _parent.Z轴坐标;
   this.onEnterFrame = function()
   {
      _parent._y += 垂直速度;
      垂直速度 += _root.重力加速度;
      if(_parent._y >= 起始Y)
      {
         _parent._y = 起始Y;
         delete this.onEnterFrame;
         _parent.gotoAndPlay("消失");
      }
   };
}
"""

SPIN_SCRIPT = """onClipEvent (enterFrame) {
	this._rotation += 7;
}"""


# ------------------------------------------------------------ 足球图本体
def build_football_graphic(subs):
    """按 SVG 顺序分 N_LAYERS 个图层：SVG 靠后的内容放更上面的图层。"""
    per = int(math.ceil(len(subs) / float(N_LAYERS)))
    groups = [subs[i:i + per] for i in range(0, len(subs), per)]
    n = len(groups)

    layers = []
    n_flip = 0
    for gi in range(n):                       # gi = 0 是 SVG 最前面（最底）
        grp = groups[gi]
        parts = []
        for c, ops in grp:
            txt, fl = make_shape_xml(c, ops, 16)
            parts.append(txt)
            n_flip += 1 if fl else 0
        shapes = "\n".join(parts)
        gname = "%02d" % (gi + 1)             # 01 = 最底（白底在 01 里）
        color = ["#4F4FFF", "#FF4FFF", "#4FFF4F", "#FFFF4F", "#4FFFFF", "#FF9C4F",
                 "#C04FFF", "#4FFFC0"][gi % 8]
        layers.append((gi, layer_xml(gname, frame_xml(0, shapes, key_mode="9728"),
                                     color=color, current=(gi == n - 1))))
    # 图层数组第 0 项 = 最上层 => 倒序排列
    body = "\n".join(t for _, t in reversed(layers))
    print("  走向反转的子路径: %d / %d" % (n_flip, len(subs)))
    return sym_item(PREFIX + "足球图", body, symbol_type=None, item_id=ITEM_IDS["足球图"])


def build_bullet():
    labels = layer_xml("Labels Layer", "\n".join([
        frame_xml(0, "", duration=2),
        frame_xml(2, "", name="消失"),
    ]), color="#B00DF6", extra=' locked="true"')

    scripts = layer_xml("Script Layer", "\n".join([
        frame_xml(0, ""),
        frame_xml(1, "", script="stop();\n"),
        frame_xml(2, "", duration=3, script="\nthis.removeMovieClip();\n"),
    ]), color="#95C8F0", extra=' locked="true"')

    area = layer_xml("Layer 3", "\n".join([
        frame_xml(0, inst_xml("area40X40", name="area", script=AREA_SCRIPT,
                              cpx="-4.05", cpy="5.85",
                              matrix=("1.13389587402344", "0", "0", "0.704437255859375", "-16.45", "-6.65")),
                  duration=2),
        frame_xml(2, "", duration=9),
    ]), color="#0FBACF", extra=' outline="true" useOutlineView="true"')

    pic = layer_xml("Layer 4", "\n".join([
        frame_xml(0, inst_xml(PREFIX + "足球图", script=SPIN_SCRIPT, cpx="18.3", cpy="33.45",
                              matrix=("%.14f" % SCALE_BULLET, "0", "0", "%.14f" % SCALE_BULLET, "0", "0")),
                  duration=2),
        frame_xml(2, "", duration=9),
    ]), color="#EBC1F0", current=True)

    return sym_item(PREFIX + "足球", "\n".join([labels, scripts, area, pic]),
                    linkage="足球", item_id=ITEM_IDS["足球"])


def build_dress():
    muzzle = layer_xml("图层 4", frame_xml(0, inst_xml(
        "各种图素材等/Symbol 13", name="枪口位置", cpx="-8.6", cpy="20.1",
        matrix=("1.69486999511719", "0", "0", "1.02896118164063", "-20.9", "8"))),
        color="#FF4FFF", current=True)
    pic = layer_xml("Layer 2", frame_xml(0, inst_xml(
        PREFIX + "足球图", symbol_type="graphic", loop="loop",
        matrix=("%.14f" % SCALE_DRESS, "0", "0", "%.14f" % SCALE_DRESS, "0", "0"))),
        color="#BBC5DB")
    return sym_item(PREFIX + "手雷-足球", "\n".join([muzzle, pic]),
                    linkage="手雷-足球", item_id=ITEM_IDS["手雷-足球"])


def build_icon():
    scripts = layer_xml("Script Layer", frame_xml(0, "", script="stop();\n"), color="#B08A75")
    mask = layer_xml("Layer 3", frame_xml(0, inst_xml("武器/刀剑/阴影所用", symbol_type="graphic", loop="loop")),
                     color="#03F9C1", extra=' locked="true" layerType="mask"')
    masked = layer_xml("Layer 4", frame_xml(0, inst_xml(
        PREFIX + "足球图", symbol_type="graphic", loop="loop",
        matrix=("%.14f" % SCALE_ICON_MASK, "0", "0", "%.14f" % SCALE_ICON_MASK, "0", "0"))),
        color="#8AC92F", extra=' parentLayerIndex="1"')
    base = layer_xml("Layer 5", "\n".join([
        frame_xml(0, inst_xml("图标阴影", symbol_type="graphic", loop="loop")),
        frame_xml(1, inst_xml(PREFIX + "足球图", symbol_type="graphic", loop="loop",
                              matrix=("%.14f" % SCALE_ICON_BIG, "0", "0", "%.14f" % SCALE_ICON_BIG, "0", "0"))),
    ]), color="#5DD9C8", current=True)
    return sym_item(PREFIX + "图标-足球", "\n".join([scripts, mask, masked, base]),
                    linkage="图标-足球", item_id=ITEM_IDS["图标-足球"])


# ------------------------------------------------------------ 主文档登记
# ------------------------------------------------------------ 写出工具
def save_text(path, text, crlf=True):
    """XFL 全库是 CRLF + 无 BOM，写回必须保持一致，否则整文件 diff。"""
    if crlf:
        text = text.replace("\r\n", "\n").replace("\n", "\r\n")
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)


def updated_document():
    """在 <symbols> 末尾插入 4 条 Include；保持原文件的换行风格。"""
    path = os.path.join(XFL_DIR, "DOMDocument.xml")
    with open(path, encoding="utf-8", newline="") as fh:
        raw = fh.read()
    crlf = "\r\n" in raw
    doc = raw.replace("\r\n", "\n")
    names = ["足球图", "足球", "手雷-足球", "图标-足球"]
    for n in names:                              # 幂等：先清掉同名旧登记
        doc = re.sub(r'\n?\s*<Include href="特效与子弹/%s\.xml"[^/]*/>' % re.escape(n), "", doc)
    block = "\n".join('          <Include href="%s%s.xml" loadImmediate="false" itemID="%s" lastModified="%d"/>'
                      % (PREFIX, n, ITEM_IDS[n], TS) for n in names)
    doc = doc.replace("     </symbols>", block + "\n     </symbols>")
    return path, doc, crlf


def main():
    install = "--install" in sys.argv
    subs = read_svg()
    print("子路径总数:", len(subs), " 去重颜色:", len({c for c, _ in subs}))

    files = {
        "足球图.xml": build_football_graphic(subs),
        "足球.xml": build_bullet(),
        "手雷-足球.xml": build_dress(),
        "图标-足球.xml": build_icon(),
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    for fn, text in files.items():
        save_text(os.path.join(OUT_DIR, fn), text)
        print("  %-16s %8.1f KB" % (fn, len(text.encode("utf-8")) / 1024.0))

    doc_path, doc, crlf = updated_document()
    save_text(os.path.join(OUT_DIR, "DOMDocument.xml"), doc, crlf)
    print("  DOMDocument.xml（预览，crlf=%s）" % crlf)

    # 预览用中间数据
    preview = [{"c": c, "p": [[round(x, 2), round(y, 2)] for x, y in subpath_points(ops, 4)]}
               for c, ops in subs]
    with open(os.path.join(HERE, "subpaths.json"), "w", encoding="utf-8") as fh:
        json.dump({"w": 992, "h": 1056, "subs": preview}, fh)
    print("  subpaths.json（渲染验证用）  %d 个子路径" % len(preview))

    if install:
        bak = doc_path + ".bak-足球前"
        if not os.path.exists(bak):
            shutil.copy2(doc_path, bak)
            print("  已备份 ->", os.path.basename(bak))
        for fn, text in files.items():
            save_text(os.path.join(LIB_DIR, PREFIX, fn), text)
        save_text(doc_path, doc, crlf)
        print("  已写入 XFL 库目录 + 主文档")
    else:
        print("\n（预览模式，未改动 flashswf；加 --install 写入）")


if __name__ == "__main__":
    main()
