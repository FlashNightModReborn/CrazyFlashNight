"""Assemble the submitted AK47 artwork as editable native XFL; publish with CS6."""
from __future__ import annotations

import argparse
from collections import Counter
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET
from fontTools.pens.basePen import BasePen
from fontTools.svgLib.path import parse_path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/tesla-map-assets'))
from native_vector import svg_to_xfl_legacy as base
sys.path.insert(0, str(ROOT / 'tools/asset-metrology'))
from xfl_geometry import segments as edge_segments

CONFIG = json.loads(Path(__file__).with_name('assembly.json').read_text('utf-8'))
N = '{' + base.NS + '}'
NS = {'x': base.NS}
E = base.E
PREFIX = CONFIG['namespace']
OWNED = ROOT / CONFIG['owner']
INHERIT = {'fill', 'stroke', 'stroke-width', 'fill-opacity', 'stroke-opacity',
           'stroke-linecap', 'stroke-linejoin', 'fill-rule'}


class SourcePen(BasePen):
    def __init__(self):
        super().__init__(None)
        self.paths, self.segments = [], []
        self.current = self.start = None

    def _moveTo(self, point):
        self.current = self.start = point
        self.segments = []

    def _lineTo(self, point):
        self.segments.append(('L', point))
        self.current = point

    def _qCurveToOne(self, control, end):
        self.segments.append(('Q', control, end))
        self.current = end

    def _curveToOne(self, first, second, end):
        self.segments.extend(base.cubic_q(self.current, first, second, end, tol=.025))
        self.current = end

    def _closePath(self):
        if self.current != self.start:
            self._lineTo(self.start)
        self.paths.append((self.start, self.segments, True))

    def _endPath(self):
        self.paths.append((self.start, self.segments, False))


legacy_primitive = base.primitive


def primitive(element):
    if base.tag(element) == 'path' and re.search('[Aa]', element.get('d', '')):
        pen = SourcePen()
        parse_path(element.get('d'), pen)
        return pen.paths
    return legacy_primitive(element)


base.primitive = primitive


def item_id(name):
    # CS6 parses the suffix as a signed integer and clamps oversized hashes.
    return '6af80000-' + format(4096 + int(hashlib.sha256(name.encode('utf-8')).hexdigest()[:4], 16), '08x')


def xml_bytes(element):
    ET.indent(element, space='  ')
    return ET.tostring(element, encoding='utf-8', xml_declaration=True) + b'\n'


def canonical(element):
    """Compare native save semantics, including Flash's fixed-point quantization."""
    tag = base.tag(element)
    if tag == 'DOMShape' and element.find(N+'fills') is not None:
        filled = [e for e in element.findall('./x:edges/x:Edge', NS)
                  if e.get('fillStyle0','0') != '0' or e.get('fillStyle1','0') != '0']
        segments = [s for edge in filled for s in edge_segments(edge.get('edges',''))]
        counts = Counter(segments)
        # A straight path traversed both ways has exactly zero fill winding.
        # CS6 drops this unused black default fill on the second native save.
        if segments and all(len(s) == 2 and counts[s] == counts[tuple(reversed(s))] for s in segments):
            element = copy.deepcopy(element)
            element.remove(element.find(N+'fills'))
            for edge in element.findall('./x:edges/x:Edge', NS):
                edge.attrib.pop('fillStyle0',None)
                edge.attrib.pop('fillStyle1',None)
    if tag == 'transformationPoint':
        return None
    if tag == 'matrix' and len(element) == 1:
        child = element[0]
        if all(float(child.get(k, default)) == float(default) for k, default in
               {'a':1,'b':0,'c':0,'d':1,'tx':0,'ty':0}.items()):
            return None
    if tag == 'edges':
        grouped = {}
        for child in element:
            assert base.tag(child) == 'Edge'
            key = tuple(sorted((k,v) for k,v in child.attrib.items() if k != 'edges'))
            lines = [tuple(tuple(round(v*20) for v in p) for p in segment)
                     for segment in edge_segments(child.get('edges', ''))]
            if child.get('fillStyle0','0') == child.get('fillStyle1','0') == '0':
                lines = list({min(s,tuple(reversed(s))) for s in lines})
            grouped.setdefault(key, []).extend(lines)
        return tag, tuple(sorted((key, tuple(sorted(value))) for key,value in grouped.items()))
    ignored = {'itemID', 'lastModified', 'lastUniqueIdentifier', 'current', 'isSelected',
               'selected', 'centerPoint3DX', 'centerPoint3DY'}
    defaults = {
        'DOMFrame': {'duration': '1'},
        'DOMSymbolItem': {'linkageExportInFirstFrame': 'true'},
        'DOMSymbolInstance': {'firstFrame': '0'},
        'LinearGradient': {'spreadMethod': 'extend'},
        'RadialGradient': {'spreadMethod': 'extend', 'focalPointRatio': '0'},
        'GradientEntry': {'color': '#000000', 'alpha': '1'},
        'SolidColor': {'color': '#000000', 'alpha': '1'},
        'SolidStroke': {'weight': '1', 'caps': 'round', 'joints': 'round'},
        'Matrix': {'a': '1', 'b': '0', 'c': '0', 'd': '1', 'tx': '0', 'ty': '0'},
    }
    values = dict(defaults.get(tag, {}))
    values.update({k:v for k,v in element.attrib.items() if k not in ignored})
    normalized = {}
    for key, value in values.items():
        if tag == 'Edge' and key == 'edges':
            normalized[key] = tuple(sorted(tuple(tuple(round(v*20) for v in p) for p in segment)
                                           for segment in edge_segments(value)))
            continue
        if re.fullmatch(base.NUM, value):
            number = float(value)
            grid = None
            if tag == 'Matrix': grid = 20 if key in ('tx', 'ty') else 65536
            elif tag in ('GradientEntry', 'SolidColor', 'RadialGradient') and key in ('alpha', 'ratio', 'focalPointRatio'): grid = 255
            elif tag == 'Color' and key.endswith('Multiplier'): grid = 256
            elif tag == 'SolidStroke' and key == 'weight': grid = 20
            marker = 'native-alpha-percent' if tag == 'Color' else 'native-grid'
            normalized[key] = (marker, grid, round(number*grid)) if grid else number
        else:
            normalized[key] = value
    children = tuple(c for child in element if (c := canonical(child)) is not None)
    return tag, tuple(sorted(normalized.items())), (element.text or '').strip(), children


