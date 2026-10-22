"""XFL(DOMSymbolItem) -> SVG 装饰导出器。

设计目标：把 Flash XFL 库里某一帧的**可见装饰**保真导出为 SVG，
供 Web UI 复刻原版美术。坐标一律保持 Flash 舞台像素（twips/20），
矩阵原样写入 transform，不做几何近似。

范围边界（遇到即记录 unsupported / skipped，不静默丢图）：
- 不执行 ActionScript、不推进 MovieClip 播放时钟；取声明 firstFrame 或第 0 帧。
- shape tween / MorphShape：只取该帧 elements 内的基准 DOMShape，MorphSegments 忽略。
- BevelFilter / GlowFilter / BlurFilter 等 -> 记录 unsupported（基础美术仍导出）。
- DropShadowFilter -> feDropShadow（stdDeviation=blur/2，近似）。
- blendMode -> style="mix-blend-mode"；光栅化器支持度记入 manifest。
- mask 层 -> clipPath；命中的被遮罩层包 clip-path。
- DOMDynamicText / DOMStaticText -> 只进 layout.json，不烘焙进 SVG。
- portrait 槽位符号（--portrait-symbols）不展开，只记矩阵。
- BitmapFill / DottedStroke / DOMBitmapInstance / TLF / 元件对象 -> unsupported。
- Edge@cubics 为 edges 的冗余三次编码，忽略；若 Edge 只有 cubics 而无 edges 数据则计数报告。

解析思路沿用 tools/asset-metrology/xfl_geometry.py（已验证）：
Edge 语义 `!`move `|`/`/`line `[`/`]`quadratic-bezier，`S<n>` 编辑器选择位，
坐标为 twips/20，`#XX[.YY]` 为十六进制定点补码。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from xml.sax.saxutils import escape

NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
TOKENS = re.compile(r'#[0-9a-fA-F]+(?:\.[0-9a-fA-F]+)?|[+-]?(?:\d+(?:\.\d*)?|\.\d+)|[!|/\[\]S]')
BARE_AMP = re.compile(r'&(?!#\d+;|#x[0-9A-Fa-f]+;|[A-Za-z][A-Za-z0-9_.:-]*;)')
GRADIENT_HALF = 819.2  # Flash 渐变空间半宽（16384 twips 方框 -> px）
BUTTON_STATES = ('up', 'over', 'down', 'hit')


# ---------- 基础几何（与 xfl_geometry.py 同语义） ----------

def parse_matrix(el):
    if el is None:
        return IDENTITY
    return tuple(float(el.get(k, IDENTITY[i])) for i, k in
                 enumerate(('a', 'b', 'c', 'd', 'tx', 'ty')))


def multiply(l, r):
    a, b, c, d, x, y = l
    e, f, g, h, u, v = r
    return (a*e + c*f, b*e + d*f, a*g + c*h, b*g + d*h,
            a*u + c*v + x, b*u + d*v + y)


def transform_point(m, p):
    a, b, c, d, x, y = m
    return (a*p[0] + c*p[1] + x, b*p[0] + d*p[1] + y)


def transform_rect(m, w, h):
    pts = [transform_point(m, p) for p in ((0, 0), (w, 0), (0, h), (w, h))]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return [min(xs), min(ys), max(xs), max(ys)]


def num(token):
    """twips 数 -> px。"""
    if not token.startswith('#'):
        v = float(token)
    else:
        whole, _, frac = token[1:].partition('.')
        iv = int(whole, 16)
        if iv >= 0x800000:
            iv -= 0x1000000
        v = iv + (int(frac, 16) / 16**len(frac) if frac else 0)
    if not math.isfinite(v):
        raise ValueError('非有限坐标')
    return v / 20.0


def edge_segments(edge_text):
    """Edge@edges -> [ (p0, p1) 直线 | (p0, ctrl, p1) 二次贝塞尔 ]，px。"""
    tokens = TOKENS.findall(edge_text or '')
    if TOKENS.sub('', edge_text or '').strip():
        raise ValueError('不支持的轮廓语法: ' + edge_text[:60])
    out, i, cur = [], 0, None
    while i < len(tokens):
        cmd = tokens[i]
        i += 1
        if cmd == 'S':
            if i >= len(tokens) or not tokens[i].isdigit():
                raise ValueError('损坏的选择位')
            i += 1
            continue
        if cmd not in ('!', '|', '/', '[', ']'):
            raise ValueError('不支持的轮廓命令: ' + cmd)
        n = 4 if cmd in ('[', ']') else 2
        coords = tuple(num(t) for t in tokens[i:i + n])
        if len(coords) != n:
            raise ValueError('坐标数量不足')
        i += n
        end = coords[-2:]
        if cmd != '!':
            if cur is None:
                raise ValueError('轮廓缺少起点')
            out.append((cur, coords[:2], end) if n == 4 else (cur, end))
        cur = end
    return out


def segments_to_d(segs, m=None):
    """段序列 -> path d。每段首点与上一段末点相同则续写，否则 M。m 可选预变换。"""
    if m is not None:
        segs = [tuple(transform_point(m, p) for p in s) for s in segs]
    parts, cur = [], None
    for s in segs:
        if cur != s[0]:
            parts.append('M%s %s' % (f(s[0][0]), f(s[0][1])))
        if len(s) == 3:
            parts.append('Q%s %s %s %s' % (f(s[1][0]), f(s[1][1]), f(s[2][0]), f(s[2][1])))
        else:
            parts.append('L%s %s' % (f(s[1][0]), f(s[1][1])))
        cur = s[-1]
    return ''.join(parts)


def reverse_segments(segs):
    """fillStyle0 的边对填充区是反向的；反转整条边保持 nonzero 一致。"""
    out = []
    for s in reversed(segs):
        if len(s) == 3:
            out.append((s[2], s[1], s[0]))
        else:
            out.append((s[1], s[0]))
    return out


def f(v):
    s = ('%.4f' % v).rstrip('0').rstrip('.')
    return s if s not in ('-0', '') else '0'


def fmt_matrix(m):
    return 'matrix(%s)' % ' '.join(f(v) for v in m)


def clip_items_to_xml(items):
    """[(d, matrix)] -> clipPath 子节点串。"""
    out = []
    for d, m in items:
        if not d:
            continue
        tr = ' transform="%s"' % fmt_matrix(m) if m != IDENTITY else ''
        out.append('<path%s d="%s"/>' % (tr, d))
    return ''.join(out)


CT_IDENTITY = (1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0)


def ct_apply_rgb(hex_color, ct):
    """Flash ColorTransform 逐通道: c' = clamp(c*mult + off)。"""
    v = int(hex_color.lstrip('#')[:6], 16)
    r, g, b = (v >> 16) & 255, (v >> 8) & 255, v & 255
    r = min(255, max(0, round(r * ct[0] + ct[4])))
    g = min(255, max(0, round(g * ct[1] + ct[5])))
    b = min(255, max(0, round(b * ct[2] + ct[6])))
    return '#%02X%02X%02X' % (r, g, b)


