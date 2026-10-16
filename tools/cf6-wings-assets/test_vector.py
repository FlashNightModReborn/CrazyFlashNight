"""Check the radial material conversion in source coordinates, independent of Flash pixels."""
import io
import math
from pathlib import Path
from lxml import etree as E
from vector import NativePart

NS = {'x': 'http://ns.adobe.com/xfl/2008/'}


def convert(extra='', paint='fill', transform=''):
    source = '<svg xmlns="http://www.w3.org/2000/svg"><defs><radialGradient id="g" ' + extra + '>'
    source += '<stop offset="0" stop-color="#ffffff" stop-opacity="0.3"/><stop offset="1" stop-color="#000000"/>'
    source += '</radialGradient></defs><rect x="10" y="20" width="200" height="100" '
    source += 'fill="' + ('url(#g)' if paint == 'fill' else 'none') + '" '
    if paint == 'stroke':
        source += 'stroke="url(#g)" stroke-width="2" '
    source += 'opacity="0.5" ' + paint + '-opacity="0.4" transform="' + transform + '"/></svg>'
    symbols, _ = NativePart(io.StringIO(source), 'test', (0, 0)).build()
    return next(r for root in symbols.values() for r in root.findall('.//x:RadialGradient', NS))


def matrix(gradient):
    m = gradient.find('x:matrix/x:Matrix', NS)
    return [float(m.get(key, str(default))) for key, default in [('a', 1), ('b', 0), ('c', 0), ('d', 1), ('tx', 0), ('ty', 0)]]


def close(actual, expected):
    assert all(math.isclose(a, b, abs_tol=1e-6) for a, b in zip(actual, expected)), (actual, expected)


g = convert()
close(matrix(g), [100 / 819.2, 0, 0, 50 / 819.2, 110, 70])
assert math.isclose(float(g.find('x:GradientEntry', NS).get('alpha')), 0.06)
close(matrix(convert(transform='matrix(0 2 -3 0 50 80)')), [0, 200 / 819.2, -150 / 819.2, 0, -160, 300])
close(matrix(convert(paint='stroke')), [100 / 819.2, 0, 0, 50 / 819.2, 110, 70])
try:
    convert('fx="25%"')
except ValueError as error:
    assert 'Only centered radial gradients' in str(error)
else:
    raise AssertionError('Unsupported displaced focus must not silently lose its geometry')
for part in (Path(__file__).resolve().parents[2] / 'flashswf/arts/new/Codex素材源稿/CF6Wings-R3/parts').glob('*.svg'):
    symbols, stats = NativePart(part, 'test/' + part.stem, (0, 0)).build()
    assert stats['shapes'] > 0 and stats['masks'] == 2
    assert all(not root.findall('.//x:BitmapFill', NS) for root in symbols.values())
print('Wings vectors: default ellipse, affine transform, stroke, opacity, rejection and twelve source parts passed')