def equivalent(first, second):
    if isinstance(first, tuple) and isinstance(second, tuple):
        if len(first) != len(second):
            return False
        if len(first) == 3 and first[0] == second[0] and first[0] in ('native-grid', 'native-alpha-percent'):
            tolerance = 3 if first[0] == 'native-alpha-percent' else 1
            return first[1] == second[1] and abs(first[2] - second[2]) <= tolerance
        return all(equivalent(a, b) for a, b in zip(first, second))
    return first == second


def matrix(element, values=base.I):
    E('Matrix', dict(zip(('a', 'b', 'c', 'd', 'tx', 'ty'), map(base.fmt, values))),
      E('matrix', parent=element))


def instance(name, values=base.I, graphic=True, alpha=1, instance_name=None):
    attrs = {'libraryItemName': name}
    if graphic:
        attrs.update(symbolType='graphic', loop='single frame', firstFrame='0')
    if instance_name:
        attrs['name'] = instance_name
    out = E('DOMSymbolInstance', attrs)
    matrix(out, values)
    E('Point', parent=E('transformationPoint', parent=out))
    if alpha != 1:
        E('Color', {'alphaMultiplier': base.fmt(alpha)}, E('color', parent=out))
    return out


def frame(index, contents=(), duration=1, stop=False):
    out = E('DOMFrame', {'index': index, 'duration': duration, 'keyMode': '9728'})
    if stop:
        E('script', parent=E('Actionscript', parent=out)).text = 'stop();'
    E('elements', parent=out).extend(contents)
    return out


def layer(name, frames, **attrs):
    out = E('DOMLayer', {'name': name, 'color': '#4FFF4F', **attrs})
    E('frames', parent=out).extend(frames)
    return out


def symbol(name, layers, graphic=True, linkage=None):
    attrs = {'name': name, 'itemID': item_id(name)}
    if graphic:
        attrs['symbolType'] = 'graphic'
    if linkage:
        attrs.update(linkageExportForAS='true', linkageIdentifier=linkage,
                     linkageExportInFirstFrame='true')
    out = E('DOMSymbolItem', attrs)
    E('layers', parent=E('DOMTimeline', {'name': name.rsplit('/', 1)[-1]},
                         E('timeline', parent=out))).extend(layers)
    return out


