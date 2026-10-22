#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CF6 无车战 20 图 SVG 矢量源审计（r5，K3 线）。

只读仓库源文件；不渲染图像、不改任何源。输出写入 tmp/cf6-roguelike-20261021/kimi-maps/r5/。

用法（仓库根目录）：
  tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-source/vector-audit/audit.py
      全量 20 图，写 vector-source-index.json；每 5 图更新 progress-r5.json；
      20 图齐全后写 result-r5.md。
  ... audit.py --map A02 A03     只审指定图，结果打印到 stdout，不写文件（调试用）。
  ... audit.py --check           重算并与既有 vector-source-index.json 深比对
      （忽略 generatedAt），并核验 progress 完整与 result-r5.md 存在；不一致退出码 1。

支持矩阵基准：tools/cf6-map-runtime/native-vector/README.md（Astra A01 样板），
其文件 SHA 记录进索引头部，便于机器复核“对照哪个版本矩阵”。
"""
import argparse
import base64
import hashlib
import json
import os
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MAP_INPUT = os.path.join(ROOT, "tools", "cf6-map-source", "generated", "map-input.json")
MATRIX_README = os.path.join(ROOT, "tools", "cf6-map-runtime", "native-vector", "README.md")
DEFAULT_OUT = os.path.join(ROOT, "tmp", "cf6-roguelike-20261021", "kimi-maps", "r5")

PRIORITY_MAPS = ["A02", "A03", "A04", "A05", "A06", "A08"]
ASTRA_SAMPLE = "A01"  # Astra 独占 native-vector/ 与背景 XFL；此处仅做索引交叉核对

XLINK_HREF = "{http://www.w3.org/1999/xlink}href"
SHAPE_TAGS = ("path", "rect", "circle", "ellipse", "line", "polygon", "polyline")
DEF_KINDS = ("linearGradient", "radialGradient", "clipPath", "mask", "filter", "pattern", "symbol")
SKIP_TAGS = ("defs", "title", "desc", "metadata", "style", "script")
URL_RE = re.compile(r"url\(\s*['\"]?#([^)'\"\s]+)\s*['\"]?\)")
ARC_RE = re.compile(r"[Aa]")

# 对照 Astra native-vector 支持矩阵的特性码。
SEVERITY = {
    "FILTER": "extension-required",            # 矩阵：显式拒绝或需新增实现
    "ECCENTRIC_RADIAL": "extension-required",  # 矩阵：仅线性/居中径向
    "COLORED_LUMINANCE_MASK": "extension-required",  # 矩阵：彩色 luminance mask 拒绝
    "PATTERN": "extension-required",           # 矩阵未声明支持
    "EXTERNAL_USE": "extension-required",      # 矩阵：不支持外部 URL
    "EXTERNAL_IMAGE": "extension-required",    # 矩阵：仅原稿内嵌 base64
    "MESH_GRADIENT": "extension-required",
    "ARC_COMMAND": "verify",                   # A01 无弧线命令，legacy writer 未声明
    "TEXT_FONT_UNBOUND": "verify",             # 矩阵仅绑定 DejaVu Sans Bold
    "BLEND_MODE": "verify",                    # 矩阵仅组透明度 blendMode=layer
    "LARGE_COVERAGE_MASK": "verify-performance",  # 扫描线式 mask，原生 mask 性能未验证
    "NON_OBB_GRADIENT": "verify",              # userSpaceOnUse 渐变需坐标展开核对
}

GRAY_NAMES = {"white", "black", "gray", "grey", "lightgray", "lightgrey",
              "darkgray", "darkgrey", "dimgray", "dimgrey", "gainsboro",
              "whitesmoke", "silver"}


def rel(p):
    return os.path.relpath(p, ROOT).replace(os.sep, "/")


def local(tag):
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def now_iso():
    return datetime.now().astimezone().isoformat(timespec="seconds")


def parse_style(el):
    out = {}
    raw = el.get("style")
    if raw:
        for item in raw.split(";"):
            if ":" in item:
                k, v = item.split(":", 1)
                out[k.strip()] = v.strip()
    return out


def prop(el, st, name, default=None):
    if name in st:
        return st[name]
    v = el.get(name)
    return v if v is not None else default


def collect_url_refs(el, st):
    refs = set()
    for v in list(el.attrib.values()) + list(st.values()):
        if isinstance(v, str) and "url(" in v:
            refs.update(URL_RE.findall(v))
    return refs


def parse_color(c):
    """返回 (r,g,b) 或 None（无法解析/none/currentColor）。"""
    if not c:
        return None
    c = c.strip().lower()
    if c in ("none", "currentcolor", "inherit", "transparent"):
        return None
    if c.startswith("#"):
        h = c[1:]
        try:
            if len(h) == 3:
                return tuple(int(ch * 2, 16) for ch in h)
            if len(h) >= 6:
                return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
        except ValueError:
            return None
        return None
    m = re.match(r"rgba?\(([^)]+)\)", c)
    if m:
        try:
            parts = [float(x) for x in re.split(r"[,\s]+", m.group(1).strip()) if x][:3]
            if len(parts) == 3:
                return tuple(int(round(x)) for x in parts)
        except ValueError:
            return None
        return None
    if c in GRAY_NAMES:
        g = {"white": 255, "black": 0, "silver": 192}.get(c, 128)
        return (g, g, g)
    return None  # 其他命名色保守视为无法解析


def is_grayscale_color(c):
    rgb = parse_color(c)
    if rgb is None:
        return None  # 未知
    return rgb[0] == rgb[1] == rgb[2]


def num(v, default=None):
    if v is None:
        return default
    try:
        return float(str(v).strip().rstrip("%"))
    except ValueError:
        return default


class SvgAudit:
    """单个 SVG 的可见节点 + 被引用 defs 审计。按文件 SHA 缓存，跨图复用。"""

    def __init__(self, path):
        self.path = path
        self.data = open(path, "rb").read()
        self.sha = sha256_bytes(self.data)
        self.counts = {}
        self.group_nodes = {}
        self.id_index = {}
        self.direct_refs = {}       # def id -> set(top group labels)
        self.def_nested = {}        # def id -> set(def ids referenced inside)
        self.referenced = {}        # def id -> entry dict
        self.referrers = {}         # def id -> set(top labels)（闭包传播后）
        self.unreferenced_def_counts = {}
        self.missing_refs = []
        self.images = []
        self.texts = {"count": 0, "fonts": {}, "tspanCount": 0}
        self.arc_paths = []         # (top, d 前缀)
        self.blend_elements = []
        self.external_uses = []
        self.features = []          # {code, severity, detail, groups}
        self.group_features = {}
        self.use_cycles = []
        self.pruned_display_none = 0
        self.parse_error = None

    def add_ref(self, rid, top):
        self.direct_refs.setdefault(rid, set()).add(top or "(ungrouped)")

    def add_feature(self, code, detail, top=None, groups=None):
        g = sorted(groups) if groups else ([top] if top else [])
        self.features.append({"code": code, "severity": SEVERITY.get(code, "verify"),
                              "detail": detail, "groups": g})
        for lbl in g:
            self.group_features.setdefault(lbl, set()).add(code)

    def run(self):
        try:
            root = ET.fromstring(self.data)
        except ET.ParseError as e:
            self.parse_error = str(e)
            return self
        self.root = root
        for el in root.iter():
            eid = el.get("id")
            if eid:
                self.id_index[eid] = el
        self.viewBox = root.get("viewBox")
        self.width_attr = root.get("width")
        self.height_attr = root.get("height")

        # 顶层组：剥开单子节点包装组（最多 3 层），其孩子作为分件粒度。
        peel = root
        for _ in range(3):
            kids = [c for c in peel if local(c.tag) not in SKIP_TAGS + DEF_KINDS]
            if len(kids) == 1 and local(kids[0].tag) == "g":
                peel = kids[0]
            else:
                break
        tops = [c for c in peel if local(c.tag) not in SKIP_TAGS + DEF_KINDS]
        self.top_labels = {}
        for i, c in enumerate(tops):
            lbl = c.get("id") or "%s#%d" % (local(c.tag), i)
            self.top_labels[lbl] = c
            self.group_nodes.setdefault(lbl, 0)

        # peel 之上的包装组也计数并收集引用（归属记为 (ungrouped)）
        node = root
        while node is not peel:
            tag = local(node.tag)
            if tag in SHAPE_TAGS or tag in ("g", "use", "image", "text", "switch"):
                self.counts[tag] = self.counts.get(tag, 0) + 1
            for rid in collect_url_refs(node, parse_style(node)):
                self.add_ref(rid, None)
            kids = [c for c in node if local(c.tag) not in SKIP_TAGS + DEF_KINDS]
            node = kids[0] if (len(kids) == 1 and local(kids[0].tag) == "g") else peel

        for c in tops:
            lbl = c.get("id") or "%s#%d" % (local(c.tag), tops.index(c))
            self.visit(c, False, lbl, [])

        self.resolve_defs()
        self.propagate_referrers()
        self.classify_def_features()
        self.count_unreferenced_defs()
        return self

    # ---- 可见树遍历 ----
    def hidden_state(self, el, st, inherited):
        disp = prop(el, st, "display")
        if disp == "none":
            return "prune"
        vis = prop(el, st, "visibility")
        h = inherited
        if vis in ("hidden", "collapse"):
            h = True
        elif vis == "visible":
            h = False
        return h

    def visit(self, el, vis_hidden, top, inst_stack):
        tag = local(el.tag)
        if tag in SKIP_TAGS or tag in DEF_KINDS:
            return
        st = parse_style(el)
        hh = self.hidden_state(el, st, vis_hidden)
        if hh == "prune":
            self.pruned_display_none += 1
            return
        if not hh:
            if tag in SHAPE_TAGS or tag in ("use", "image", "text", "g", "switch"):
                self.counts[tag] = self.counts.get(tag, 0) + 1
                if top:
                    self.group_nodes[top] = self.group_nodes.get(top, 0) + 1
            for rid in collect_url_refs(el, st):
                self.add_ref(rid, top)
            blend = st.get("mix-blend-mode") or el.get("mix-blend-mode")
            if blend and blend != "normal":
                self.blend_elements.append({"top": top, "mode": blend})
            if tag == "path":
                d = el.get("d") or ""
                arcs = len(ARC_RE.findall(d))
                if arcs:
                    self.arc_paths.append({"top": top, "arcCommands": arcs})
            elif tag == "use":
                self.handle_use(el, hh, top, inst_stack)
            elif tag == "image":
                self.handle_image(el, top)
            elif tag == "text":
                self.handle_text(el, st)
        for c in el:
            self.visit(c, hh, top, inst_stack)

    def handle_use(self, el, vis_hidden, top, inst_stack):
        href = el.get("href") or el.get(XLINK_HREF)
        if not href:
            return
        if not href.startswith("#"):
            self.external_uses.append({"top": top, "href": href[:200]})
            return
        rid = href[1:]
        self.add_ref(rid, top)
        if rid in inst_stack:
            self.use_cycles.append(rid)
            return
        target = self.id_index.get(rid)
        if target is None:
            self.missing_refs.append(rid)
            return
        before = sum(self.counts.get(t, 0) for t in SHAPE_TAGS) + self.counts.get("g", 0)
        ttag = local(target.tag)
        if ttag in SHAPE_TAGS or ttag in ("g", "switch", "svg", "symbol"):
            self.counts[ttag if ttag in SHAPE_TAGS else "g"] = \
                self.counts.get(ttag if ttag in SHAPE_TAGS else "g", 0) + 1
            if top:
                self.group_nodes[top] = self.group_nodes.get(top, 0) + 1
            for rid2 in collect_url_refs(target, parse_style(target)):
                self.add_ref(rid2, top)
            for c in target:
                self.visit(c, vis_hidden, top, inst_stack + [rid])
        after = sum(self.counts.get(t, 0) for t in SHAPE_TAGS) + self.counts.get("g", 0)
        self.counts["useExpandedElements"] = self.counts.get("useExpandedElements", 0) + (after - before) + 1

    def handle_image(self, el, top):
        href = el.get("href") or el.get(XLINK_HREF) or ""
        entry = {"top": top, "x": el.get("x"), "y": el.get("y"),
                 "width": el.get("width"), "height": el.get("height")}
        entry.update(self.decode_image_href(href, top))
        if entry["hrefType"] == "external-file":
            self.add_feature("EXTERNAL_IMAGE", "外部图片引用 %s" % href[:80], top)
        self.images.append(entry)

    def handle_text(self, el, st):
        self.texts["count"] += 1
        font = prop(el, st, "font-family", "(default)")
        chars = len("".join(el.itertext()))
        f = self.texts["fonts"].setdefault(font, {"textElements": 0, "chars": 0})
        f["textElements"] += 1
        f["chars"] += chars
        self.texts["tspanCount"] += sum(1 for c in el.iter() if local(c.tag) == "tspan")

    # ---- defs 引用闭包 ----
    def resolve_defs(self):
        queue = [(rid, tops) for rid, tops in self.direct_refs.items()]
        seen_pairs = set()
        while queue:
            rid, tops = queue.pop()
            key = (rid, tuple(sorted(tops)))
            if key in seen_pairs:
                continue
            seen_pairs.add(key)
            el = self.id_index.get(rid)
            if el is None:
                if rid not in self.missing_refs:
                    self.missing_refs.append(rid)
                continue
            if rid in self.referenced:
                continue
            kind = local(el.tag)
            entry, nested = self.process_def(rid, el, kind)
            self.referenced[rid] = entry
            self.def_nested[rid] = nested
            for n in nested:
                self.direct_refs.setdefault(n, set()).update(tops)
                queue.append((n, set(tops)))

    def propagate_referrers(self):
        ref_map = {k: set(v) for k, v in self.direct_refs.items()}
        changed = True
        rounds = 0
        while changed and rounds < 20:
            changed = False
            rounds += 1
            for rid, nested in self.def_nested.items():
                for n in nested:
                    before = len(ref_map.get(n, ()))
                    ref_map.setdefault(n, set()).update(ref_map.get(rid, ()))
                    if len(ref_map[n]) != before:
                        changed = True
        self.referrers = ref_map

    def process_def(self, rid, el, kind):
        entry = {"id": rid, "kind": kind}
        nested = set()
        for sub in el.iter():
            nested.update(collect_url_refs(sub, parse_style(sub)))
            h = sub.get("href") or sub.get(XLINK_HREF)
            if h and h.startswith("#"):
                nested.add(h[1:])
        nested.discard(rid)
        if kind in ("linearGradient", "radialGradient"):
            entry.update(self.gradient_info(el))
        elif kind == "filter":
            entry["filterUnits"] = el.get("filterUnits", "objectBoundingBox")
            entry["region"] = {k: el.get(k) for k in ("x", "y", "width", "height")}
            prims = []
            for c in el:
                ck = local(c.tag)
                attrs = {local(k): (v[:160] if isinstance(v, str) else v)
                         for k, v in c.attrib.items() if local(k) != "id"}
                prims.append({"kind": ck, "attrs": attrs})
            entry["primitives"] = prims
        elif kind == "mask":
            entry.update(self.mask_info(el))
        elif kind == "clipPath":
            entry["clipPathUnits"] = el.get("clipPathUnits", "userSpaceOnUse")
            shapes = [local(c.tag) for c in el.iter()
                      if local(c.tag) in SHAPE_TAGS + ("text", "use")]
            entry["shapeCount"] = len(shapes)
            entry["shapeKinds"] = sorted(set(shapes))
            entry["hasText"] = "text" in shapes
        elif kind == "pattern":
            entry["patternUnits"] = el.get("patternUnits", "objectBoundingBox")
            entry["patternContentUnits"] = el.get("patternContentUnits", "userSpaceOnUse")
            entry["tile"] = {"width": el.get("width"), "height": el.get("height")}
            kids = [c for c in el]
            entry["childCount"] = len(kids)
            entry["childKinds"] = sorted({local(c.tag) for c in kids})
            pimages = []
            for c in el.iter():
                if local(c.tag) == "image":
                    pimages.append(self.decode_image_href(
                        c.get("href") or c.get(XLINK_HREF) or ""))
            if pimages:
                entry["images"] = pimages
                if len(kids) == 1 and local(kids[0].tag) == "image":
                    entry["note"] = ("单 image 平铺 = 原作者程序纹理位图填充；"
                                     "纹理字节可走 CS6 原生导入，pattern 填充语义本身需新增实现"
                                     "（或等效位图填充），不自动整层转 PNG")
        elif kind == "symbol":
            entry["childCount"] = sum(1 for _ in el.iter()) - 1
        return entry, nested

    def decode_image_href(self, href, top=None):
        entry = {"hrefType": None, "role": "original-author-embedded"}
        if href.startswith("data:"):
            header, _, payload = href.partition(",")
            entry["hrefType"] = "data-uri"
            entry["mime"] = header[5:].split(";")[0] or "text/plain"
            if ";base64" in header:
                try:
                    raw = base64.b64decode(payload, validate=False)
                except Exception:
                    raw = b""
                    entry["decodeError"] = True
            else:
                raw = urllib.parse.unquote_to_bytes(payload)
            entry["decodedBytes"] = len(raw)
            if raw:
                entry["decodedSha256"] = sha256_bytes(raw)
        else:
            entry["hrefType"] = "external-file"
            entry["href"] = href[:200]
        return entry

    def gradient_stops(self, el, depth=0):
        stops = []
        href = el.get("href") or el.get(XLINK_HREF)
        if href and href.startswith("#") and depth < 5:
            base = self.id_index.get(href[1:])
            if base is not None:
                stops = self.gradient_stops(base, depth + 1)
        own = []
        for s in el:
            if local(s.tag) != "stop":
                continue
            st = parse_style(s)
            color = prop(s, st, "stop-color", "black")
            own.append({"offset": s.get("offset", "0"), "color": color,
                        "opacity": prop(s, st, "stop-opacity")})
        return own or stops

    def gradient_info(self, el):
        units = el.get("gradientUnits")
        if units is None:
            # 生成器有用 objectBoundingBox="true" 非标准属性的习惯
            units = "objectBoundingBox" if el.get("objectBoundingBox") in ("true", "1") \
                else "objectBoundingBox"
        info = {"gradientUnits": units,
                "transform": el.get("gradientTransform"),
                "spreadMethod": el.get("spreadMethod", "pad")}
        stops = self.gradient_stops(el)
        info["stopCount"] = len(stops)
        info["hasAlphaStops"] = any(s["opacity"] not in (None, "1", "1.0") for s in stops)
        gray = set()
        for s in stops:
            g = is_grayscale_color(s["color"])
            gray.add(g)
        info["stopsGrayscale"] = (False if False in gray else (True if gray == {True} else None))
        info["stops"] = stops[:24]
        if local(el.tag) == "radialGradient":
            cx, cy = el.get("cx"), el.get("cy")
            fx, fy = el.get("fx"), el.get("fy")
            info.update({"cx": cx or "50%", "cy": cy or "50%", "r": el.get("r") or "50%"})
            if fx is not None or fy is not None:
                fxv = num(fx, num(cx, 50.0))
                fyv = num(fy, num(cy, 50.0))
                info["fx"], info["fy"] = fx, fy
                info["eccentric"] = abs(fxv - num(cx, 50.0)) > 1e-6 or \
                                    abs(fyv - num(cy, 50.0)) > 1e-6
            else:
                info["eccentric"] = False
            if units == "objectBoundingBox":
                cxc, cyc = num(cx, 50.0), num(cy, 50.0)
                info["centered"] = abs(cxc - 50.0) <= 1e-6 and abs(cyc - 50.0) <= 1e-6
            else:
                # userSpaceOnUse 的 cx/cy 是用户坐标，无“50%,50% 居中”语义；
                # 由 NON_OBB_GRADIENT(verify) 覆盖，不算偏心
                info["centered"] = None
        return info

    def mask_info(self, el):
        st = parse_style(el)
        mtype = prop(el, st, "mask-type", "luminance")
        info = {"maskUnits": el.get("maskUnits", "objectBoundingBox"),
                "maskContentUnits": el.get("maskContentUnits", "userSpaceOnUse"),
                "maskType": mtype}
        fills = []
        shape_count = 0
        subpath_total = 0
        d_bytes = 0
        for sub in el.iter():
            if local(sub.tag) in SHAPE_TAGS:
                shape_count += 1
                sst = parse_style(sub)
                fill = prop(sub, sst, "fill", "black")
                fills.append(fill[:60])
                d = sub.get("d")
                if d:
                    subpath_total += len(re.findall(r"[Mm]", d))
                    d_bytes += len(d)
        info["shapeCount"] = shape_count
        info["subpathCount"] = subpath_total
        info["pathDataBytes"] = d_bytes
        info["distinctFills"] = sorted(set(fills))[:20]
        # 灰阶判定：纯色直接判；url(#grad) 取渐变 stop。
        gray_votes = set()
        for f in set(fills):
            if f.startswith("url("):
                m = URL_RE.search(f)
                if m:
                    gel = self.id_index.get(m.group(1))
                    if gel is not None and local(gel.tag) in ("linearGradient", "radialGradient"):
                        for s in self.gradient_stops(gel):
                            gray_votes.add(is_grayscale_color(s["color"]))
                        continue
                gray_votes.add(None)
            else:
                gray_votes.add(is_grayscale_color(f))
        if mtype == "alpha":
            info["classification"] = "alpha"
        elif False in gray_votes:
            info["classification"] = "luminance-colored"
        elif gray_votes and None not in gray_votes:
            info["classification"] = "luminance-grayscale"
        else:
            info["classification"] = "luminance-unknown"
        return info

    def classify_def_features(self):
        for rid, entry in self.referenced.items():
            groups = sorted(self.referrers.get(rid, ()))
            kind = entry["kind"]
            if kind == "radialGradient":
                if entry.get("eccentric"):
                    self.add_feature("ECCENTRIC_RADIAL",
                                     "radialGradient %s fx/fy 偏离圆心" % rid, groups=groups)
                elif entry.get("centered") is False:
                    self.add_feature("ECCENTRIC_RADIAL",
                                     "radialGradient %s objectBoundingBox 圆心非 50%%,50%%" % rid,
                                     groups=groups)
                if entry.get("gradientUnits") == "userSpaceOnUse":
                    self.add_feature("NON_OBB_GRADIENT",
                                     "radialGradient %s userSpaceOnUse" % rid, groups=groups)
            elif kind == "linearGradient" and entry.get("gradientUnits") == "userSpaceOnUse":
                self.add_feature("NON_OBB_GRADIENT",
                                 "linearGradient %s userSpaceOnUse" % rid, groups=groups)
            elif kind == "filter":
                kinds = [p["kind"] for p in entry.get("primitives", [])]
                self.add_feature("FILTER", "filter %s: %s" % (rid, ",".join(kinds)), groups=groups)
            elif kind == "mask":
                cls = entry.get("classification")
                if cls == "luminance-colored":
                    self.add_feature("COLORED_LUMINANCE_MASK",
                                     "mask %s 彩色 luminance" % rid, groups=groups)
                if entry.get("shapeCount", 0) > 500 or entry.get("subpathCount", 0) > 500:
                    self.add_feature("LARGE_COVERAGE_MASK",
                                     "mask %s 含 %d 形状/%d 子路径（扫描线式覆盖，原生 mask 性能未验证）"
                                     % (rid, entry.get("shapeCount", 0), entry.get("subpathCount", 0)),
                                     groups=groups)
            elif kind == "pattern":
                self.add_feature("PATTERN", "pattern %s" % rid, groups=groups)
            elif kind in ("meshgradient", "mesh"):
                self.add_feature("MESH_GRADIENT", "mesh %s" % rid, groups=groups)
        for eu in self.external_uses:
            self.add_feature("EXTERNAL_USE", "外部 use %s" % eu["href"][:80], top=eu["top"])
        arc_by_group = {}
        for a in self.arc_paths:
            arc_by_group[a["top"]] = arc_by_group.get(a["top"], 0) + a["arcCommands"]
        for g, n in sorted(arc_by_group.items(), key=lambda kv: str(kv[0])):
            self.add_feature("ARC_COMMAND", "路径含 %d 个弧线命令" % n, top=g)
        for font in self.texts["fonts"]:
            if "dejavu" not in font.lower() and font != "(default)":
                self.add_feature("TEXT_FONT_UNBOUND", "字体 %s 未绑定" % font)
        for b in self.blend_elements:
            self.add_feature("BLEND_MODE", "mix-blend-mode %s" % b["mode"], top=b["top"])

    def count_unreferenced_defs(self):
        for eid, el in self.id_index.items():
            kind = local(el.tag)
            if kind in DEF_KINDS and eid not in self.referenced:
                self.unreferenced_def_counts[kind] = \
                    self.unreferenced_def_counts.get(kind, 0) + 1

    def summary(self):
        ref_counts = {}
        other_ref = 0
        for e in self.referenced.values():
            if e["kind"] in DEF_KINDS:
                ref_counts[e["kind"]] = ref_counts.get(e["kind"], 0) + 1
            else:
                other_ref += 1  # use 指向的普通 g/形状等实例化目标
        visible = {t: self.counts.get(t, 0) for t in
                   SHAPE_TAGS + ("use", "image", "text", "g") if self.counts.get(t)}
        if self.counts.get("useExpandedElements"):
            visible["useExpandedElements"] = self.counts["useExpandedElements"]
        extension = sorted({f["code"] for f in self.features
                            if f["severity"] == "extension-required"})
        verify = sorted({f["code"] for f in self.features
                         if f["severity"] != "extension-required"})
        ext_groups = sorted({g for f in self.features
                             if f["severity"] == "extension-required" for g in f["groups"]})
        ready_groups = [g for g in sorted(self.group_nodes) if g not in ext_groups]
        return {
            "path": rel(self.path),
            "sha256": self.sha,
            "bytes": len(self.data),
            "viewBox": self.viewBox,
            "widthAttr": self.width_attr,
            "heightAttr": self.height_attr,
            "parseError": self.parse_error,
            "visibleCounts": visible,
            "referencedDefs": {
                "counts": ref_counts,
                "useTargetElements": other_ref,
                "gradients": sorted((e for e in self.referenced.values()
                                     if e["kind"] in ("linearGradient", "radialGradient")),
                                    key=lambda e: e["id"]),
                "clipPaths": sorted((e for e in self.referenced.values() if e["kind"] == "clipPath"),
                                    key=lambda e: e["id"]),
                "masks": sorted((e for e in self.referenced.values() if e["kind"] == "mask"),
                                key=lambda e: e["id"]),
                "filters": sorted((e for e in self.referenced.values() if e["kind"] == "filter"),
                                  key=lambda e: e["id"]),
                "patterns": sorted((e for e in self.referenced.values() if e["kind"] == "pattern"),
                                   key=lambda e: e["id"]),
            },
            "unreferencedDefCounts": self.unreferenced_def_counts,
            "missingRefs": sorted(set(self.missing_refs)),
            "useCycles": sorted(set(self.use_cycles)),
            "images": self.images,
            "texts": self.texts,
            "prunedDisplayNone": self.pruned_display_none,
            "features": sorted(self.features,
                               key=lambda f: (f["severity"], f["code"], f["detail"], f["groups"])),
            "extensionRequiredCodes": extension,
            "verifyCodes": verify,
            "topGroups": [{"id": g, "visibleNodes": self.group_nodes.get(g, 0),
                           "features": sorted(self.group_features.get(g, ()))}
                          for g in sorted(self.group_nodes)],
            "nativeReadyGroups": ready_groups,
            "extensionGroups": ext_groups,
        }


_audit_cache = {}


def audit_svg_cached(path):
    sha = sha256_file(path)
    if sha in _audit_cache:
        return _audit_cache[sha]
    a = SvgAudit(path).run().summary()
    _audit_cache[sha] = a
    return a


def png_info(path):
    if not os.path.isfile(path):
        return {"path": rel(path), "exists": False}
    return {"path": rel(path), "exists": True, "sha256": sha256_file(path),
            "bytes": os.path.getsize(path),
            "role": "whole-layer-baked-raster-baseline"}


NON_PRODUCTION_MARKERS = ("preview", "panorama", "/reference/")


def collect_map_svgs(node, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if k in ("svg", "partsSvg"):
                if isinstance(v, str) and v.endswith(".svg"):
                    out.add(v)
                elif isinstance(v, list):
                    out.update(x for x in v if isinstance(x, str) and x.endswith(".svg"))
            else:
                collect_map_svgs(v, out)
    elif isinstance(node, list):
        for i in node:
            collect_map_svgs(i, out)


def audit_layer(layer):
    src = layer.get("source") or {}
    svg_rel = src.get("svg")
    entry = {
        "id": layer.get("id"),
        "role": layer.get("role"),
        "sourceKind": layer.get("sourceKind"),
        "placement": {k: layer.get(k) for k in
                      ("x", "y", "width", "height", "depth", "pixelSize",
                       "clip", "loopHeight") if layer.get(k) is not None},
        "png": png_info(os.path.join(ROOT, layer["png"])) if layer.get("png") else None,
        "registration": {k: v for k, v in src.items() if k not in ("svg", "partsSvg")},
        "registrationBasis": layer.get("basis"),
    }
    if svg_rel and svg_rel.endswith(".svg"):
        svg_abs = os.path.join(ROOT, svg_rel.replace("/", os.sep))
        if not os.path.isfile(svg_abs):
            entry["sourceSVG"] = {"path": svg_rel, "exists": False}
        else:
            a = audit_svg_cached(svg_abs)
            entry["sourceSVG"] = a
            low = svg_rel.lower()
            entry["productionSource"] = not any(m in low for m in NON_PRODUCTION_MARKERS)
            def_ids = [e["id"]
                       for k in ("gradients", "clipPaths", "masks", "filters", "patterns")
                       for e in a["referencedDefs"][k]]
            img_sha = {im.get("decodedSha256") for im in a["images"]
                       if im.get("decodedSha256")}
            for pat in a["referencedDefs"]["patterns"]:
                for im in pat.get("images", []):
                    if im.get("decodedSha256"):
                        img_sha.add(im["decodedSha256"])
            entry["dependencyClosure"] = {
                "internalDefIds": sorted(def_ids),
                "embeddedImageSha": sorted(img_sha),
                "externalRefs": [im["href"] for im in a["images"]
                                 if im["hrefType"] == "external-file"] +
                                [f["detail"] for f in a["features"]
                                 if f["code"] == "EXTERNAL_USE"],
                "partsSvg": [],
            }
            parts = []
            for p in src.get("partsSvg") or []:
                pabs = os.path.join(ROOT, p.replace("/", os.sep))
                if os.path.isfile(pabs):
                    pa = audit_svg_cached(pabs)
                    parts.append({"path": p, "sha256": pa["sha256"],
                                  "bytes": pa["bytes"], "viewBox": pa["viewBox"],
                                  "visibleCounts": pa["visibleCounts"],
                                  "extensionRequiredCodes": pa["extensionRequiredCodes"]})
                else:
                    parts.append({"path": p, "exists": False})
            entry["dependencyClosure"]["partsSvg"] = parts
    else:
        entry["sourceSVG"] = {"path": svg_rel, "exists": False,
                              "note": "非文件引用（见 deferredLayers/notes）"}
        entry["productionSource"] = False
    return entry


def audit_map(mid, mdef):
    consumed = set()
    collect_map_svgs(mdef, consumed)
    layers = [audit_layer(l) for l in mdef.get("layers", [])]
    props = []
    for p in mdef.get("props") or []:
        svg_rel = p.get("svg")
        pe = {"id": p.get("id"), "kind": p.get("kind"), "role": "prop-dynamic",
              "instances": p.get("instances"), "frames": p.get("frames"),
              "registration": p.get("registration")}
        if svg_rel:
            pabs = os.path.join(ROOT, svg_rel.replace("/", os.sep))
            if os.path.isfile(pabs):
                pe["svg"] = audit_svg_cached(pabs)
            else:
                pe["svg"] = {"path": svg_rel, "exists": False}
        props.append(pe)
    # proposed 未接入：包内 parts/ 下盘上存在但未进 map-input 的 SVG
    pkg = (mdef.get("package") or "").rstrip("/")
    proposed = []
    pkg_abs = os.path.join(ROOT, pkg.replace("/", os.sep))
    parts_dir = os.path.join(pkg_abs, "parts")
    if os.path.isdir(parts_dir):
        for name in sorted(os.listdir(parts_dir)):
            if not name.endswith(".svg"):
                continue
            relp = "%s/parts/%s" % (pkg, name)
            if relp in consumed:
                continue
            pabs = os.path.join(parts_dir, name)
            pa = audit_svg_cached(pabs)
            proposed.append({"path": relp, "sha256": pa["sha256"], "bytes": pa["bytes"],
                             "viewBox": pa["viewBox"],
                             "visibleCounts": pa["visibleCounts"],
                             "extensionRequiredCodes": pa["extensionRequiredCodes"],
                             "status": "proposed-not-wired",
                             "note": "盘上 parts/ 存在但未接入 map-input；不伪装已消费"})
    return {
        "id": mid,
        "stage": mdef.get("stage"),
        "revision": mdef.get("revision"),
        "package": pkg,
        "nativeBounds": mdef.get("nativeBounds"),
        "priority": mid in PRIORITY_MAPS,
        "owner": "astra-native-sample(仅交叉核对)" if mid == ASTRA_SAMPLE else "k3-audit",
        "layers": layers,
        "propsDynamics": props,
        "deferredLayers": mdef.get("deferredLayers") or [],
        "proposedNotWired": proposed,
        "notes": mdef.get("notes"),
    }


def build_index(map_ids=None, write=False):
    with open(MAP_INPUT, encoding="utf-8") as f:
        mi = json.load(f)
    order = [m for m in PRIORITY_MAPS if m in mi["maps"]]
    order += [m for m in mi["maps"] if m not in order and m != ASTRA_SAMPLE]
    order += [ASTRA_SAMPLE] if ASTRA_SAMPLE in mi["maps"] else []
    if map_ids:
        order = [m for m in order if m in map_ids]
    index = {
        "schema": "cf6-vector-source-index.v1",
        "generatedAt": now_iso(),
        "generator": "tools/cf6-map-source/vector-audit/audit.py",
        "mapInput": {"path": rel(MAP_INPUT), "sha256": sha256_file(MAP_INPUT),
                     "generatedAt": mi.get("generatedAt")},
        "supportMatrix": {"path": rel(MATRIX_README), "sha256": sha256_file(MATRIX_README),
                          "note": "Astra A01 native-vector 支持矩阵；unsupported 判定基准"},
        "severityLegend": SEVERITY,
        "coordinateSpace": mi.get("coordinateSpace"),
        "maps": {},
    }
    done = []
    for i, mid in enumerate(order, 1):
        index["maps"][mid] = audit_map(mid, mi["maps"][mid])
        done.append(mid)
        if write and not map_ids and (i % 5 == 0 or i == len(order)):
            write_progress(done, [m for m in order if m not in done])
    return index


def write_progress(done, remaining):
    os.makedirs(DEFAULT_OUT, exist_ok=True)
    prog = {
        "schema": "cf6-vector-audit-progress.v1",
        "updatedAt": now_iso(),
        "total": len(done) + len(remaining),
        "completed": done,
        "remaining": remaining,
        "status": "complete" if not remaining else "running",
    }
    out = os.path.join(DEFAULT_OUT, "progress-r5.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(prog, f, ensure_ascii=False, indent=1)
    print("[progress] %d/%d -> %s" % (len(done), prog["total"], rel(out)))


def strip_ts(o):
    if isinstance(o, dict):
        return {k: strip_ts(v) for k, v in o.items() if k not in ("generatedAt", "updatedAt")}
    if isinstance(o, list):
        return [strip_ts(x) for x in o]
    return o


def cmd_check():
    fresh = build_index()
    path = os.path.join(DEFAULT_OUT, "vector-source-index.json")
    ok = True
    if not os.path.isfile(path):
        print("[check] 缺少 %s" % rel(path))
        ok = False
    else:
        with open(path, encoding="utf-8") as f:
            old = json.load(f)
        if strip_ts(old) != strip_ts(fresh):
            print("[check] vector-source-index.json 与当前源重算结果不一致")
            old_maps = strip_ts(old).get("maps", {})
            new_maps = strip_ts(fresh).get("maps", {})
            for mid in sorted(set(old_maps) | set(new_maps)):
                if old_maps.get(mid) != new_maps.get(mid):
                    print("[check]   差异图: %s" % mid)
            ok = False
        else:
            print("[check] vector-source-index.json 与重算一致（20 图源 SHA/特性均匹配）")
    prog_path = os.path.join(DEFAULT_OUT, "progress-r5.json")
    if os.path.isfile(prog_path):
        with open(prog_path, encoding="utf-8") as f:
            prog = json.load(f)
        if prog.get("status") != "complete" or len(prog.get("completed", [])) != 20:
            print("[check] progress-r5.json 未完整")
            ok = False
    else:
        print("[check] 缺少 progress-r5.json")
        ok = False
    if not os.path.isfile(os.path.join(DEFAULT_OUT, "result-r5.md")):
        print("[check] 缺少 result-r5.md")
        ok = False
    print("[check] %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description="CF6 20 图 SVG 矢量源审计（只读源，输出 r5）")
    ap.add_argument("--map", nargs="+", help="只审指定图（打印 stdout，不写文件）")
    ap.add_argument("--check", action="store_true", help="重算并与既有索引比对")
    args = ap.parse_args()
    if args.check:
        sys.exit(cmd_check())
    index = build_index(args.map, write=not args.map)
    if args.map:
        json.dump(index, sys.stdout, ensure_ascii=False, indent=1)
        return
    os.makedirs(DEFAULT_OUT, exist_ok=True)
    out = os.path.join(DEFAULT_OUT, "vector-source-index.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=1, sort_keys=True)
    print("[index] %s (%d maps)" % (rel(out), len(index["maps"])))
    write_result_md(index)
    print("[done] result-r5.md 已写；复核用 --check")


def write_result_md(index):
    """20 图齐全后生成 result-r5.md（机器可重跑派生，非手签结论）。"""
    L = []
    A = L.append
    A("# CF6 无车战 20 图矢量源审计结果（r5 / K3 线）")
    A("")
    A("- 生成时间：%s（本机真实时间）" % now_iso())
    A("- 生成命令：`tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-source/vector-audit/audit.py`（Git Bash 执行，UTF-8）")
    A("- 复核命令：同一命令加 `--check`，与 `vector-source-index.json` 深比对（忽略时间戳）")
    A("- 输入：`%s`（SHA `%s`）" % (index["mapInput"]["path"], index["mapInput"]["sha256"][:16]))
    A("- 支持矩阵基准：`%s`（SHA `%s`）" % (index["supportMatrix"]["path"], index["supportMatrix"]["sha256"][:16]))
    A("- 边界：本审计只读 SVG/PNG 源，未渲染图像、未动 CS6/游戏、未改任何源文件；"
      "`tools/cf6-map-runtime/`（Astra 独占）仅以 README 作为矩阵基准读取。")
    A("")
    A("## 结论读法")
    A("")
    A("- `extension-required`：对照 Astra A01 矩阵需新增实现的特性，已定位到具体 defs 与顶层组，"
      "**不据此判全图不可矢量**；同层其余组仍在 `nativeReadyGroups`。")
    A("- `verify` / `verify-performance`：矩阵未声明但可能可走原生（弧线、非 DejaVu 字体、"
      "userSpaceOnUse 渐变、扫描线大 mask 性能）。")
    A("- 原稿内嵌 `data:` 图片 = 原作者程序纹理（走 A01 同款“base64 解码原字节 → CS6 原生导入”路径）；"
      "map-input 的 `layer.png` = 我们此前新增的整层 baked 对照位图，两者来源与用途不同，"
      "baked 只作对照基线，不代签矢量转换。")
    A("")
    for mid, m in index["maps"].items():
        A("## %s（%s，rev %s）%s" % (mid, m["id"], m["revision"],
                                     "〔优先〕" if m["priority"] else ""))
        if m["owner"].startswith("astra"):
            A("- A01 为 Astra 原生矢量样板，本行仅为交叉核对，不重复施工。")
        A("- 包：`%s`；nativeBounds=%s" % (m["package"], m["nativeBounds"]))
        for l in m["layers"]:
            s = l.get("sourceSVG") or {}
            if not s.get("viewBox") and not s.get("sha256"):
                A("- 层 `%s`（%s）：%s" % (l["id"], l["role"], s.get("note") or "无 SVG"))
                continue
            vc = s.get("visibleCounts", {})
            vsum = " ".join("%s=%d" % (k, v) for k, v in sorted(vc.items()))
            reg = l.get("registration") or {}
            regkeys = {k: reg[k] for k in ("matrix", "rootWorldMatrix", "placementInGameworld",
                                           "viewBox", "matrixSpace", "rootPlacement") if k in reg}
            A("- 层 `%s`（%s/%s，depth %s）：`%s`" % (
                l["id"], l["role"], l["sourceKind"],
                (l.get("placement") or {}).get("depth"), s.get("path")))
            A("  - viewBox `%s`，SHA `%s`，可见节点：%s" % (s.get("viewBox"), s.get("sha256", "")[:16], vsum or "(空)"))
            A("  - 世界注册：%s；依据：%s" % (json.dumps(regkeys, ensure_ascii=False),
                                             (l.get("registrationBasis") or "")[:120]))
            rd = s.get("referencedDefs", {})
            dsum = {k: len(rd.get(k, [])) for k in
                    ("gradients", "clipPaths", "masks", "filters", "patterns")}
            A("  - 引用 defs：%s；未引用 defs 另计：%s" % (
                json.dumps(dsum), json.dumps(s.get("unreferencedDefCounts", {}))))
            for f in rd.get("filters", []):
                prims = ", ".join("%s%s" % (p["kind"],
                                            "(%s)" % p["attrs"].get("stdDeviation") if p["attrs"].get("stdDeviation") else "")
                                  for p in f.get("primitives", []))
                A("  - filter `%s`（%s，region %s）：%s" % (
                    f["id"], f.get("filterUnits"), json.dumps(f.get("region")), prims))
            for g in rd.get("gradients", []):
                if g["kind"] == "radialGradient" and (g.get("eccentric") or g.get("centered") is False):
                    A("  - radial `%s`：cx=%s cy=%s fx=%s fy=%s，%s" % (
                        g["id"], g.get("cx"), g.get("cy"), g.get("fx"), g.get("fy"),
                        "偏心" if g.get("eccentric") else "非中心(objectBoundingBox)"))
            n_rad = sum(1 for g in rd.get("gradients", []) if g["kind"] == "radialGradient")
            n_rad_off = sum(1 for g in rd.get("gradients", [])
                            if g["kind"] == "radialGradient"
                            and (g.get("eccentric") or g.get("centered") is False))
            n_rad_us = sum(1 for g in rd.get("gradients", [])
                           if g["kind"] == "radialGradient"
                           and g.get("gradientUnits") == "userSpaceOnUse")
            if n_rad:
                A("  - 径向渐变共 %d 个（偏心/非中心 %d，userSpaceOnUse %d，其余居中 OBB）" % (
                    n_rad, n_rad_off, n_rad_us))
            mk_agg = {}
            for mk in rd.get("masks", []):
                key = (mk.get("maskType"), mk.get("classification"),
                       mk.get("maskUnits"), mk.get("maskContentUnits"))
                mk_agg.setdefault(key, []).append(mk)
            for (mtype, cls, mu, mcu), mks in sorted(mk_agg.items(), key=lambda kv: str(kv[0])):
                big = [m for m in mks if m.get("shapeCount", 0) > 500
                       or m.get("subpathCount", 0) > 500]
                A("  - mask ×%d：maskType=%s，%s，units=%s/%s%s" % (
                    len(mks), mtype, cls, mu, mcu,
                    ("；大覆盖：" + ", ".join("%s(形状%d/子路径%d)" % (
                        m["id"], m.get("shapeCount", 0), m.get("subpathCount", 0))
                        for m in big)) if big else ""))
            pt_note_shown = False
            for pt in rd.get("patterns", []):
                pim = pt.get("images") or []
                A("  - pattern `%s`：units=%s/%s，tile=%sx%s，孩子=%s%s" % (
                    pt["id"], pt.get("patternUnits"), pt.get("patternContentUnits"),
                    (pt.get("tile") or {}).get("width"), (pt.get("tile") or {}).get("height"),
                    pt.get("childKinds"),
                    ("，内嵌纹理 %d 字节 SHA `%s`" % (pim[0].get("decodedBytes", 0),
                     (pim[0].get("decodedSha256") or "")[:16])) if pim else ""))
                if pt.get("note") and not pt_note_shown:
                    A("    - %s（下同）" % pt["note"])
                    pt_note_shown = True
            cps = rd.get("clipPaths", [])
            if cps:
                agg = {}
                for cp in cps:
                    key = (cp.get("clipPathUnits"), cp.get("hasText"),
                           tuple(cp.get("shapeKinds") or ()))
                    agg[key] = agg.get(key, 0) + 1
                A("  - clipPath %d 个：%s" % (len(cps), "；".join(
                    "units=%s %s形状%s ×%d" % (k[0], "/".join(k[2]), "(含文本)" if k[1] else "", v)
                    for k, v in sorted(agg.items(), key=lambda kv: str(kv[0])))))
            im_agg = {}
            for im in s.get("images", []):
                if im["hrefType"] == "data-uri":
                    key = (im.get("mime"), im.get("decodedBytes", 0),
                           (im.get("decodedSha256") or "")[:16])
                    im_agg[key] = im_agg.get(key, 0) + 1
                else:
                    A("  - 外部图片引用（矩阵不支持）：%s" % im.get("href"))
            for (mime, nbytes, sha16), cnt in sorted(im_agg.items()):
                A("  - 内嵌图（原作者程序纹理）：%s %d 字节 SHA `%s` ×%d" % (
                    mime, nbytes, sha16, cnt))
            if s.get("texts", {}).get("count"):
                A("  - 文本 %d 个，字体：%s" % (
                    s["texts"]["count"], json.dumps(list(s["texts"]["fonts"].keys()), ensure_ascii=False)))
            if s.get("extensionRequiredCodes"):
                A("  - **extension-required**：%s" % ", ".join(s["extensionRequiredCodes"]))
                by_code = {}
                for f in s.get("features", []):
                    if f["severity"] == "extension-required":
                        by_code.setdefault(f["code"], []).append(f)
                for code, fs in sorted(by_code.items()):
                    details = [f["detail"] for f in fs]
                    groups = sorted({g for f in fs for g in f["groups"]})
                    show = details if len(details) <= 8 else details[:8] + ["…共 %d 条" % len(details)]
                    A("    - `%s` ×%d（组：%s）" % (code, len(fs),
                                                    ", ".join(groups) or "全文件"))
                    for d in show:
                        A("      - %s" % d)
            if s.get("verifyCodes"):
                A("  - verify：%s" % ", ".join(s["verifyCodes"]))
            A("  - 可保留原生顶层组 %d/%d：%s" % (
                len(s.get("nativeReadyGroups", [])), len(s.get("topGroups", [])),
                ", ".join(s.get("nativeReadyGroups", [])[:12]) or "(无)"))
            if s.get("extensionGroups"):
                A("  - 需扩展局部组：%s" % ", ".join(s["extensionGroups"]))
        if m["propsDynamics"]:
            A("- 动态件（不烘入底图；门叶等复用矢量源）：%s" % ", ".join(
                "%s(`%s`)" % (p["id"], (p.get("svg") or {}).get("path", "?")) for p in m["propsDynamics"]))
        if m["proposedNotWired"]:
            A("- proposed 未接入（盘上 parts/ 存在、map-input 未消费，不伪装已消费）：")
            for p in m["proposedNotWired"]:
                A("  - `%s`（%d 字节，ext=%s）" % (
                    p["path"], p["bytes"], "/".join(p["extensionRequiredCodes"]) or "无"))
        for d in m.get("deferredLayers", []):
            A("- deferred：`%s`——%s" % (d.get("id"), (d.get("note") or "")[:100]))
        A("")
    # 跨图共性统计
    code_maps = {}
    filter_prims = {}
    for mid, m in index["maps"].items():
        for l in m["layers"]:
            s = l.get("sourceSVG") or {}
            for f in s.get("features", []):
                if f["severity"] == "extension-required":
                    code_maps.setdefault(f["code"], set()).add(mid)
            for flt in (s.get("referencedDefs", {}) or {}).get("filters", []):
                for p in flt.get("primitives", []):
                    filter_prims.setdefault(p["kind"], set()).add(mid)
    A("## 跨图共性")
    A("")
    for code, maps in sorted(code_maps.items()):
        A("- `%s`：%s" % (code, ", ".join(sorted(maps))))
    if filter_prims:
        A("- filter primitive 实际使用：%s" % "; ".join(
            "%s（%s）" % (k, ", ".join(sorted(v))) for k, v in sorted(filter_prims.items())))
    A("")
    A("## 边界与未证明项")
    A("")
    A("- 本审计是静态源分析：不等于 CS6 编译通过、不等于原生 XFL 实际像素正确、不等于运行时烘焙效果。")
    A("- 既有整层 baked PNG 仅作对照基线保留；矢量转换与实机画面需 Astra/主控另行验收。")
    A("- A01 行仅为交叉核对 Astra 样板输入，native-vector/ 与其背景 XFL 归 Astra 独占。")
    out = os.path.join(DEFAULT_OUT, "result-r5.md")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