def ct_apply_alpha(a, ct):
    return min(1.0, max(0.0, a * ct[3] + ct[7] / 255.0))


# ---------- 填充 / 描边 ----------

class Unsupported(Exception):
    pass


def parse_solid(el):
    color = el.get('color', '#000000')
    alpha = float(el.get('alpha', '1'))
    return {'kind': 'solid', 'color': color.upper(), 'alpha': alpha}


def parse_gradient(el, kind):
    m = el.find('./x:matrix/x:Matrix', NS)
    entries = []
    for g in el.findall('./x:GradientEntry', NS):
        entries.append({'ratio': float(g.get('ratio', '0')),
                        'color': g.get('color', '#000000').upper(),
                        'alpha': float(g.get('alpha', '1'))})
    return {'kind': kind, 'matrix': parse_matrix(m), 'entries': entries,
            'spread': el.get('spreadMethod', 'extend'),
            'focal': float(el.get('focalPointRatio', '0'))}


def parse_fill_style(fs):
    for child in fs:
        tag = child.tag.rsplit('}', 1)[-1]
        if tag == 'SolidColor':
            return parse_solid(child)
        if tag in ('LinearGradient', 'RadialGradient'):
            return parse_gradient(child, 'linear' if tag == 'LinearGradient' else 'radial')
        if tag == 'BitmapFill':
            raise Unsupported('BitmapFill')
    return None


def parse_stroke_style(ss):
    for child in ss:
        tag = child.tag.rsplit('}', 1)[-1]
        if tag != 'SolidStroke':
            raise Unsupported('stroke:' + tag)
        fill_el = child.find('./x:fill', NS)
        fill = parse_fill_style(fill_el) if (fill_el is not None and len(fill_el)) else None
        return {'kind': 'solid', 'weight': float(child.get('weight', '1')),
                'caps': child.get('caps', 'round'), 'joints': child.get('joints', 'round'),
                'miter': child.get('miterLimit'), 'scaleMode': child.get('scaleMode', 'normal'),
                'fill': fill or {'kind': 'solid', 'color': '#000000', 'alpha': 1.0}}
    return None


# ---------- 渲染器 ----------