class Artwork(base.Writer):
    """Extend the retained writer only for this checked SVG's use/clipping/focus."""
    def __init__(self, source):
        super().__init__(source)
        self.by_id = {e.get('id'): e for e in self.root.iter() if e.get('id')}
        self.symbols = {}

    def shape(self, element, attrs, transform):
        self.current_geometry = element
        return super().shape(element, attrs, transform)

    def geometry_bounds(self):
        points = []
        for current, segments, _ in base.primitive(self.current_geometry):
            points.append(current)
            for segment in segments:
                end = segment[-1]
                points.append(end)
                if segment[0] == 'Q':
                    control = segment[1]
                    for axis in (0, 1):
                        denominator = current[axis] - 2 * control[axis] + end[axis]
                        if denominator:
                            t = (current[axis] - control[axis]) / denominator
                            if 0 < t < 1:
                                points.append(tuple((1-t)**2 * current[k] + 2*(1-t)*t*control[k]
                                                    + t*t*end[k] for k in (0, 1)))
                current = end
        return (min(p[0] for p in points), min(p[1] for p in points),
                max(p[0] for p in points), max(p[1] for p in points))

    def paint(self, parent, fill, attributes, transform, alpha):
        match = re.fullmatch(r'url\(#([^)]*)\)', fill)
        gradient = self.grads.get(match[1]) if match else None
        if gradient is None:
            return super().paint(parent, fill, attributes, transform, alpha)
        units = gradient.get('gradientUnits', 'objectBoundingBox')
        assert units in ('userSpaceOnUse', 'objectBoundingBox')
        gm = transform
        if units == 'objectBoundingBox':
            x0, y0, x1, y1 = self.geometry_bounds()
            assert x1 > x0 and y1 > y0
            gm = base.mul(gm, (x1-x0, 0, 0, y1-y0, x0, y0))
        gm = base.mul(gm, base.transform(gradient.get('gradientTransform')))

        def coordinate(key, default, axis):
            raw = gradient.get(key, default)
            if raw.endswith('%'):
                return float(raw[:-1])/100 * (1 if units == 'objectBoundingBox' else [1200, 450][axis])
            return float(raw)

        if base.tag(gradient) == 'linearGradient':
            p = coordinate('x1', '0%', 0), coordinate('y1', '0%', 1)
            q = coordinate('x2', '100%', 0), coordinate('y2', '0%', 1)
            dx, dy = q[0] - p[0], q[1] - p[1]
            native = E('LinearGradient', {'spreadMethod': 'extend'}, parent)
            matrix(native, base.mul(gm, (dx/1638.4, dy/1638.4, -dy/1638.4,
                                         dx/1638.4, (p[0]+q[0])/2, (p[1]+q[1])/2)))
        else:
            assert base.tag(gradient) == 'radialGradient' and units == 'userSpaceOnUse'
            cx, cy, radius = [float(gradient.get(k)) for k in ('cx', 'cy', 'r')]
            fx, fy = float(gradient.get('fx', cx)), float(gradient.get('fy', cy))
            dx, dy = fx - cx, fy - cy
            focal = math.hypot(dx, dy) / radius
            assert radius > 0 and 0 <= focal < 1 and not gradient.get('href')
            angle = math.atan2(dy, dx)
            c, s = math.cos(angle) * radius / 819.2, math.sin(angle) * radius / 819.2
            native = E('RadialGradient', {'focalPointRatio': base.fmt(focal),
                                          'spreadMethod': 'extend'}, parent)
            matrix(native, base.mul(gm, (c, s, -s, c, cx, cy)))
        for stop in gradient:
            ratio = float(stop.get('offset'))
            E('GradientEntry', {'ratio': base.fmt(ratio),
                               'color': base.color(stop.get('stop-color')),
                               'alpha': base.fmt(alpha * float(stop.get('stop-opacity', 1)))}, native)

    def walk(self, element, parent_style=None, parent_matrix=base.I):
        kind = base.tag(element)
        if kind in {'defs', 'animate', 'metadata', 'title', 'desc'}:
            return []
        attrs = {k: v for k, v in (parent_style or {}).items() if k in INHERIT}
        attrs.update(element.attrib)
        transform = base.mul(parent_matrix, base.transform(element.get('transform')))
        if attrs.get('display') == 'none':
            return []
        if element.get('clip-path'):
            clip_id = re.fullmatch(r'url\(#([^)]*)\)', element.get('clip-path'))[1]
            clip = self.by_id[clip_id]
            assert clip.get('clipPathUnits', 'userSpaceOnUse') == 'userSpaceOnUse'
            name = PREFIX + '/裁剪/' + element.get('id', clip_id)
            local = copy.deepcopy(element)
            local.attrib.pop('clip-path')
            mask = []
            for child in clip:
                mask.extend(self.walk(child, {'fill': '#FFFFFF', 'stroke': 'none'}, transform))
            art = self.walk(local, parent_style, parent_matrix)
            self.symbols[name] = symbol(name, [
                layer('木纹原生遮罩', [frame(0, mask)], layerType='mask', locked='true'),
                layer('木纹', [frame(0, art)], parentLayerIndex='0', locked='true')])
            return [instance(name)]
        if kind == 'use':
            ref = element.get('{http://www.w3.org/1999/xlink}href') or element.get('href')
            assert ref and ref.startswith('#')
            placement = base.mul(transform, (1, 0, 0, 1, float(element.get('x', 0)),
                                             float(element.get('y', 0))))
            return self.walk(self.by_id[ref[1:]], attrs, placement)
        if kind in {'g', 'svg'}:
            shapes = []
            for child in element:
                shapes.extend(self.walk(child, attrs, transform))
            return shapes
        assert kind in {'path', 'circle', 'ellipse', 'rect', 'line', 'polygon', 'polyline'}, kind
        shape = self.shape(element, attrs, transform)
        return [shape] if shape is not None else []


