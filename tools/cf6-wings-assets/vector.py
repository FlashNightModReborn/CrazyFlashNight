"""Wings SVG paint adapter: preserve object-bbox linear/radial paints as native vectors."""
from pathlib import Path
import copy
import importlib.util
import math
import re
import xml.etree.ElementTree as SE
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('wings_gamma_vector', ROOT / 'tools/gamma-echo-assets/build.py')
gamma = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gamma)
base, geo = gamma.base, gamma.geo


class NativePart(gamma.NativePart):
    """Resolve per-element paint bounds without changing archived SVG registration."""
    def paint_shape(self, el, attrs, matrix):
        el, attrs = copy.deepcopy(el), dict(attrs)
        bounds = None
        for paint in ('fill', 'stroke'):
            match = re.fullmatch(r'url\(#([^)]*)\)', attrs.get(paint, ''))
            if not match:
                continue
            original = self.writer.grads[match[1]]
            if original.get('gradientUnits', 'objectBoundingBox') != 'objectBoundingBox':
                continue
            if bounds is None:
                segments = []
                for start, pieces, closed in base.primitive(el):
                    point = start
                    for piece in pieces:
                        segments.append((point, *piece[1:]))
                        point = piece[-1]
                bounds = geo.bounds(segments)
            x0, y0, x1, y1 = bounds
            if not x1 > x0 or not y1 > y0:
                raise ValueError('Degenerate object-bbox paint bounds')
            gradient = copy.deepcopy(original)
            if base.tag(gradient) == 'radialGradient':
                defaults = [('cx', '50%'), ('cy', '50%'), ('r', '50%'),
                            ('fx', original.get('cx', '50%')),
                            ('fy', original.get('cy', '50%')), ('fr', '0')]
            else:
                defaults = [('x1', '0%'), ('y1', '0%'), ('x2', '100%'), ('y2', '0%')]
            for key, default in defaults:
                raw = gradient.get(key, default)
                value = float(raw[:-1]) / 100 if raw.endswith('%') else float(raw)
                if not math.isfinite(value):
                    raise ValueError('Non-finite object-bbox gradient coordinate')
                gradient.set(key, str(value))
            ident = 'wings-paint-' + str(self.serial)
            self.serial += 1
            gradient.set('id', ident)
            gradient.set('gradientUnits', 'userSpaceOnUse')
            bbox = (x1 - x0, 0, 0, y1 - y0, x0, y0)
            transform = base.mul(bbox, base.transform(gradient.get('gradientTransform')))
            gradient.set('gradientTransform', 'matrix(' + ' '.join(map(str, transform)) + ')')
            self.writer.grads[ident] = gradient
            attrs[paint] = 'url(#' + ident + ')'
        shape = self.writer.shape(el, attrs, matrix)
        if shape is None:
            return None
        shape.attrib.pop('isFloating', None)
        shape.set('isDrawingObject', 'true')
        return E.fromstring(SE.tostring(shape))
