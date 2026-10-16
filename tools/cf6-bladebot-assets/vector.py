"""Bladebot-only SVG adapter: circular holes and reusable vector atlas references."""
from pathlib import Path
import copy
import hashlib
import importlib.util
import math
import re
import xml.etree.ElementTree as SE

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('bladebot_wings_vector', ROOT / 'tools/cf6-wings-assets/vector.py')
wings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wings)
base, geo, gamma = wings.base, wings.geo, wings.gamma


def circular_holes(path):
    """Convert the authored two-semicircle hole to four cubic arcs; reject other arcs."""
    number = r'[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?'
    pattern = re.compile(r'M\s*(' + number + r')[ ,]+(' + number + r')\s*'
        r'A\s*(' + number + r')[ ,]+(' + number + r')[ ,]+0[ ,]+1[ ,]+([01])[ ,]+('
        + number + r')[ ,]+(' + number + r')\s*A\s*(' + number + r')[ ,]+('
        + number + r')[ ,]+0[ ,]+1[ ,]+([01])[ ,]+(' + number + r')[ ,]+(' + number + r')')

    def replace(match):
        x, y, rx, ry, sweep, x2, y2, rx2, ry2, sweep2, xe, ye = map(float, match.groups())
        if not (rx > 0 and rx == ry == rx2 == ry2 and sweep == sweep2 and x == xe and y == ye
                and abs(math.hypot(x2-x, y2-y)-2*rx) < 1e-8):
            raise ValueError('Only the documented circular antipodal hole is supported')
        cx, cy = (x+x2)/2, (y+y2)/2
        start = math.atan2(y-cy, x-cx)
        delta = math.pi/2 * (1 if sweep else -1)
        k = 4/3 * math.tan(delta/4)
        text = ['M' + str(x) + ' ' + str(y)]
        for i in range(4):
            a, b = start + i*delta, start + (i+1)*delta
            p = (cx+rx*math.cos(a), cy+rx*math.sin(a))
            q = (cx+rx*math.cos(b), cy+rx*math.sin(b))
            c1 = (p[0]-k*rx*math.sin(a), p[1]+k*rx*math.cos(a))
            c2 = (q[0]+k*rx*math.sin(b), q[1]-k*rx*math.cos(b))
            text.append('C' + ' '.join(format(v, '.12g') for v in (*c1, *c2, *q)))
        return ' '.join(text)

    result = pattern.sub(replace, path)
    if re.search('[Aa]', result):
        raise ValueError('Unexpected arc: review the frozen vector source')
    return result


class NativePart(wings.NativePart):
    shared_references = {}

    def __init__(self, path, name, origin):
        super().__init__(path, name, origin)
        for element in self.svg.iter():
            if base.tag(element) == 'path' and re.search('[Aa]', element.get('d', '')):
                element.set('d', circular_holes(element.get('d')))

    def contents(self, element, inherited=None, matrix=base.I):
        if base.tag(element) != 'use':
            return super().contents(element, inherited, matrix)
        ref = element.get('href', element.get('{http://www.w3.org/1999/xlink}href', ''))
        if not ref.startswith('#') or ref[1:] not in self.by_id:
            raise ValueError('Only local, resolved vector use references are supported')
        if any(element.get(k) for k in ('width', 'height')):
            raise ValueError('Viewport-sized SVG use requires separate review')
        source = copy.deepcopy(self.by_id[ref[1:]])
        if base.tag(source) != 'g':
            raise ValueError('Expected the approved vector atlas group')
        if any(base.tag(child) == 'use' for child in source.iter()):
            raise ValueError('Nested or cyclic atlas references require separate review')
        source.attrib.pop('id', None)
        digest = hashlib.sha256(SE.tostring(source)).hexdigest()
        name = 'Codex/大刀机器人/碎片图集/' + digest[:16]
        if digest not in self.shared_references:
            child = copy.copy(self)
            child.name, child.symbols, child.serial, child.masks = name, {}, 0, 0
            drawing = child.contents(source)
            child.symbols[name] = gamma.symbol(name, [gamma.layer('共用矢量材质图集', [gamma.frame(elements=drawing)])])
            self.shared_references[digest] = child.symbols
        self.symbols.update(self.shared_references[digest])
        transform = base.mul(matrix, base.transform(element.get('transform')))
        transform = base.mul(transform, (1, 0, 0, 1, float(element.get('x', '0')), float(element.get('y', '0'))))
        return [gamma.instance(name, matrix=transform)]
