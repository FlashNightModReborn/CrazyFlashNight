"""Static geometry/reference fixtures for the floor_lattice vector-pattern adapter.

These fixtures validate tile coverage, lattice matrices, mask wiring, negative
origins and every rejection branch against the static contract only. They are
not a Flash substitute: actual rendering parity remains root's CS6/browser
comparison after native import.
"""
from pathlib import Path
import importlib.util
import math
import tempfile
import unittest
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
NV = HERE.parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


api = load('cf6_native_vector_fixture', NV / 'build-a01.py')
adapter = load('cf6_pattern_adapter_fixture', HERE / 'pattern_adapter.py')
PatternCandidate = adapter.candidate_class(api)
base = api.base

TEMPLATE = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="-100 -60 400 200"><defs>'
            '<g id="mat"><rect x="-20" y="0" width="60" height="10" fill="#336699"/>'
            '<rect x="0" y="0" width="5" height="10" fill="#99cc00" opacity="0.5"/></g>'
            '{pattern}</defs>{paint}</svg>')
PATTERN = ('<pattern id="lat" patternUnits="userSpaceOnUse" width="20" height="10" '
           'patternTransform="matrix(1 0 -0.25 1 -50 -20)">'
           '<g transform="matrix(1 0 0.25 1 0 0)"><use href="#mat"/></g></pattern>')
PAINT = '<rect x="-60" y="-30" width="150" height="90" fill="url(#lat)"/>'


def convert(pattern=PATTERN, paint=PAINT):
    handle = tempfile.NamedTemporaryFile('w', suffix='.svg', delete=False, encoding='utf-8')
    handle.write(TEMPLATE.format(pattern=pattern, paint=paint))
    handle.close()
    converter = PatternCandidate(handle.name, textures={})
    elements = converter.walk_native(converter.root)
    return converter, elements


def instances_of(converter, symbol_name):
    found = []
    for tree in converter.symbols.values():
        for node in tree.iter():
            if node.tag == api.N + 'DOMSymbolInstance' and node.get('libraryItemName') == symbol_name:
                found.append(node)
    return found


def matrix_of(instance):
    node = instance.find(api.N + 'matrix/' + api.N + 'Matrix')
    return tuple(float(node.get(k, '0' if k in ('b', 'c') else '1')) for k in ('a', 'b', 'c', 'd', 'tx', 'ty'))


class LatticeGeometry(unittest.TestCase):
    def test_tile_cover_negative_origin_and_shear(self):
        pattern = ET.fromstring(PATTERN)
        matrices, info = adapter.lattice_tiles(base, pattern, (-60, -30, 90, 60))
        self.assertEqual(info['columns'], [-1, 7])
        self.assertEqual(info['rows'], [-1, 7])
        self.assertEqual(info['tileInstances'], 81)
        expected = base.mul((1, 0, -0.25, 1, -50, -20), (1, 0, 0, 1, -20, -10))
        self.assertEqual(matrices[0], expected)
        # Lattice basis in user space stays (20, 0) and (-5, 10) between neighbours.
        self.assertEqual(matrices[1][:4], matrices[0][:4])
        self.assertAlmostEqual(matrices[1][4] - matrices[0][4], 20)
        self.assertAlmostEqual(matrices[1][5], matrices[0][5])
        row = matrices[9]
        self.assertAlmostEqual(row[4] - matrices[0][4], -2.5)
        self.assertAlmostEqual(row[5] - matrices[0][5], 10)

    def test_tile_union_covers_paint_bounds(self):
        pattern = ET.fromstring(PATTERN)
        matrices, info = adapter.lattice_tiles(base, pattern, (-60, -30, 90, 60))
        w, h = info['tile']
        for corner in ((-60, -30), (-60, 60), (90, -30), (90, 60)):
            inside = False
            for m in matrices:
                inverse_det = m[0] * m[3] - m[1] * m[2]
                ux, uy = corner[0] - m[4], corner[1] - m[5]
                px = (m[3] * ux - m[2] * uy) / inverse_det
                py = (-m[1] * ux + m[0] * uy) / inverse_det
                if -1e-9 <= px <= w + 1e-9 and -1e-9 <= py <= h + 1e-9:
                    inside = True
            self.assertTrue(inside, 'paint corner not covered by any tile: ' + repr(corner))