class Renderer:
    def __init__(self, library, portrait_symbols):
        self.library = Path(library).resolve()
        self.cache = {}
        self.sources = set()
        self.unsupported = []
        self.skipped = []
        self.warnings = set()
        self.defs = []
        self._def_id = 0
        self._def_dedup = {}
        self.portrait_symbols = set(portrait_symbols)
        self.fields = []      # DOMDynamicText/Static 记录
        self.buttons = []     # 按钮实例记录
        self.portraits = []   # 肖像槽记录
        self.clips = {}       # mask -> path d（舞台坐标）
        self.button_files = {}  # (symbol,state) -> 相对路径
        self.separate_buttons = False  # True: source.svg 不烘焙按钮 up 美术

    # ---- 资源 ----
    def load(self, name):
        if name not in self.cache:
            path = (self.library / (name + '.xml')).resolve()
            if not path.is_relative_to(self.library):
                raise ValueError('符号路径越界: ' + name)
            if not path.exists():
                raise Unsupported('缺少库文件: ' + name)
            self.cache[name] = ET.fromstring(BARE_AMP.sub('&amp;', path.read_text(encoding='utf-8-sig')))
            self.sources.add(path)
        return self.cache[name]

    def new_def(self, body, tag='clipPath'):
        key = (tag, body)
        if key in self._def_dedup:
            return self._def_dedup[key]
        self._def_id += 1
        did = 'd%d' % self._def_id
        self._def_dedup[key] = did
        self.defs.append('<%s id="%s">%s</%s>' % (tag, did, body, tag))
        return did

    def note_unsupported(self, feature, where, effect='基础美术仍导出'):
        self.unsupported.append({'feature': feature, 'where': where, 'effect': effect})

    # ---- 时间轴帧选择 ----
    def frame_elements(self, root, frame, where):
        """yield (layer, elements_el)。层序按文档序（0=顶层），调用方负责倒序绘制。"""
        timeline = root.find('./x:timeline/x:DOMTimeline', NS)
        if timeline is None:
            return
        layers = timeline.findall('./x:layers/x:DOMLayer', NS)
        for li, layer in enumerate(layers):
            if layer.get('layerType') in ('guide', 'folder'):
                continue
            if layer.get('visible') == 'false':
                continue
            for fr in layer.findall('./x:frames/x:DOMFrame', NS):
                start = int(fr.get('index', 0))
                if start <= frame < start + int(fr.get('duration', 1)):
                    if frame != start and fr.get('tweenType'):
                        self.warnings.add('%s: 帧 %d 落在 %s tween 内，取关键帧美术' %
                                          (where, frame, fr.get('tweenType')))
                    yield li, layer, fr.find('./x:elements', NS)
                    break

    def symbol_bbox(self, name, frame=0, m=IDENTITY, stack=()):
        """粗略包围盒（不含描边宽度）。遮罩感知：被遮罩层 bbox 与其 mask 层
        （parentLayerIndex 指向）本帧内容 bbox 相交；mask 无内容则该层不可见。"""
        if name in stack or len(stack) > 64:
            return None
        try:
            root = self.load(name)
        except Exception:
            return None
        layers_el = root.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS)
        # 本帧各层 elements（mask 层也收集，供相交）
        frame_els = []
        for li, layer in enumerate(layers_el):
            if layer.get('layerType') in ('guide', 'folder') \
                    or layer.get('visible') == 'false':
                frame_els.append((li, layer, None))
                continue
            els = None
            for fr in layer.findall('./x:frames/x:DOMFrame', NS):
                s = int(fr.get('index', 0))
                if s <= frame < s + int(fr.get('duration', 1)):
                    els = fr.find('./x:elements', NS)
                    break
            frame_els.append((li, layer, els))
        # mask 层自身不可见，只提供裁剪边界
        mask_bbox = {}
        for li, layer, els in frame_els:
            if layer.get('layerType') == 'mask' and els is not None:
                pts = []
                self._bbox_elements(els, m, stack + (name,), pts)
                if pts:
                    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
                    mask_bbox[li] = (min(xs), min(ys), max(xs), max(ys))
        pts = []
        for li, layer, els in frame_els:
            if layer.get('layerType') in ('guide', 'folder', 'mask') or els is None:
                continue
            lpts = []
            self._bbox_elements(els, m, stack + (name,), lpts)
            if not lpts:
                continue
            pi = self._mask_index_of(layers_el, li)
            if pi is None:
                pts.extend(lpts)
                continue
            mb = mask_bbox.get(pi)
            if mb is None:
                continue  # 遮罩关系存在但 mask 无内容 -> 整层不可见
            xs, ys = [p[0] for p in lpts], [p[1] for p in lpts]
            lb = (max(min(xs), mb[0]), max(min(ys), mb[1]),
                  min(max(xs), mb[2]), min(max(ys), mb[3]))
            if lb[0] < lb[2] and lb[1] < lb[3]:
                pts.extend([(lb[0], lb[1]), (lb[2], lb[3])])
        if not pts:
            return None
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        return [min(xs), min(ys), max(xs), max(ys)]

    def _bbox_elements(self, els, m, stack, pts):
        for el in els:
            tag = el.tag.rsplit('}', 1)[-1]
            own = el.find('./x:matrix/x:Matrix', NS)
            mm = multiply(m, parse_matrix(own)) if own is not None else m
            if tag == 'DOMGroup':
                mem = el.find('./x:members', NS)
                if mem is not None:
                    self._bbox_elements(mem, mm, stack, pts)
            elif tag == 'DOMSymbolInstance':
                ln = el.get('libraryItemName')
                if ln and ln not in self.portrait_symbols:
                    b = self.symbol_bbox(ln, int(el.get('firstFrame', 0)), mm, stack)
                    if b:
                        pts.extend([(b[0], b[1]), (b[2], b[3])])
            elif tag == 'DOMShape':
                for e in el.findall('./x:edges/x:Edge', NS):
                    for s in edge_segments(e.get('edges', '')):
                        pts.extend(transform_point(mm, p) for p in (s[0], s[-1]))

    # ---- 主渲染 ----
    def render_symbol(self, name, frame, where, ct=CT_IDENTITY):
        """返回该符号指定帧的 SVG 片段字符串（局部坐标，列表按底->顶序）。"""
        root = self.load(name)
        if root.find('.//x:Actionscript', NS) is not None:
            self.warnings.add(name + ': 含 ActionScript，未执行')
        out = []
        # mask 处理：先收集 mask 层 id -> clipPath
        layers = root.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS)
        mask_clip = {}   # mask 层索引 -> clipPath def id
        for li, layer, els in self.frame_elements(root, frame, where):
            if layer.get('layerType') != 'mask':
                continue
            mask_clip[li] = self.new_def(
                clip_items_to_xml(self.elements_to_d(els, where + ' mask')))
        for li, layer, els in self.frame_elements(root, frame, where):
            if layer.get('layerType') == 'mask':
                continue
            if els is None or not len(els):
                continue
            body = self.elements_to_svg(els, where, ct)
            clip = mask_clip.get(self._mask_index_of(layers, li))
            if clip:
                body = '<g clip-path="url(#%s)">%s</g>' % (clip, body)
            out.append((li, body))
        # DOMLayer 0 = 顶层；SVG 先画底层 -> 反转
        out.sort(key=lambda t: -t[0])
        return ''.join(b for _, b in out)

    def _mask_index_of(self, layers, li):
        """返回层 li 的 mask 层索引（parentLayerIndex 指向 mask）。"""
        try:
            return int(layers[li].get('parentLayerIndex'))
        except (TypeError, ValueError):
            return None

    def elements_to_d(self, els, where, m=IDENTITY):
        """elements -> [(d, 矩阵)] 列表（供 clipPath / 元数据）。"""
        parts = []
        if els is None:
            return parts
        for el in els:
            tag = el.tag.rsplit('}', 1)[-1]
            own = el.find('./x:matrix/x:Matrix', NS)
            mm = multiply(m, parse_matrix(own)) if own is not None else m
            if tag == 'DOMShape':
                d = self.shape_to_d(el, where, mm)
                if d:
                    parts.append((d, IDENTITY))
            elif tag == 'DOMGroup':
                mem = el.find('./x:members', NS)
                parts.extend(self.elements_to_d(mem, where, mm))
            elif tag == 'DOMSymbolInstance':
                ln = el.get('libraryItemName')
                if ln:
                    try:
                        root = self.load(ln)
                        for _, _, sub in self.frame_elements(root, 0, ln):
                            parts.extend(self.elements_to_d(sub, ln, mm))
                    except Exception as ex:
                        self.note_unsupported('clipPath 内嵌套实例', ln, str(ex))
        return parts

    def portrait_mask_clip(self, name, frame, m, where):
        """读取 portrait 槽符号本帧 mask 层几何（仅 DOMShape/Group，
        不展开被遮罩内容与嵌套实例依赖），返回经实例矩阵的舞台 path d。"""
        try:
            root = self.load(name)
        except Unsupported:
            return None
        parts = []
        for _, layer, els in self.frame_elements(root, frame, where):
            if layer.get('layerType') != 'mask' or els is None:
                continue
            parts.extend(self._mask_shapes_to_d(els, m, where))
        return ''.join(parts) or None

    def _mask_shapes_to_d(self, els, m, where):
        out = []
        for el in els:
            tag = el.tag.rsplit('}', 1)[-1]
            own = el.find('./x:matrix/x:Matrix', NS)
            mm = multiply(m, parse_matrix(own)) if own is not None else m
            if tag == 'DOMShape':
                d = self.shape_to_d(el, where, mm)
                if d:
                    out.append(d)
            elif tag == 'DOMGroup':
                mem = el.find('./x:members', NS)
                if mem is not None:
                    out.extend(self._mask_shapes_to_d(mem, mm, where))
            else:
                self.note_unsupported('portrait mask 内 ' + tag, where,
                                      '该项未计入裁剪')
        return out

    def shape_to_d(self, shape, where, m=IDENTITY):
        parts = []
        for e in shape.findall('./x:edges/x:Edge', NS):
            if not e.get('edges'):
                continue
            segs = edge_segments(e.get('edges'))
            if e.get('fillStyle1', '0') != '0':
                parts.append(segments_to_d(segs, m))
            if e.get('fillStyle0', '0') != '0':
                parts.append(segments_to_d(reverse_segments(segs), m))
        return ''.join(parts)

    def elements_to_svg(self, els, where, ct=CT_IDENTITY):
        out = []
        for el in els:
            s = self.element_to_svg(el, where, ct)
            if s:
                out.append(s)
        return ''.join(out)

    def element_to_svg(self, el, where, ct=(1, 1, 1, 1, 0, 0, 0, 0)):
        tag = el.tag.rsplit('}', 1)[-1]
        own = el.find('./x:matrix/x:Matrix', NS)
        m = parse_matrix(own)
        tr = ' transform="%s"' % fmt_matrix(m) if m != IDENTITY else ''
        # color transform / alpha
        color = el.find('./x:color/x:Color', NS)
        color_attrs, ct = self.color_transform(color, ct)
        # filters
        filt = el.find('./x:filters', NS)
        filt_attr = self.filters_to_attr(filt, where)
        blend = el.get('blendMode')
        style = ' style="mix-blend-mode:%s"' % blend if blend and blend != 'normal' else ''
        if blend and blend != 'normal':
            self.note_unsupported('blendMode=' + blend, where,
                                  '已写 mix-blend-mode；CairoSVG 光栅化可能忽略')

        if tag == 'DOMGroup':
            mem = el.find('./x:members', NS)
            body = self.elements_to_svg(mem, where, ct) if mem is not None else ''
            return '<g%s%s%s%s>%s</g>' % (tr, color_attrs, filt_attr, style, body)

        if tag == 'DOMSymbolInstance':
            ln = el.get('libraryItemName')
            iname = el.get('name', '')
            if el.get('visible') == 'false':
                self.skipped.append({'symbol': ln, 'reason': 'visible=false'})
                return ''
            if not ln:
                self.note_unsupported('无 libraryItemName 的实例', where)
                return ''
            if ln in self.portrait_symbols:
                rec = {'id': iname or ln.split('/')[-1], 'symbol': ln,
                       'matrix': list(m if m != IDENTITY else IDENTITY)}
                clip_d = self.portrait_mask_clip(
                    ln, int(el.get('firstFrame', 0)), m, where)
                if clip_d:
                    rec['clip'] = 'internalPortraitClip'
                    self.clips['internalPortraitClip'] = clip_d
                self.portraits.append(rec)
                self.skipped.append({'symbol': ln, 'reason': 'portraitDep'})
                return ''
            stype = el.get('symbolType', 'movie clip')
            frame = int(el.get('firstFrame', 0))
            if stype == 'button':
                return self.button_instance(el, ln, m, tr, color_attrs,
                                            filt_attr, style, where, ct)
            try:
                body = self.render_symbol(ln, frame, ln, ct=ct)
            except Unsupported as ex:
                self.note_unsupported(str(ex), ln)
                return ''
            attrs = ''.join((tr, color_attrs, filt_attr, style))
            if iname:
                attrs += ' data-name="%s"' % escape(iname)
            return '<g%s>%s</g>' % (attrs, body)

        if tag == 'DOMShape':
            return self.shape_to_svg(el, tr + color_attrs, where, ct)

        if tag in ('DOMDynamicText', 'DOMStaticText'):
            self.fields.append(self.text_record(el, tag, m))
            return ''

        if tag == 'DOMRectangleObject':
            x, y = float(el.get('x', 0)), float(el.get('y', 0))
            w, h = float(el.get('objectWidth', 0)), float(el.get('objectHeight', 0))
            r = float(el.get('topLeftRadius', 0))
            return ('<rect x="%s" y="%s" width="%s" height="%s" rx="%s"%s/>'
                    % (f(x), f(y), f(w), f(h), f(r), tr))
        if tag == 'DOMOvalObject':
            x, y = float(el.get('x', 0)), float(el.get('y', 0))
            w, h = float(el.get('objectWidth', 0)), float(el.get('objectHeight', 0))
            return ('<ellipse cx="%s" cy="%s" rx="%s" ry="%s"%s/>'
                    % (f(x + w / 2), f(y + h / 2), f(w / 2), f(h / 2), tr))

        self.note_unsupported('元素:' + tag, where)
        return ''

    # ---- shape -> 填充/描边分桶 ----
    def shape_to_svg(self, shape, tr, where, ct=CT_IDENTITY):
        fills, strokes = {}, {}
        for fs in shape.findall('./x:fills/x:FillStyle', NS):
            try:
                fills[fs.get('index')] = parse_fill_style(fs)
            except Unsupported as ex:
                self.note_unsupported(str(ex), where + ' fill', '该填充路径省略')
        for ss in shape.findall('./x:strokes/x:StrokeStyle', NS):
            try:
                strokes[ss.get('index')] = parse_stroke_style(ss)
            except Unsupported as ex:
                self.note_unsupported(str(ex), where + ' stroke', '该描边省略')
        cubics_only = 0
        buckets = {}  # ('fill',idx)/('stroke',idx) -> [d]
        for e in shape.findall('./x:edges/x:Edge', NS):
            if not e.get('edges'):
                cubics_only += 1
                continue
            try:
                segs = edge_segments(e.get('edges'))
            except ValueError as ex:
                self.note_unsupported('Edge 语法', where, str(ex))
                continue
            f1, f0, st = e.get('fillStyle1', '0'), e.get('fillStyle0', '0'), e.get('strokeStyle', '0')
            if f1 != '0':
                buckets.setdefault(('fill', f1), []).append(segments_to_d(segs))
            if f0 != '0':
                buckets.setdefault(('fill', f0), []).append(segments_to_d(reverse_segments(segs)))
            if st != '0':
                buckets.setdefault(('stroke', st), []).append(segments_to_d(segs))
        if cubics_only:
            # cubics 冗余边在 XFL 导出中与 edges 并存；仅当全部边都缺 edges 才算丢失
            total = len(shape.findall('./x:edges/x:Edge', NS))
            if cubics_only == total and total:
                self.note_unsupported('Edge 仅含 cubics', where, '该形状未导出')
        out = []
        for (kind, idx), ds in buckets.items():
            d = ''.join(ds)
            if not d:
                continue
            if kind == 'fill':
                spec = fills.get(idx)
                if spec is None:
                    self.note_unsupported('fillStyle 索引缺失', where, 'index=' + idx)
                    continue
                paint, extra = self.paint_attr(spec, where, ct=ct)
                if paint is None:
                    continue  # alpha 0 等不可见
                out.append('<path d="%s" %s%s/>' % (d, paint, extra))
            else:
                spec = strokes.get(idx)
                if spec is None:
                    continue
                paint, extra = self.paint_attr(spec['fill'], where, stroke=True,
                                               stroke_spec=spec, ct=ct)
                if paint is None:
                    continue
                out.append('<path d="%s" fill="none" %s%s/>' % (d, paint, extra))
        if not out:
            if shape.findall('./x:edges/x:Edge', NS):
                self.skipped.append({'where': where, 'reason': 'allPaintsInvisible'})
            return ''
        return '<g%s fill-rule="nonzero">%s</g>' % (tr or '', ''.join(out))

    def paint_attr(self, spec, where, stroke=False, stroke_spec=None,
                   ct=CT_IDENTITY):
        """返回 (paint_attr, extra_attrs)。None = 不可见。"""
        if spec is None:
            return None, ''
        if spec['kind'] == 'solid':
            alpha = ct_apply_alpha(spec['alpha'], ct)
            if alpha <= 0:
                return None, ''
            color = ct_apply_rgb(spec['color'], ct) if ct != CT_IDENTITY else spec['color']
            key = 'stroke' if stroke else 'fill'
            attr = '%s="%s"' % (key, color)
            if alpha < 1:
                attr += ' %s-opacity="%.4f"' % (key, alpha)
        else:
            if ct != CT_IDENTITY:
                spec = dict(spec)
                spec['entries'] = [
                    dict(g, color=ct_apply_rgb(g['color'], ct),
                         alpha=ct_apply_alpha(g['alpha'], ct))
                    for g in spec['entries']]
            gid = self.gradient_def(spec)
            attr = ('stroke' if stroke else 'fill') + '="url(#%s)"' % gid
        if stroke and stroke_spec is not None:
            s = stroke_spec
            attr += ' stroke-width="%s" stroke-linecap="%s" stroke-linejoin="%s"' % (
                f(s['weight']), s['caps'], s['joints'])
            if s['joints'] == 'miter' and s['miter']:
                attr += ' stroke-miterlimit="%s"' % s['miter']
            if s['scaleMode'] == 'none':
                attr += ' vector-effect="non-scaling-stroke"'
            elif s['scaleMode'] != 'normal':
                self.note_unsupported('stroke scaleMode=' + s['scaleMode'], where)
        return attr, ''

    def gradient_def(self, spec):
        body = ''.join(
            '<stop offset="%s" stop-color="%s"%s/>' % (
                f(g['ratio']), g['color'],
                '' if g['alpha'] >= 1 else ' stop-opacity="%.4f"' % g['alpha'])
            for g in spec['entries'])
        spread = {'extend': 'pad', 'reflect': 'reflect', 'repeat': 'repeat'}.get(spec['spread'])
        sm = ' spreadMethod="%s"' % spread if spread else ''
        tr = ' gradientTransform="%s"' % fmt_matrix(spec['matrix'])
        if spec['kind'] == 'linear':
            inner = ('<linearGradient gradientUnits="userSpaceOnUse" '
                     'x1="-819.2" y1="0" x2="819.2" y2="0"%s%s>%s</linearGradient>'
                     % (tr, sm, body))
        else:
            foc = ' fx="%s"' % f(spec['focal'] * GRADIENT_HALF) if spec['focal'] else ''
            inner = ('<radialGradient gradientUnits="userSpaceOnUse" '
                     'cx="0" cy="0" r="819.2"%s%s%s>%s</radialGradient>'
                     % (foc, tr, sm, body))
        key = ('gradient', inner)
        if key in self._def_dedup:
            return self._def_dedup[key]
        self._def_id += 1
        gid = 'g%d' % self._def_id
        self._def_dedup[key] = gid
        self.defs.append(inner.replace('<linearGradient', '<linearGradient id="%s"' % gid, 1)
                         .replace('<radialGradient', '<radialGradient id="%s"' % gid, 1))
        return gid

    # ---- color / filter ----
    # 颜色变换 ct = (rm, gm, bm, am, ro, go, bo, ao)，offset 0-255。
    # 纯 alphaMultiplier 走组 opacity（合成后整乘，与 Flash 一致）；
    # 其余折算进每个 fill/渐变 stop（逐通道线性，无渲染器依赖）。
    def color_transform(self, color, ct):
        if color is None:
            return '', ct
        mult = tuple(float(color.get(k, '1')) for k in
                     ('redMultiplier', 'greenMultiplier', 'blueMultiplier',
                      'alphaMultiplier'))
        off = tuple(float(color.get(k, '0')) for k in
                    ('redOffset', 'greenOffset', 'blueOffset', 'alphaOffset'))
        el_ct = mult + off
        # 组合：先内层后外层 c' = (c*im+io)*om+oo -> mult=im*om, off=io*om+oo
        im, io = el_ct[:4], el_ct[4:]
        om, oo = ct[:4], ct[4:]
        ct2 = tuple(im[i] * om[i] for i in range(4)) + \
              tuple(io[i] * om[i] + oo[i] for i in range(4))
        if all(v == 0 for v in io) and el_ct[:3] == (1.0, 1.0, 1.0):
            # 纯 alpha：组 opacity 精确（对重叠半透明也正确）
            am = el_ct[3] * ct[3]
            return ('' if am >= 1 else ' opacity="%.4f"' % am), ct
        return '', ct2

    def filters_to_attr(self, filt, where):
        if filt is None:
            return ''
        parts, fid = [], None
        for fl in filt:
            tag = fl.tag.rsplit('}', 1)[-1]
            if tag == 'DropShadowFilter':
                dist = float(fl.get('distance', '4'))
                ang = math.radians(float(fl.get('angle', '45')))
                blur = (float(fl.get('blurX', '4')) + float(fl.get('blurY', '4'))) / 4
                alpha = float(fl.get('alpha', '1')) * float(fl.get('strength', '1'))
                color = fl.get('color', '#000000')
                if fl.get('inner') == 'true' or fl.get('hideObject') == 'true':
                    self.note_unsupported('DropShadow inner/hideObject', where)
                key = ('filter', 'feDropShadow', dist, ang, blur, color, min(alpha, 1))
                if key not in self._def_dedup:
                    self._def_id += 1
                    self._def_dedup[key] = 'fl%d' % self._def_id
                    self.defs.append(
                        '<filter id="%s" x="-50%%" y="-50%%" width="200%%" height="200%%">'
                        '<feDropShadow dx="%s" dy="%s" stdDeviation="%s" flood-color="%s" '
                        'flood-opacity="%s"/></filter>'
                        % (self._def_dedup[key], f(dist * math.cos(ang)),
                           f(-dist * math.sin(ang)), f(blur), color, f(min(alpha, 1))))
                fid = self._def_dedup[key]
            elif tag == 'BevelFilter':
                self.note_unsupported('BevelFilter', where, '斜面高光/阴影未导出')
            else:
                self.note_unsupported('Filter:' + tag, where)
        return ' filter="url(#%s)"' % fid if fid else ''

    # ---- 按钮 ----
    @staticmethod
    def _rect_by_matrix(m, bbox):
        pts = [transform_point(m, p) for p in
               ((bbox[0], bbox[1]), (bbox[2], bbox[1]),
                (bbox[0], bbox[3]), (bbox[2], bbox[3]))]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        return [min(xs), min(ys), max(xs), max(ys)]

    def button_instance(self, el, ln, m, tr, color_attrs,
                        filt_attr, style, where, ct=CT_IDENTITY):
        rec = {'symbol': ln, 'matrix': list(m), 'states': {}, 'hitTestOnly': False}
        name = el.get('name', '')
        if name:
            rec['instanceName'] = name
        alpha_m = re.search(r'opacity="([\d.]+)"', color_attrs)
        if alpha_m:
            rec['alpha'] = float(alpha_m.group(1))
        script = el.find('./x:Actionscript/x:script', NS)
        if script is not None and script.text:
            rec['script'] = ' '.join(script.text.split())
        # 检查 up 态是否为空（hitTest-only 热区按钮）
        up_bbox = self.symbol_bbox(ln, 0)
        hit_bbox = self.symbol_bbox(ln, 3)
        if up_bbox is None:
            rec['hitTestOnly'] = True
            hb = transform_rect(m, 0, 0)
            if hit_bbox:
                # hit_bbox 已是 symbol 局部 bbox -> 需再过实例矩阵
                hb = self._rect_by_matrix(m, hit_bbox)
            rec['stageRect'] = hb
            rec['hitRect'] = hb
            self.skipped.append({'symbol': ln, 'reason': 'hitTestOnly'})
            self.buttons.append(rec)
            return ''
        for si, sname in enumerate(BUTTON_STATES[:3]):
            try:
                body = self.render_symbol(ln, si, ln + ':' + sname, ct=ct)
            except Unsupported as ex:
                self.note_unsupported(str(ex), ln + ':' + sname)
                continue
            if not body:
                continue
            rec['states'][sname] = body  # 调用方决定写文件或内联
        rec['upBody'] = rec['states'].get('up', '')
        rec['stageRect'] = self._rect_by_matrix(m, up_bbox)
        # hitRect：Flash 热区取帧 3（hit 帧）内容；空帧 3 回退 up 态 bbox。
        rec['hitRect'] = self._rect_by_matrix(m, hit_bbox or up_bbox)
        rec['upLocalBBox'] = up_bbox
        self.buttons.append(rec)
        if self.separate_buttons:
            return ''
        attrs = ''.join((tr, color_attrs, filt_attr, style))
        return '<g%s>%s</g>' % (attrs, rec['upBody'])

    # ---- 文本记录 ----
    def text_record(self, el, tag, m):
        w = float(el.get('width', 0))
        h = float(el.get('height', 0))
        attrs = el.find('./x:textRuns/x:DOMTextRun/x:textAttrs/x:DOMTextAttrs', NS)
        chars = el.find('./x:textRuns/x:DOMTextRun/x:characters', NS)
        rec = {
            'id': el.get('name') or el.get('variableName') or '',
            'variableName': el.get('variableName'),
            'kind': 'dynamicText' if tag == 'DOMDynamicText' else 'staticText',
            'matrix': list(m), 'rect': {'w': w, 'h': h},
            'stageRect': transform_rect(m, w, h),
            'font': {
                'face': attrs.get('face') if attrs is not None else None,
                'size': float(attrs.get('size', '12')) if attrs is not None else 12,
                'color': attrs.get('fillColor') if attrs is not None else None,
                'lineSpacing': float(attrs.get('lineSpacing', '0')) if attrs is not None else 0,
                'indent': float(attrs.get('indent', '0')) if attrs is not None else 0,
                'letterSpacing': float(attrs.get('letterSpacing', '0')) if attrs is not None else 0,
            },
            'multiline': el.get('lineType') == 'multiline',
            'html': el.get('renderAsHTML') == 'true',
            'selectable': el.get('isSelectable') == 'true',
            'sampleText': (chars.text or '') if chars is not None else '',
            'layer': None,
        }
        return rec