def generate():
    assert hashlib.sha256((ROOT / CONFIG['source']).read_bytes()).hexdigest() == CONFIG['sourceSHA256']
    writer = Artwork(ROOT / CONFIG['source'])
    assert writer.root.get('viewBox') == '0 0 1200 450'
    assert float(ET.parse(OWNED / 'DOMDocument.xml').getroot().get('frameRate')) == CONFIG['fps']
    groups = list(writer.by_id['weapon-ak47-fire-kylin'])
    parts = []
    eye = None
    for group in groups:
        if group.get('id') == 'eye-glow-loop':
            eye = group
            continue
        name = PREFIX + '/分件/' + group.get('id')
        writer.symbols[name] = symbol(name, [layer(group.get('id'), [frame(0, writer.walk(group))])])
        parts.append(name)
    assert eye is not None
    eye_layers, frozen_layers = [], []
    for group in eye:
        animation = group.find('{http://www.w3.org/2000/svg}animate')
        assert animation is not None and animation.get('dur') == '1.2s'
        assert animation.get('keyTimes') == '0;0.25;0.5;0.75;1'
        assert animation.get('attributeName') == 'opacity'
        values = list(map(float, animation.get('values').split(';')))
        assert len(values) == 5 and values[0] == values[-1]
        original = copy.deepcopy(group)
        original.attrib.pop('opacity', None)
        name = PREFIX + '/分件/' + group.get('id')
        writer.symbols[name] = symbol(name, [layer(group.get('id'), [frame(0, writer.walk(original))])])
        frames = []
        for index in range(CONFIG['cycleFrames']):
            phase = index * 4 / CONFIG['cycleFrames']
            low = int(phase)
            alpha = values[low] + (values[low + 1] - values[low]) * (phase - low)
            frames.append(frame(index, [instance(name, alpha=alpha)]))
        eye_layers.append(layer(group.get('id'), frames))
        frozen_layers.append(layer(group.get('id'), [frame(0, [instance(name, alpha=values[2])])]))
    eye_name, frozen = PREFIX + '/眼焰循环', PREFIX + '/眼焰定格'
    writer.symbols[eye_name] = symbol(eye_name, list(reversed(eye_layers)), graphic=False)
    writer.symbols[frozen] = symbol(frozen, list(reversed(frozen_layers)))
    body = PREFIX + '/枪身'
    writer.symbols[body] = symbol(body, [layer(p.rsplit('/', 1)[-1], [frame(0, [instance(p)])])
                                          for p in reversed(parts)])
    static, animated = PREFIX + '/00_静态总装', PREFIX + '/动画'
    for name, effect, is_graphic in [(static, frozen, True), (animated, eye_name, False)]:
        writer.symbols[name] = symbol(name, [
            layer('眼焰', [frame(0, [instance(effect, graphic=is_graphic, instance_name=None if is_graphic else '眼焰')])]),
            layer('枪身', [frame(0, [instance(body)])])], graphic=is_graphic)
    scale = round(CONFIG['oldContourWidth'] / CONFIG['sourceContourWidth'] * 65536) / 65536
    gx, gy = CONFIG['grip']
    tx, ty = round(-gx * scale * 20) / 20, round(-gy * scale * 20) / 20
    mx, my = CONFIG['muzzle']
    muzzle = (round((mx * scale + tx) * 20) / 20, round((my * scale + ty) * 20) / 20)
    name = PREFIX + '/' + CONFIG['linkage']
    writer.symbols[name] = symbol(name, [
        layer('停止', [frame(0, stop=True)]),
        layer('枪口接口', [frame(0, [instance('Codex/接口/枪口标记',
              (1, 0, 0, 1, *muzzle), graphic=False, instance_name='枪口位置')])]),
        layer('原生分件与眼焰', [frame(0, [instance(animated, (scale, 0, 0, scale, tx, ty),
                                                  graphic=False, instance_name='动画')])])
    ], graphic=False, linkage=CONFIG['linkage'])
    angle = math.radians(CONFIG['iconAngleDegrees'])
    a, b = CONFIG['iconScale'] * math.cos(angle), CONFIG['iconScale'] * math.sin(angle)
    ix, iy = CONFIG['iconFocus']
    crop = (a, b, -b, a, -a * ix + b * iy, -b * ix - a * iy)
    # Keep the icon's moving clip directly under its stopped root. Rotation
    # and the 24px mask live inside that clip, as required by the existing
    # layered Web exporter; the static body uses an identical internal mask.
    icon_eye = PREFIX + '/图标眼焰'
    cropped_eye_layers = []
    for source_layer in reversed(eye_layers):
        cropped_layer = copy.deepcopy(source_layer)
        cropped_layer.set('parentLayerIndex', '0')
        cropped_layer.set('locked', 'true')
        for placement in cropped_layer.findall('.//x:DOMSymbolInstance', NS):
            placement.find('./x:matrix/x:Matrix', NS).attrib.update(
                dict(zip(('a','b','c','d','tx','ty'), map(base.fmt, crop))))
        cropped_eye_layers.append(cropped_layer)
    writer.symbols[icon_eye] = symbol(icon_eye, [
        layer('24像素遮罩', [frame(0, [instance('Codex/图标/24像素遮罩')],
                                     duration=CONFIG['cycleFrames'])], layerType='mask', locked='true'),
        *cropped_eye_layers], graphic=False)
    icon_body = PREFIX + '/图标枪身'
    writer.symbols[icon_body] = symbol(icon_body, [
        layer('24像素遮罩', [frame(0, [instance('Codex/图标/24像素遮罩')])], layerType='mask', locked='true'),
        layer('兽首特写', [frame(0, [instance(body, crop)])], parentLayerIndex='0', locked='true')])
    drop = scale * CONFIG['holderScale']
    dx, dy = CONFIG['displayCenter']
    icon_name = PREFIX + '/' + CONFIG['icon']
    writer.symbols[icon_name] = symbol(icon_name, [
        layer('停止', [frame(0, stop=True)]),
        layer('图标眼焰', [frame(0, [instance(icon_eye, graphic=False, instance_name='眼焰')])]),
        layer('掉落眼焰', [frame(0), frame(1, [instance(eye_name,
              (drop, 0, 0, drop, -dx * drop, -dy * drop), graphic=False, instance_name='眼焰')])]),
        layer('底影与掉落整枪', [frame(0, [instance('Codex/图标/24像素底影'), instance(icon_body)]),
              frame(1, [instance(body, (drop, 0, 0, drop, -dx * drop, -dy * drop))])])
    ], graphic=False, linkage=CONFIG['icon'])
    assert len(eye_layers) == 5
    return writer.symbols, {'scale': scale, 'translation': [tx, ty], 'muzzle': muzzle,
                            'cycleFrames': CONFIG['cycleFrames'], 'fps': CONFIG['fps'],
                            'nativeShapes': writer.shape_count, 'nativeSegments': writer.segment_count}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--report')
    args = parser.parse_args()
    symbols, report = generate()
    changed = []
    for name, root in symbols.items():
        path = OWNED / 'LIBRARY' / (name + '.xml')
        data = xml_bytes(root)
        if not path.exists() or not equivalent(canonical(ET.parse(path).getroot()), canonical(root)):
            changed.append(str(path.relative_to(ROOT)))
            if not args.check:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
    document_path = OWNED / 'DOMDocument.xml'
    text = document_path.read_text('utf-8-sig')
    document = ET.fromstring(text)
    existing = {e.get('href') for e in document.findall('./x:symbols/x:Include', NS)}
    missing = [name for name in symbols if name + '.xml' not in existing]
    if missing:
        changed.append(str(document_path.relative_to(ROOT)))
        if not args.check:
            includes = ''.join('    <Include href="' + name + '.xml" itemID="' + item_id(name) + '"/>\n'
                               for name in sorted(missing))
            assert text.count('</symbols>') == 1
            text = text.replace('</symbols>', includes + '</symbols>', 1)
            document_path.write_text(text, encoding='utf-8', newline='\n')
    report.update(check=args.check, changed=changed, symbols=len(symbols),
                  sourceSHA256=hashlib.sha256((ROOT / CONFIG['source']).read_bytes()).hexdigest())
    if args.report:
        path = ROOT / args.report
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))
    return 1 if args.check and changed else 0


if __name__ == '__main__':
    raise SystemExit(main())
