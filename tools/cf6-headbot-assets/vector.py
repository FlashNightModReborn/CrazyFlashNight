"""Preclip the authored headbot paints; compact only exact native-grid vertices."""
from pathlib import Path
import importlib.util
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
GUARD = ROOT / 'tools/cf6-guard-assets'
# The existing clipper imports its own paint adapter by the module name vector.
# Load it without allowing the headbot entry module to shadow that dependency.
spec = importlib.util.spec_from_file_location('headbot_guard_paint', GUARD/'vector.py')
paint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(paint)
previous = sys.modules.get('vector')
sys.modules['vector'] = paint
spec = importlib.util.spec_from_file_location('headbot_guard_clip', GUARD/'clipped_vector.py')
clip = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clip)
if previous is None:
    sys.modules.pop('vector', None)
else:
    sys.modules['vector'] = previous


def compact_edges(text):
    """No resampling: remove duplicate / same-direction collinear twip points."""
    if '[' in text:
        return text, 0
    tokens = re.findall(r'[!|]|-?\d+', text)
    groups = []
    for i in range(0, len(tokens), 3):
        op, x, y = tokens[i:i+3]
        if op == '!':
            groups.append([])
        point = (int(x), int(y))
        points = groups[-1]
        if points and points[-1] == point:
            continue
        while len(points) > 1:
            a, b = points[-2:]
            ux, uy = b[0]-a[0], b[1]-a[1]
            vx, vy = point[0]-b[0], point[1]-b[1]
            if ux*vy != uy*vx or ux*vx+uy*vy < 0:
                break
            points.pop()
        points.append(point)
    output = ' '.join(('!' if i == 0 else '|')+str(x)+' '+str(y)
                      for points in groups for i, (x, y) in enumerate(points))
    return output, len(tokens)//3-sum(map(len, groups))


class NativePart(clip.ClippedPart):
    def build(self):
        symbols, report = super().build()
        removed = 0
        for symbol in symbols.values():
            for edge in symbol.findall('.//x:Edge', clip.NS):
                value, count = compact_edges(edge.get('edges'))
                edge.set('edges', value)
                removed += count
        report['removedExactGridVertices'] = removed
        return symbols, report


def original_effect(path, name, origin):
    """Unclipped CF6 vectors retain native quadratic curves and gradients."""
    return paint.wings.NativePart(path, name, origin).build()
