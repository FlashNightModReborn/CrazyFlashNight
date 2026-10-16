"""Geometry tests for Bladebot's blade opening and shared clipped death atlas."""
import math
import unittest
from pathlib import Path
import vector


class VectorTests(unittest.TestCase):
    def test_circle_hole_is_closed_and_round(self):
        original = 'M2051 19.5 A7.5 7.5 0 1 0 2036 19.5 A7.5 7.5 0 1 0 2051 19.5 Z'
        paths = vector.base.parse_path(vector.circular_holes(original))
        self.assertEqual(len(paths), 1)
        self.assertTrue(paths[0][2])
        for x, y in vector.base.flattened(paths[0]):
            self.assertLess(abs(math.hypot(x-2043.5, y-19.5)-7.5), 0.05)
        points = vector.base.flattened(paths[0])
        self.assertAlmostEqual(min(x for x, _ in points), 2036, places=8)
        self.assertAlmostEqual(max(x for x, _ in points), 2051, places=8)
        self.assertAlmostEqual(min(y for _, y in points), 12, places=8)
        self.assertAlmostEqual(max(y for _, y in points), 27, places=8)

    def test_unsupported_arcs_rejected(self):
        with self.assertRaises(ValueError):
            vector.circular_holes('M0 0 A10 5 0 0 0 20 0')

    def test_every_frozen_part_and_one_shared_atlas(self):
        archive = vector.ROOT/'flashswf/arts/new/Codex素材源稿/CF6大刀机器人-R2'
        paths = sorted(archive.glob('parts/*.svg')) + sorted(archive.glob('death-parts/*.svg'))
        self.assertEqual(len(paths), 19)
        vector.NativePart.shared_references.clear()
        symbols = {}
        for path in paths:
            converted, report = vector.NativePart(path, 'test/'+path.stem, (0, 0)).build()
            self.assertGreater(report['masks'], 0)
            for name, node in converted.items():
                encoded = vector.gamma.xml_bytes(node)
                if name in symbols:
                    self.assertEqual(symbols[name], encoded)
                symbols[name] = encoded
                self.assertNotIn(b'DOMBitmapInstance', encoded)
                self.assertNotIn(b'BitmapFill', encoded)
        self.assertEqual(len(vector.NativePart.shared_references), 1)


if __name__ == '__main__':
    unittest.main()
