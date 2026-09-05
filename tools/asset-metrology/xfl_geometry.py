"""只读 XFL 轮廓测量；不执行帧脚本、补间、滤镜或描边扩张。"""
from __future__ import annotations

import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from xml.sax.saxutils import escape

NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
IDENTITY = (1, 0, 0, 1, 0, 0)
TOKENS = re.compile(r'#[0-9a-fA-F]+(?:\.[0-9a-fA-F]+)?|[+-]?(?:\d+(?:\.\d*)?|\.\d+)|[!|/\[\]S]')
BARE_AMPERSAND = re.compile(r'&(?!#\d+;|#x[0-9A-Fa-f]+;|[A-Za-z][A-Za-z0-9_.:-]*;)')
MARKER = re.compile(r'^(?:(?:枪口位置|弹壳位置|刀口位置|攻击区域)\d*|area)$')


def matrix(value):
    result = tuple(float(value.get(k, IDENTITY[i])) for i, k in enumerate(('a', 'b', 'c', 'd', 'tx', 'ty')))
    if not all(math.isfinite(v) for v in result):
        raise ValueError('矩阵包含非有限值')
    return result


def multiply(left, right):
    a, b, c, d, x, y = left
    e, f, g, h, u, v = right
    return a*e+c*f, b*e+d*f, a*g+c*h, b*g+d*h, a*u+c*v+x, b*u+d*v+y


def point(transform, value):
    a, b, c, d, x, y = transform
    return a*value[0]+c*value[1]+x, b*value[0]+d*value[1]+y


def number(token):
    if not token.startswith('#'):
        result = float(token)
    else:
        whole, _, fraction = token[1:].partition('.')
        integer = int(whole, 16)
        if integer >= 0x800000:
            integer -= 0x1000000
        result = integer + (int(fraction, 16) / 16**len(fraction) if fraction else 0)
    if not math.isfinite(result):
        raise ValueError('轮廓坐标包含非有限值')
    return result / 20


def segments(edge):
    tokens = TOKENS.findall(edge)
    if TOKENS.sub('', edge).strip():
        raise ValueError('不支持的轮廓语法')
    index, current = 0, None
    while index < len(tokens):
        command = tokens[index]
        index += 1
        if command == 'S':
            if index >= len(tokens) or not tokens[index].isdigit():
                raise ValueError('损坏的轮廓选择位')
            index += 1  # 编辑器选择位，不参与几何。
            continue
        if command not in ('!', '|', '/', '[', ']'):
            raise ValueError('不支持的轮廓命令：' + command)
        count = 4 if command in ('[', ']') else 2
        if len(tokens[index:index+count]) != count:
            raise ValueError('轮廓坐标数量不足')
        coordinates = [number(v) for v in tokens[index:index+count]]
        index += count
        end = tuple(coordinates[-2:])
        if command != '!':
            if current is None:
                raise ValueError('轮廓缺少起点')
            yield (current, tuple(coordinates[:2]), end) if count == 4 else (current, end)
        current = end


def bounds(contours):
    points = []
    for segment in contours:
        points.extend((segment[0], segment[-1]))
        if len(segment) == 3:
            p, q, r = segment
            for axis in (0, 1):
                divisor = p[axis]-2*q[axis]+r[axis]
                if divisor:
                    t = (p[axis]-q[axis])/divisor
                    if 0 < t < 1:
                        points.append(tuple((1-t)**2*p[k]+2*(1-t)*t*q[k]+t*t*r[k] for k in (0, 1)))
    if not points:
        raise ValueError('所选帧没有可测量的轮廓')
    return [min(p[0] for p in points), min(p[1] for p in points), max(p[0] for p in points), max(p[1] for p in points)]


