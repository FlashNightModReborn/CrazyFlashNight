"""Restricted native expansion for the confirmed CF6 floor_lattice vector pattern.

Scope is exactly the r8-rejected structure: patternUnits="userSpaceOnUse"
(patternContentUnits default), no viewBox, a single vector <g> child, an
invertible patternTransform, referenced as the fill of an untransformed
<rect> without stroke. The vector tile content is converted once into a
reusable native symbol whose content is clipped to one tile window — the
per-tile, single-pass clip is the observed SVG pattern semantic (verified
against a real browser engine on 2026-10-21 with a 3-tile-wide translucent
probe: interior alpha stayed single-pass). Tile instances are placed on the
source lattice patternTransform*(x+i*w, y+j*h) covering the paint rect and
then masked by the original paint geometry, so no tile art spills outside
the painted shape. Group opacity/fill-opacity keep the converter's existing
pattern-opacity wrapper. Anything outside this structure raises ValueError;
no style is silently dropped, no repeated unit is baked into a new PNG.
"""
import copy
import math
import re
import xml.etree.ElementTree as ET

MAX_TILES = 256
SVG = '{http://www.w3.org/2000/svg}'


def lattice_tiles(base, pattern, bbox):
    """Tile indices and instance matrices covering bbox (paint-node local space)."""
    if pattern.get('patternUnits') != 'userSpaceOnUse' or pattern.get('patternContentUnits', 'userSpaceOnUse') != 'userSpaceOnUse':
        raise ValueError('non-user-space pattern requires explicit support')
    if pattern.get('viewBox') is not None:
        raise ValueError('pattern viewport requires explicit support')
    if base.style(pattern).get('overflow', 'hidden') != 'hidden':
        raise ValueError('visible-overflow vector patterns require explicit support')
    try:
        width = float(pattern.get('width'))
        height = float(pattern.get('height'))
        x0 = float(pattern.get('x', 0))
        y0 = float(pattern.get('y', 0))
    except (TypeError, ValueError):
        raise ValueError('vector pattern requires numeric tile geometry')
    if not all(math.isfinite(v) for v in (width, height, x0, y0)) or width <= 0 or height <= 0:
        raise ValueError('invalid vector pattern tile size')
    placement = base.transform(pattern.get('patternTransform'))
    if not all(math.isfinite(v) for v in placement):
        raise ValueError('nonfinite patternTransform')
    a, b, c, d, e, f = placement
    det = a * d - b * c
    if abs(det) < 1e-12:
        raise ValueError('singular patternTransform')
    minx, miny, maxx, maxy = bbox
    if not all(math.isfinite(v) for v in bbox) or maxx < minx or maxy < miny:
        raise ValueError('invalid paint bounds for vector pattern')
    ia, ib, ic, id_ = d / det, -b / det, -c / det, a / det

    def to_pattern(p):
        ux, uy = p[0] - e, p[1] - f
        return ia * ux + ic * uy, ib * ux + id_ * uy

    grid = [to_pattern(p) for p in ((minx, miny), (minx, maxy), (maxx, miny), (maxx, maxy))]
    gx0, gx1 = min(p[0] for p in grid), max(p[0] for p in grid)
    gy0, gy1 = min(p[1] for p in grid), max(p[1] for p in grid)
    i0, i1 = math.floor((gx0 - x0) / width), math.ceil((gx1 - x0) / width) - 1
    j0, j1 = math.floor((gy0 - y0) / height), math.ceil((gy1 - y0) / height) - 1
    if i1 < i0 or j1 < j0:
        raise ValueError('vector pattern coverage is empty')
    if (i1 - i0 + 1) * (j1 - j0 + 1) > MAX_TILES:
        raise ValueError('vector pattern expansion exceeds the reviewed bound')
    matrices = [base.mul(placement, (1, 0, 0, 1, x0 + i * width, y0 + j * height))
                for j in range(j0, j1 + 1) for i in range(i0, i1 + 1)]
    return matrices, {'tile': [width, height], 'origin': [x0, y0], 'patternTransform': list(placement),
                      'paintBounds': [minx, miny, maxx, maxy], 'columns': [i0, i1], 'rows': [j0, j1],
                      'tileInstances': len(matrices)}