class ReferenceAndMaskWiring(unittest.TestCase):
    def test_single_tile_symbol_reused_and_masked(self):
        converter, elements = convert()
        self.assertEqual(len(elements), 1)
        tiles = [name for name in converter.symbols if name.endswith('-vector-pattern-tile-lat')]
        self.assertEqual(len(tiles), 1)
        tile_tree = converter.symbols[tiles[0]]
        scripts = [n.text or '' for n in tile_tree.iter() if n.tag == api.N + 'script']
        self.assertIn('content.setMask(maskShape)', scripts[0])
        names = sorted(n.get('name') for n in tile_tree.iter()
                       if n.tag == api.N + 'DOMSymbolInstance' and n.get('name'))
        self.assertEqual(names, ['content', 'maskShape'])
        placed = instances_of(converter, tiles[0])
        self.assertEqual(len(placed), 81)
        first = matrix_of(placed[0])
        expected = base.mul((1, 0, -0.25, 1, -50, -20), (1, 0, 0, 1, -20, -10))
        for got, want in zip(first, expected):
            self.assertAlmostEqual(got, want)
        reports = [r for r in converter.pattern_reports if r.get('kind') == 'native-vector-lattice']
        self.assertEqual(len(reports), 1)
        self.assertEqual(reports[0]['id'], 'lat')
        self.assertEqual(reports[0]['tileInstances'], 81)

    def test_paint_shape_mask_wraps_lattice(self):
        converter, elements = convert()
        wrapper = [name for name in converter.symbols if name.endswith('-vector-pattern-lat')]
        self.assertEqual(len(wrapper), 1)
        tree = converter.symbols[wrapper[0]]
        scripts = [n.text or '' for n in tree.iter() if n.tag == api.N + 'script']
        self.assertIn('content.setMask(maskShape)', scripts[0])
        shapes = [n for n in tree.iter() if n.tag == api.N + 'DOMShape']
        self.assertEqual(shapes, [], 'paint geometry must live in the mask symbol, not the wrapper')


class RejectionBranches(unittest.TestCase):
    def assert_rejected(self, pattern=PATTERN, paint=PAINT):
        with self.assertRaises(ValueError):
            convert(pattern, paint)

    def test_two_tile_children_rejected(self):
        self.assert_rejected(PATTERN.replace('</g></pattern>', '</g><g/></pattern>'))

    def test_object_bounding_box_rejected(self):
        self.assert_rejected(PATTERN.replace('patternUnits="userSpaceOnUse"', 'patternUnits="objectBoundingBox"'))

    def test_visible_overflow_rejected(self):
        self.assert_rejected(PATTERN.replace('<pattern id="lat"', '<pattern id="lat" overflow="visible"'))

    def test_viewbox_rejected(self):
        self.assert_rejected(PATTERN.replace('width="20" height="10"', 'width="20" height="10" viewBox="0 0 20 10"'))

    def test_non_rect_paint_rejected(self):
        self.assert_rejected(paint='<ellipse cx="0" cy="0" rx="50" ry="30" fill="url(#lat)"/>')

    def test_stroke_with_pattern_rejected(self):
        self.assert_rejected(paint=PAINT.replace('fill="url(#lat)"', 'fill="url(#lat)" stroke="#000000"'))

    def test_transformed_paint_rejected(self):
        self.assert_rejected(paint=PAINT.replace('<rect ', '<rect transform="translate(1 0)" '))

    def test_singular_transform_rejected(self):
        self.assert_rejected(PATTERN.replace('matrix(1 0 -0.25 1 -50 -20)', 'matrix(0 0 0 0 0 0)'))

    def test_unbounded_expansion_rejected(self):
        self.assert_rejected(PATTERN.replace('width="20" height="10"', 'width="1" height="1"'))

    def test_intrinsic_image_pattern_untouched(self):
        tiny_png = ('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
                    'AAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==')
        import base64
        import hashlib
        key = hashlib.sha256(base64.b64decode(tiny_png.split(',', 1)[1])).hexdigest()
        pattern = ('<pattern id="tex" patternUnits="userSpaceOnUse" width="1" height="1">'
                   '<image width="1" height="1" href="' + tiny_png + '"/></pattern>')
        handle = tempfile.NamedTemporaryFile('w', suffix='.svg', delete=False, encoding='utf-8')
        handle.write(TEMPLATE.format(pattern=pattern, paint='<rect x="0" y="0" width="10" height="10" fill="url(#tex)"/>'))
        handle.close()
        converter = PatternCandidate(handle.name, textures={key: {'name': 'one.png', 'pixels': [1, 1]}})
        converter.walk_native(converter.root)
        fills = [n for tree in converter.symbols.values() for n in tree.iter() if n.tag == api.N + 'BitmapFill']
        self.assertEqual(len(fills), 1)
        self.assertEqual([r for r in converter.pattern_reports if r.get('kind') == 'native-vector-lattice'], [])