# ---------- 顶层导出 ----------

def sha256_file(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def export(library, symbol, frame, stage, out_dir, portrait_symbols, button_ids,
           separate_buttons=False):
    r = Renderer(library, portrait_symbols)
    r.separate_buttons = separate_buttons
    root = r.load(symbol)
    # 帧 label 校验
    label = None
    for fr in root.findall('.//x:DOMFrame', NS):
        if int(fr.get('index', 0)) == frame and fr.get('name'):
            label = fr.get('name')
    body_parts = []
    layers = root.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS)
    # mask clip 收集（舞台坐标 path 列表）+ 按被遮罩层名记入 clips
    mask_cid = {}      # mask 层索引 -> clipPath def id
    masked_name = {}   # mask 层索引 -> 被遮罩层名（首个）
    for li, layer in enumerate(layers):
        pi = layer.get('parentLayerIndex')
        if pi is not None:
            masked_name.setdefault(int(pi), layer.get('name', 'layer%d' % li))
    for li, layer, els in r.frame_elements(root, frame, symbol):
        if layer.get('layerType') == 'mask':
            items = r.elements_to_d(els, symbol + ':mask')
            mask_cid[li] = r.new_def(clip_items_to_xml(items))
            key = 'clip:' + masked_name.get(li, 'mask%d' % li)
            r.clips[key] = ''.join(d for d, _ in items)
            if key == 'clip:外部立绘层':
                r.clips['portraitClip'] = r.clips[key]
    for li, layer, els in r.frame_elements(root, frame, symbol):
        if layer.get('layerType') == 'mask':
            continue
        if els is None or not len(els):
            continue
        lname = layer.get('name', 'layer%d' % li)
        before = (len(r.fields), len(r.buttons), len(r.portraits))
        body = r.elements_to_svg(els, symbol + ':' + lname)
        for rec in r.fields[before[0]:]:
            rec['layer'] = lname
        for rec in r.buttons[before[1]:]:
            rec['layer'] = lname
            if lname in button_ids:
                rec['id'] = button_ids[lname]
        clip_idx = r._mask_index_of(layers, li)
        if clip_idx in mask_cid and body:
            body = '<g clip-path="url(#%s)">%s</g>' % (mask_cid[clip_idx], body)
        for rec in r.portraits[before[2]:]:
            rec['layer'] = lname
            if clip_idx in masked_name or clip_idx is not None:
                rec['clip'] = 'clip:' + masked_name.get(clip_idx, 'mask%d' % clip_idx)
        if body:
            body_parts.append((li, lname, body))
    body_parts.sort(key=lambda t: -t[0])
    body = ''.join('<g data-layer="%s">%s</g>' % (escape(n), b) for _, n, b in body_parts)
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" '
           'width="%d" height="%d">\n<defs>%s</defs>\n%s</svg>\n'
           % (stage[0], stage[1], stage[0], stage[1], ''.join(r.defs), body))
    return r, svg, label