class Geometry:
    def __init__(self, library: Path, include_markers=False):
        self.library = library.resolve()
        self.include_markers = include_markers
        self.cache = {}
        self.source_files = set()
        self.skipped = set()
        self.warnings = set()

    def symbol(self, name, frame=0, transform=IDENTITY, stack=()):
        if frame < 0:
            raise ValueError('帧号不能为负')
        if name in stack or len(stack) >= 64:
            raise ValueError('循环引用或过深的符号链：' + name)
        if name not in self.cache:
            path = (self.library / (name + '.xml')).resolve()
            if not path.is_relative_to(self.library):
                raise ValueError('符号路径越出 LIBRARY')
            self.cache[name] = ET.fromstring(BARE_AMPERSAND.sub('&amp;', path.read_text(encoding='utf-8-sig')))
            self.source_files.add(path)
        root = self.cache[name]
        total = max((int(f.get('index', 0))+int(f.get('duration', 1)) for f in root.findall('.//x:DOMFrame', NS)), default=0)
        if frame >= total:
            raise ValueError(f'{name}：帧号 {frame+1} 超出时间轴')
        if root.find('.//x:Actionscript', NS) is not None:
            self.warnings.add('包含 ActionScript；静态测量不执行脚本')
        for layer in root.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS):
            if layer.get('layerType') in ('guide', 'folder'):
                continue
            if layer.get('layerType') == 'mask':
                raise ValueError('遮罩需要专门测量：' + name)
            for f in layer.findall('./x:frames/x:DOMFrame', NS):
                start = int(f.get('index', 0))
                if start <= frame < start+int(f.get('duration', 1)):
                    if frame != start and f.get('tweenType'):
                        raise ValueError('不对补间中间帧猜测插值：' + name)
                    elements = f.find('./x:elements', NS)
                    if elements is not None:
                        for element in elements:
                            yield from self.element(element, transform, stack+(name,))
                    break

    def element(self, element, transform, stack):
        tag = element.tag.rsplit('}', 1)[-1]
        own = element.find('./x:matrix/x:Matrix', NS)
        m = multiply(transform, matrix(own.attrib)) if own is not None else transform
        if element.find('./x:filters', NS) is not None:
            self.warnings.add('包含滤镜；结果不含滤镜扩张')
        color = element.find('./x:color/x:Color', NS)
        if color is not None and color.get('alphaMultiplier') == '0' and float(color.get('alphaOffset', '0')) == 0:
            return
        if tag == 'DOMGroup':
            members = element.find('./x:members', NS)
            if members is not None:
                for child in members:
                    yield from self.element(child, m, stack)
        elif tag == 'DOMSymbolInstance':
            name = element.get('name', '')
            if not self.include_markers and MARKER.fullmatch(name):
                self.skipped.add(name)
                return
            # 子元件只取其声明 firstFrame；不模拟 MovieClip 播放时钟。
            yield from self.symbol(element.get('libraryItemName'), int(element.get('firstFrame', 0)), m, stack)
        elif tag == 'DOMShape':
            for edge in element.findall('./x:edges/x:Edge', NS):
                if any(edge.get(k, '0') != '0' for k in ('fillStyle0', 'fillStyle1', 'strokeStyle')):
                    for segment in segments(edge.get('edges', '')):
                        yield tuple(point(m, p) for p in segment)
        else:
            raise ValueError('不支持的几何元素：' + tag)


def contour_svg(contours, title):
    """诊断 SVG 保留局部坐标；仅描绘轮廓，不作为可回填美术。"""
    bb = bounds(contours)
    paths = []
    for segment in contours:
        coords = [f'{x:.6f},{y:.6f}' for x, y in segment]
        paths.append('M'+coords[0]+('Q'+' '.join(coords[1:]) if len(segment) == 3 else 'L'+coords[1]))
    view = f'{bb[0]-4} {bb[1]-4} {bb[2]-bb[0]+8} {bb[3]-bb[1]+8}'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}">'
            f'<title>{escape(title)}</title><path d="{" ".join(paths)}" '
            'fill="none" stroke="#405a6c" stroke-width="0.2"/></svg>\n')