class FloorUnionRegression(unittest.TestCase):
    def clip(self, path='M0 0L20 0L20 10L0 10Z M19 0L39 0L39 10L19 10Z', rule='nonzero'):
        return ET.fromstring('<clipPath xmlns="http://www.w3.org/2000/svg" id="n2floor_union_1959"><path clip-rule="'+rule+'" d="'+path+'"/></clipPath>')

    def test_overlapping_cells_remain_two_positive_filled_shapes(self):
        clip=self.clip();parts=adapter.split_floor_union(base,clip)
        self.assertEqual(len(parts),2)
        converter,_=convert()
        shapes=[converter.primitive(rect,{'fill':'#FFFFFF'})[0] for rect in parts]
        self.assertTrue(all(len(list(shape.iter(api.N+'Edge')))==1 for shape in shapes))
        # Both native exteriors are negative signed screen area. The old combined
        # evenodd guess wrongly treats the second contour as a hole at (19,0).
        normalized=[base.normalize(base.primitive(rect),True)[0] for rect in parts]
        areas=[]
        for path in normalized:
            pts=base.flattened(path);areas.append(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(pts,pts[1:]+pts[:1])))
        self.assertTrue(all(area<0 for area in areas))
        old=base.normalize(base.primitive(clip[0]),True)
        self.assertTrue(any(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(base.flattened(path),base.flattened(path)[1:]+base.flattened(path)[:1]))>0 for path in old))

    def test_evenodd_holes_are_not_silently_rewritten(self):
        with self.assertRaisesRegex(ValueError,'nonzero'):
            adapter.split_floor_union(base,self.clip(rule='evenodd'))

    def test_mixed_winding_is_not_a_union(self):
        with self.assertRaisesRegex(ValueError,'mixed'):
            adapter.split_floor_union(base,self.clip('M0 0L20 0L20 10L0 10Z M19 0L19 10L39 10L39 0Z'))

    def test_nonrectangular_path_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'four'):
            adapter.split_floor_union(base,self.clip('M0 0L20 0L10 10Z'))

    def test_cut_corner_keeps_exact_four_vertices(self):
        clip=self.clip('M0 0L10 0L12 10L0 10Z')
        cells=adapter.split_floor_union(base,clip)
        self.assertEqual(cells[0].tag,adapter.SVG+'polygon')
        self.assertEqual(cells[0].get('points'),'0,0 10,0 12,10 0,10')

    def test_concave_cell_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'convex'):
            adapter.split_floor_union(base,self.clip('M0 0L20 0L5 5L0 10Z'))

    def test_unrelated_mask_remains_owned_by_general_converter(self):
        clip=self.clip();clip.set('id','other-mask')
        self.assertIsNone(adapter.split_floor_union(base,clip))


if __name__ == '__main__':
    unittest.main()