def split_floor_union(base, clip):
    """Split only the reviewed same-winding nonzero floor-cell UNION into fills.

    The generic legacy compound-path writer assumes evenodd and guesses holes
    from each contour's first vertex. These floor cells overlap at seams, so a
    cell corner can lie inside its neighbour without that cell being a hole.
    Independent native filled rects preserve the union without changing that
    shared writer or the original SVG.
    """
    if not re.fullmatch(r'n[0-9]+floor_union_(?:1959|1978|1986)', clip.get('id', '')):
        return None
    if clip.tag != SVG+'clipPath' or set(clip.attrib) != {'id'} or len(clip) != 1:
        raise ValueError('floor union requires one untransformed clip path')
    path = clip[0]
    if path.tag != SVG+'path' or set(path.attrib) != {'d', 'clip-rule'} or path.get('clip-rule') != 'nonzero':
        raise ValueError('floor union requires explicit nonzero path')
    parts = base.primitive(path)
    if not 1 <= len(parts) <= 64:
        raise ValueError('floor union rectangle count outside reviewed bound')
    rects = []; orientation = None
    for start, segments, closed in parts:
        if not closed or any(segment[0] != 'L' for segment in segments):
            raise ValueError('floor union contour must be a closed straight rectangle')
        points = [start]+[segment[-1] for segment in segments]
        if points[-1] == points[0]:points.pop()
        if len(points) != 4 or len(set(points)) != 4 or not all(math.isfinite(v) for point in points for v in point):
            raise ValueError('floor union requires four finite distinct corners')
        xs, ys = sorted({p[0] for p in points}), sorted({p[1] for p in points})
        rectangle = len(xs)==2 and len(ys)==2 and set(points)=={(x,y) for x in xs for y in ys}
        edges = list(zip(points,points[1:]+points[:1]))
        turns = [(points[(i+1)%4][0]-points[i][0])*(points[(i+2)%4][1]-points[(i+1)%4][1])
                 -(points[(i+1)%4][1]-points[i][1])*(points[(i+2)%4][0]-points[(i+1)%4][0]) for i in range(4)]
        if not all(v>0 for v in turns) and not all(v<0 for v in turns):
            raise ValueError('floor union requires convex non-self-crossing cells')
        area = sum(a[0]*b[1]-b[0]*a[1] for a,b in edges)
        sign = 1 if area>0 else -1
        if area==0 or orientation is not None and sign!=orientation:
            raise ValueError('floor union holes or mixed contour winding rejected')
        orientation = sign
        if rectangle:
            rects.append(ET.Element(SVG+'rect',{'x':base.fmt(xs[0]),'y':base.fmt(ys[0]),
                'width':base.fmt(xs[1]-xs[0]),'height':base.fmt(ys[1]-ys[0])}))
        else:
            # 1978/1986 have one right-corner cut cell. Keep its exact four vertices;
            # replacing it by a bounding rectangle would fill outside the original floor.
            rects.append(ET.Element(SVG+'polygon',{'points':' '.join(base.fmt(x)+','+base.fmt(y) for x,y in points)}))
    return rects


def candidate_class(api):
    base = api.base

    class PatternCandidate(api.Candidate):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self.floor_union_reports = []
            for node in list(self.root.iter()):
                rects = split_floor_union(base, node)
                if rects is None:continue
                for child in list(node):node.remove(child)
                node.extend(rects)
                self.floor_union_reports.append({'id':node.get('id'),'cells':len(rects),
                    'policy':'same-winding nonzero union preserved as independent native rect/convex-corner fills'})

        def vector_pattern(self, node, attrs, pattern, mask_mode):
            if mask_mode is True:
                raise ValueError('pattern luminance masks require explicit support')
            if api.tag(node) != 'rect':
                raise ValueError('vector pattern fill is only reviewed for rect paint shapes')
            if node.get('transform'):
                raise ValueError('vector pattern on a transformed paint node requires review')
            if attrs.get('stroke', 'none') != 'none':
                raise ValueError('pattern fill plus stroke needs separated paints')
            children = list(pattern)
            if len(children) != 1 or api.tag(children[0]) != 'g':
                raise ValueError('vector pattern requires exactly one <g> tile child')
            x, y = float(node.get('x', 0)), float(node.get('y', 0))
            width, height = float(node.get('width')), float(node.get('height'))
            matrices, info = lattice_tiles(base, pattern, (x, y, x + width, y + height))
            content = self.walk_native(children[0], {}, False)
            if not content:
                raise ValueError('vector pattern tile converted to no native content')
            tile_clip = ET.Element(SVG + 'rect', {'x': '0', 'y': '0',
                                                  'width': base.fmt(info['tile'][0]), 'height': base.fmt(info['tile'][1])})
            tile = self.instance([self.instance(content, 'vector-pattern-content', name='content'),
                                  self.instance(self.primitive(tile_clip, {'fill': '#FFFFFF'}), 'vector-pattern-tile-clip', name='maskShape')],
                                 'vector-pattern-tile-' + (pattern.get('id') or 'anon'),
                                 script='stop();content.setMask(maskShape);')
            tile_name = tile.get('libraryItemName')
            placed = []
            for value in matrices:
                instance = api.E('DOMSymbolInstance', {'libraryItemName': tile_name, 'symbolType': 'movie clip'})
                api.matrix(instance, value)
                placed.append(instance)
            paint_mask = self.instance(self.primitive(copy.deepcopy(node), {'fill': '#FFFFFF'}),
                                       'vector-pattern-paint-clip', name='maskShape')
            lattice = self.instance(placed, 'vector-pattern-lattice', name='content')
            wrapped = self.instance([lattice, paint_mask], 'vector-pattern-' + (pattern.get('id') or 'anon'),
                                    script='stop();content.setMask(maskShape);')
            alpha = float(attrs.get('opacity', 1)) * float(attrs.get('fill-opacity', 1))
            if alpha != 1:
                wrapped = self.instance([wrapped], 'pattern-opacity', alpha=alpha)
            self.pattern_reports.append(dict({'id': pattern.get('id'), 'kind': 'native-vector-lattice',
                                              'policy': 'one reusable clipped native tile symbol instanced on the source lattice, masked by the original paint geometry; per-tile single-pass clip verified against a real browser engine; actual Flash rendering comparison still required'},
                                             **info))
            return [wrapped]

        def primitive(self, node, attrs, mask_mode=False):
            match = re.fullmatch(r'url\(#([^)]*)\)', attrs.get('fill', ''))
            pattern = self.byid.get(match.group(1)) if match else None
            if pattern is not None and api.tag(pattern) == 'pattern':
                images = [n for n in pattern if api.tag(n) == 'image']
                if not (len(images) == 1 and len(list(pattern)) == 1):
                    return self.vector_pattern(node, attrs, pattern, mask_mode)
            return super().primitive(node, attrs, mask_mode)

    return PatternCandidate
