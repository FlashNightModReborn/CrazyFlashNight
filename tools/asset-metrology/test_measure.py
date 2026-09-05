"""独立几何样本、输出边界及现有 XFL 标定的定向回归。"""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import measure
from xfl_geometry import Geometry, bounds, matrix, point, segments

SHAPE = '<DOMShape><edges><Edge fillStyle1="1" edges="!0 0|20 20"/></edges></DOMShape>'


class MetrologyTests(unittest.TestCase):
    def setUp(self):
        measure.OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='test-', dir=measure.OUTPUT_ROOT)
        self.base = Path(self.temp.name).resolve()
        self.assertTrue(self.base.is_relative_to(measure.OUTPUT_ROOT.resolve()))
        self.addCleanup(self.temp.cleanup)
        self.library = self.base / 'LIBRARY'
        self.library.mkdir()

    def symbol(self, name, content, layer='', frame=''):
        text = (f'<DOMSymbolItem xmlns="http://ns.adobe.com/xfl/2008/" name="{name}">'
                f'<timeline><DOMTimeline><layers><DOMLayer {layer}><frames><DOMFrame index="0" {frame}>'
                f'<elements>{content}</elements></DOMFrame></frames></DOMLayer></layers>'
                '</DOMTimeline></timeline></DOMSymbolItem>')
        (self.library/(name+'.xml')).write_text(text, encoding='utf-8')

    def test_physical_length_and_nested_coordinates(self):
        profile = measure.load_profiles()['profiles']['weapon']
        result = measure.convert_length(profile, 88, 1200)
        self.assertAlmostEqual(result['editingLayerTargetPx'], 264)
        self.assertAlmostEqual(result['resizePercent'], 22)
        nested = measure.convert_length(profile, 88, 1200, 3.19305419921875)
        self.assertAlmostEqual(nested['editingLayerTargetPx'], 82.679461, places=5)
        self.assertAlmostEqual(nested['resizePercent'], 6.889955, places=5)
        styled = measure.convert_length(profile, 100, style_factor=1.5)
        self.assertEqual(styled['outerTargetPx'], 450)

    def test_curve_extrema_after_rotation(self):
        # 控制点 y=20，而二次曲线最高只有 y=10；旋转后边界必须重新求极值。
        curve = [((0, 0), (10, 20), (20, 0))]
        self.assertEqual(bounds(curve), [0, 0, 20, 10])
        rotated = [tuple(point((0, 1, -1, 0, 0, 0), p) for p in curve[0])]
        self.assertEqual(bounds(rotated), [-10, 0, 0, 20])

    def test_signed_hex_twips_and_selection_bits(self):
        result = list(segments('!#FFFFFF.80 0S1|20 20'))
        self.assertEqual(result, [((-0.025, 0), (1, 1))])
        with self.assertRaises(ValueError):
            list(segments('!0 0|20'))

    def test_nested_scale_mirror_and_marker_exclusion(self):
        self.symbol('leaf', SHAPE)
        child = '<DOMSymbolInstance libraryItemName="leaf"><matrix><Matrix a="3" d="3"/></matrix></DOMSymbolInstance>'
        marker = '<DOMSymbolInstance libraryItemName="leaf" name="枪口位置2"><matrix><Matrix tx="1000"/></matrix></DOMSymbolInstance>'
        self.symbol('root', '<DOMGroup><matrix><Matrix a="-2" d="3" tx="10" ty="5"/></matrix><members>'+child+'</members></DOMGroup>'+marker)
        geo = Geometry(self.library)
        self.assertEqual(bounds(list(geo.symbol('root'))), [4, 5, 10, 14])
        self.assertEqual(geo.skipped, {'枪口位置2'})
        self.assertEqual(bounds(list(Geometry(self.library, True).symbol('root'))), [4, 0, 1001, 14])

    def test_unknown_geometry_masks_and_inbetween_tweens_fail(self):
        self.symbol('bitmap', '<DOMBitmapInstance libraryItemName="photo"/>')
        self.symbol('mask', SHAPE, layer='layerType="mask"')
        self.symbol('tween', SHAPE, frame='duration="5" tweenType="motion"')
        for name, frame in (('bitmap', 0), ('mask', 0), ('tween', 2)):
            with self.subTest(name=name), self.assertRaises(ValueError):
                list(Geometry(self.library).symbol(name, frame))

    def test_cycles_and_frame_range_fail(self):
        self.symbol('cycle', '<DOMSymbolInstance libraryItemName="cycle"/>')
        self.symbol('leaf', SHAPE)
        for name, frame in (('cycle', 0), ('leaf', -1), ('leaf', 2)):
            with self.subTest(name=name, frame=frame), self.assertRaises(ValueError):
                list(Geometry(self.library).symbol(name, frame))

    def test_non_finite_or_non_positive_parameters_fail(self):
        for value in (0, -1, float('nan'), float('inf')):
            with self.subTest(value=value), self.assertRaises(ValueError):
                measure.convert_length({'pixelsPerMeter': 300}, value)
        with self.assertRaises(ValueError):
            matrix({'a': 'nan'})

    def test_dry_run_and_managed_output(self):
        target = self.base/'output'
        args = ['convert', '--profile', 'weapon', '--length-cm', '88', '--output-dir', str(target)]
        with contextlib.redirect_stdout(io.StringIO()) as stdout:
            measure.main(args+['--dry-run'])
        self.assertEqual(json.loads(stdout.getvalue())['outerTargetPx'], 264)
        self.assertFalse(target.exists())
        with contextlib.redirect_stdout(io.StringIO()):
            measure.main(args)
        self.assertEqual(json.loads((target/'result.json').read_text(encoding='utf-8'))['outerTargetPx'], 264)
        with self.assertRaises(ValueError):
            measure.output_path(str(measure.ROOT/'flashswf'/'arts'))

    def test_current_human_and_weapon_samples(self):
        # 数值取自独立的 2026-09-05 调查记录；改骨架时需重新审视标尺。
        result, extra = measure.calibrate(measure.load_profiles())
        self.assertAlmostEqual(result['states']['空手站立']['heightPx'], 145.192765, places=4)
        self.assertEqual(len(result['states']), 7)
        self.assertIn('reference-contours.svg', extra)
        geo = Geometry(measure.ROOT/'flashswf/arts/things/LIBRARY')
        bb = bounds(list(geo.symbol('1.枪械相关/长枪/枪-长枪-AK47')))
        self.assertAlmostEqual(bb[2]-bb[0], 353.725, places=3)
        self.assertIn('枪口位置', geo.skipped)


if __name__ == '__main__':
    unittest.main(verbosity=2)