def write_button_svgs(r, out_dir):
    """把 buttons[].states 内的局部 SVG 片段落成文件，回填相对路径。"""
    bdir = Path(out_dir) / 'buttons'
    bdir.mkdir(parents=True, exist_ok=True)
    for rec in r.buttons:
        if rec.get('hitTestOnly'):
            continue
        bid = rec.get('id') or re.sub(r'[^\w-]+', '-', rec['symbol'].split('/')[-1])
        rec['id'] = bid
        bbox = rec.pop('upLocalBBox', None)
        for sname, frag in list(rec['states'].items()):
            pad = 2
            if bbox:
                vb = '%s %s %s %s' % (f(bbox[0] - pad), f(bbox[1] - pad),
                                      f(bbox[2] - bbox[0] + 2 * pad),
                                      f(bbox[3] - bbox[1] + 2 * pad))
            else:
                vb = '0 0 100 100'
            svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s">\n'
                   '<defs>%s</defs>\n%s</svg>\n' % (vb, ''.join(r.defs), frag))
            rel = 'buttons/%s-%s.svg' % (bid, sname)
            (Path(out_dir) / rel).write_text(svg, encoding='utf-8')
            rec['states'][sname] = rel
        rec.pop('upBody', None)


def selftest():
    assert edge_segments('!0 0|40 20') == [((0, 0), (2, 1))]
    segs = edge_segments('!0 0[20 20 40 0')
    assert len(segs) == 1 and len(segs[0]) == 3
    assert abs(num('#FFFFFF.F8') + 0.0015625) < 1e-9  # 负定点: -0.03125/20
    assert multiply((2, 0, 0, 2, 3, 4), IDENTITY) == (2, 0, 0, 2, 3, 4)
    assert transform_point((2, 0, 0, 2, 3, 4), (5, 5)) == (13, 14)
    d = segments_to_d(edge_segments('!0 0|20 0|20 20'))
    assert d.startswith('M0 0L1 0') and 'L1 1' in d
    rv = reverse_segments(edge_segments('!0 0|20 0|20 20'))
    assert rv[0][0] == (1, 1) and rv[-1][-1] == (0, 0)
    r = Renderer('.', [])
    # mask 反例（同 1879 hit 帧结构）：mask 矩形 0..10px，被遮罩内容 -100..200px
    # -> bbox 必须相交为 mask 区；outer 帧 3 仅含该实例 -> bbox=mask+偏移。
    import tempfile
    X = 'xmlns="http://ns.adobe.com/xfl/2008/"'
    # Stroke paint is inside <fill>; passing its SolidColor child would discard
    # the color/alpha and silently turn every authored stroke black.
    stroke_shape = ET.fromstring(('<DOMShape %s><strokes><StrokeStyle index="1">'
        '<SolidStroke weight="2.4"><fill><SolidColor color="#CCCCCC" alpha="0.6"/>'
        '</fill></SolidStroke></StrokeStyle></strokes><edges>'
        '<Edge strokeStyle="1" edges="!0 0|200 0"/></edges></DOMShape>') % X)
    rendered_stroke = r.shape_to_svg(stroke_shape, '', 'selftest stroke')
    assert 'stroke="#CCCCCC"' in rendered_stroke and 'stroke-opacity="0.6000"' in rendered_stroke
    gradient_stroke = ET.fromstring(('<StrokeStyle %s><SolidStroke><fill>'
        '<LinearGradient><matrix><Matrix/></matrix><GradientEntry color="#333333" ratio="0"/>'
        '<GradientEntry color="#EEEEEE" ratio="1"/></LinearGradient></fill></SolidStroke></StrokeStyle>') % X)
    gradient_paint = parse_stroke_style(gradient_stroke)['fill']
    assert gradient_paint['kind'] == 'linear' and gradient_paint['entries'][1]['color'] == '#EEEEEE'
    empty_stroke = ET.fromstring(('<StrokeStyle %s><SolidStroke/></StrokeStyle>') % X)
    assert parse_stroke_style(empty_stroke)['fill']['color'] == '#000000'
    holder = ('<DOMSymbolItem %s><timeline><DOMTimeline><layers>'
              '<DOMLayer name="m" layerType="mask"><frames><DOMFrame index="0">'
              '<elements><DOMShape><edges><Edge fillStyle1="1" edges="'
              '!0 0|200 0|200 200|0 200|0 0"/></edges></DOMShape></elements>'
              '</DOMFrame></frames></DOMLayer>'
              '<DOMLayer name="c" parentLayerIndex="0"><frames><DOMFrame index="0">'
              '<elements><DOMShape><edges><Edge fillStyle1="1" edges="'
              '!-2000 -2000|4000 -2000|4000 4000|-2000 4000|-2000 -2000"/>'
              '</edges></DOMShape></elements></DOMFrame></frames></DOMLayer>'
              '</layers></DOMTimeline></timeline></DOMSymbolItem>') % X
    outer = ('<DOMSymbolItem %s><timeline><DOMTimeline><layers>'
             '<DOMLayer name="l"><frames>'
             '<DOMFrame index="0"><elements/></DOMFrame>'
             '<DOMFrame index="3"><elements>'
             '<DOMSymbolInstance libraryItemName="holder">'
             '<matrix><Matrix tx="5" ty="5"/></matrix>'
             '</DOMSymbolInstance></elements></DOMFrame>'
             '</frames></DOMLayer></layers></DOMTimeline></timeline>'
             '</DOMSymbolItem>') % X
    with tempfile.TemporaryDirectory() as td:
        lib = Path(td)
        (lib / 'holder.xml').write_text(holder, encoding='utf-8')
        (lib / 'outer.xml').write_text(outer, encoding='utf-8')
        r2 = Renderer(lib, [])
        assert r2.symbol_bbox('holder', 0) == [0.0, 0.0, 10.0, 10.0]
        assert r2.symbol_bbox('outer', 3) == [5.0, 5.0, 15.0, 15.0]
        assert r2.symbol_bbox('outer', 0) is None
    gid = r.gradient_def(
        {'kind': 'linear', 'matrix': IDENTITY, 'spread': 'extend', 'focal': 0,
         'entries': [{'ratio': 0, 'color': '#000000', 'alpha': 1},
                     {'ratio': 1, 'color': '#FFFFFF', 'alpha': 0.5}]})
    assert 'stop-color' in r.defs[-1] and gid in r.defs[-1]
    print('selftest OK')


def main():
    if '--selftest' in sys.argv:
        selftest()
        return 0
    ap = argparse.ArgumentParser(description='XFL -> SVG 装饰导出')
    ap.add_argument('--library', required=True)
    ap.add_argument('--symbol', required=True)
    ap.add_argument('--frame', type=int, default=0)
    ap.add_argument('--stage', default='1024x576')
    ap.add_argument('--out', required=True)
    ap.add_argument('--portrait-symbols', default='对话框肖像,外部立绘层')
    ap.add_argument('--button-ids', default='关闭:close,移动:drag,按钮控制:next',
                    help='层名:按钮id 映射，逗号分隔')
    ap.add_argument('--manifest-name', default='manifest.json')
    ap.add_argument('--layout-name', default='layout.json')
    ap.add_argument('--svg-name', default='source.svg')
    ap.add_argument('--separate-buttons', action='store_true',
                    help='source.svg 不烘焙按钮 up 美术；六张 buttons/*.svg 不变')
    ap.add_argument('--selftest', action='store_true')
    ap.add_argument('--verify', action='store_true', help='只读核验工具、真源与产物闭包')
    args = ap.parse_args()
    sw, sh = (int(v) for v in args.stage.lower().split('x'))
    out_dir = Path(args.out)
    if args.verify:
        manifest = json.loads((out_dir / args.manifest_name).read_text(encoding='utf-8'))
        if bool(manifest['source'].get('separateButtons')) != args.separate_buttons:
            raise ValueError('separateButtons 配方不符，需用与生成一致的参数验证')
        if manifest['toolSha256'] != sha256_file(Path(__file__)):
            raise ValueError('生成器摘要变化，需重新导出')
        source_root = Path(args.library).resolve().parent
        for item in manifest['sources']:
            path = (source_root / item['path']).resolve()
            if not path.is_relative_to(source_root) or sha256_file(path) != item['sha256']:
                raise ValueError('真源摘要不符: ' + item['path'])
        output_root = out_dir.resolve()
        for name, digest in manifest['outputs'].items():
            path = (output_root / name).resolve()
            if not path.is_relative_to(output_root) or sha256_file(path) != digest:
                raise ValueError('产物摘要不符: ' + name)
        actual = {p.relative_to(output_root).as_posix() for p in output_root.rglob('*') if p.is_file()}
        expected = set(manifest['outputs']) | {args.manifest_name}
        if actual != expected:
            raise ValueError('产物集合不符: ' + str(sorted(actual ^ expected)))
        print('verify OK: %d sources, %d outputs' % (len(manifest['sources']), len(expected)))
        return 0
    out_dir.mkdir(parents=True, exist_ok=True)
    bids = dict(kv.split(':', 1) for kv in args.button_ids.split(',') if ':' in kv)
    r, svg, label = export(args.library, args.symbol, args.frame, (sw, sh),
                           out_dir, args.portrait_symbols.split(','), bids,
                           args.separate_buttons)
    (out_dir / args.svg_name).write_text(svg, encoding='utf-8')
    write_button_svgs(r, out_dir)
    layout = {
        'stage': {'width': sw, 'height': sh},
        'source': {'symbol': args.symbol, 'frameIndex': args.frame, 'frameLabel': label},
        'buttonRendering': 'separate' if args.separate_buttons else 'baked-up',
        'fields': r.fields,
        'buttons': [{k: v for k, v in b.items() if k != 'upBody'} for b in r.buttons],
        'portraitSlots': r.portraits,
        'clips': r.clips,
        'skipped': r.skipped,
        'unsupported': r.unsupported,
        'warnings': sorted(r.warnings),
    }
    (out_dir / args.layout_name).write_text(
        json.dumps(layout, ensure_ascii=False, indent=2), encoding='utf-8')
    gen_path = Path(__file__).resolve()
    manifest = {
        'tool': 'tools/xfl-ui-svg/xfl_to_svg.py',
        'toolSha256': sha256_file(gen_path),
        'generatedAt': 'deterministic (no timestamp)',
        'source': {'symbol': args.symbol, 'frameIndex': args.frame,
                   'frameLabel': label, 'stage': [sw, sh],
                   'separateButtons': args.separate_buttons},
        'sources': [{'path': p.relative_to(r.library.parent).as_posix(),
                     'sha256': sha256_file(p)} for p in sorted(r.sources)],
        'outputs': {},
        'skipped': r.skipped, 'unsupported': r.unsupported,
        'warnings': sorted(r.warnings),
    }
    output_names = {args.svg_name, args.layout_name}
    for button in r.buttons:
        if not button.get('hitTestOnly'):
            output_names.update(button['states'].values())
    for name in sorted(output_names):
        manifest['outputs'][Path(name).as_posix()] = sha256_file(out_dir / name)
    (out_dir / args.manifest_name).write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print('wrote %s (%d fields, %d buttons, %d portraits, %d unsupported)'
          % (out_dir, len(r.fields), len(r.buttons), len(r.portraits),
             len(r.unsupported)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
