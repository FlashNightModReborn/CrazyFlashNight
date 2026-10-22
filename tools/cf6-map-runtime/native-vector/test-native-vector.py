"""Source contract checks; rendering remains owned by actual CS6/AVM1 validation."""
import importlib.util
import base64
import io
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec=importlib.util.spec_from_file_location('candidate',Path(__file__).with_name('build-a01.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
N=module.N


class Contract(unittest.TestCase):
    def candidate(self,body,**options):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        path=Path(self.temp.name)/'test.svg';path.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'+body+'</svg>')
        return module.Candidate(path,**options)

    def texture(self):
        stream=io.BytesIO();module.Image.new('RGBA',(4,2),(20,40,60,255)).save(stream,format='PNG');raw=stream.getvalue()
        return 'data:image/png;base64,'+base64.b64encode(raw).decode(),{module.digest(raw):{'name':'test.png','pixels':[4,2]}}

    def test_affine_bbox_radial_preserved(self):
        c=self.candidate('<defs><radialGradient id="r"><stop stop-color="#FFFFFF"/><stop offset="1" stop-color="#000000"/></radialGradient></defs><ellipse cx="30" cy="50" rx="20" ry="10" fill="url(#r)"/>')
        rows=c.walk_native(list(c.root)[1]);grad=rows[0].find('.//'+N+'RadialGradient')
        mat=grad.find(N+'matrix/'+N+'Matrix');self.assertAlmostEqual(float(mat.get('a')),20/819.2)
        self.assertAlmostEqual(float(mat.get('d')),10/819.2);self.assertEqual(float(mat.get('tx')),30);self.assertEqual(float(mat.get('ty')),50)

    def test_group_opacity_stays_a_composite(self):
        c=self.candidate('<g opacity="0.5"><rect width="10" height="10"/><rect x="5" width="10" height="10"/></g>')
        rows=c.walk_native(list(c.root)[0]);self.assertEqual(len(rows),1)
        self.assertEqual(rows[0].find(N+'color/'+N+'Color').get('alphaMultiplier'),'0.5')
        tree=c.symbols[rows[0].get('libraryItemName')]
        self.assertIn('blendMode="layer"',tree.find('.//'+N+'script').text)
        self.assertEqual(len(tree.findall('.//'+N+'DOMShape')),2)

    def test_gray_mask_becomes_alpha_and_names_are_movieclips(self):
        c=self.candidate('<defs><linearGradient id="g"><stop stop-color="white"/><stop offset="1" stop-color="black"/></linearGradient><mask id="m"><rect width="10" height="10" fill="url(#g)"/></mask></defs><g mask="url(#m)"><rect width="10" height="10"/></g>')
        c.walk_native(list(c.root)[1]);scripts=[n.text for tree in c.symbols.values() for n in tree.iter() if n.tag==N+'script']
        self.assertTrue(any('content.cacheAsBitmap=true;maskShape.cacheAsBitmap=true;content.setMask(maskShape)' in s for s in scripts))
        names=[n for tree in c.symbols.values() for n in tree.iter() if n.tag==N+'DOMSymbolInstance' and n.get('name')]
        self.assertEqual({n.get('name') for n in names},{'content','maskShape'})
        self.assertTrue(all(n.get('symbolType')=='movie clip' for n in names))
        stops=[n for tree in c.symbols.values() for n in tree.iter() if n.tag==N+'GradientEntry']
        self.assertTrue(any(n.get('color')=='#FFFFFF' and n.get('alpha')=='0' for n in stops))

    def test_unsupported_effect_is_not_dropped(self):
        c=self.candidate('<rect width="10" height="10" filter="url(#blur)"/>')
        with self.assertRaisesRegex(ValueError,'filter'):c.walk_native(list(c.root)[0])

    def test_offcenter_radial_is_not_silently_centered(self):
        c=self.candidate('<defs><radialGradient id="g" fx="20%"><stop stop-color="white"/><stop offset="1" stop-color="black"/></radialGradient></defs><rect width="10" height="10" fill="url(#g)"/>')
        with self.assertRaisesRegex(ValueError,'non-centered'):c.walk_native(list(c.root)[1])

    def test_door_arc_remains_native_curved_edges(self):
        c=self.candidate('<path d="M0 5 A5 5 0 0 1 10 5 L10 10 L0 10 Z" fill="#FFFFFF"/>')
        rows=c.walk_native(list(c.root)[0]);edges=rows[0].findall('.//'+N+'Edge')
        self.assertTrue(edges);self.assertTrue(any('[' in e.get('edges') for e in edges))
        self.assertFalse(any(n.tag==N+'DOMBitmapInstance' for row in rows for n in row.iter()))

    def test_native_pattern_matrix_uses_twips_per_pixel(self):
        href,textures=self.texture()
        c=self.candidate('<defs><pattern id="p" patternUnits="userSpaceOnUse" width="8" height="4"><image width="8" height="4" href="'+href+'"/></pattern></defs><rect width="24" height="12" fill="url(#p)"/>',textures=textures)
        rows=c.walk_native(list(c.root)[1]);paint=rows[0].find('.//'+N+'BitmapFill')
        self.assertEqual(paint.get('bitmapPath'),'test.png');self.assertEqual(paint.get('bitmapIsClipped'),'false')
        self.assertEqual(paint.find(N+'matrix/'+N+'Matrix').get('a'),'40')
        self.assertEqual(len(c.used_textures),1)

    def test_image_default_meet_preserves_letterboxing(self):
        href,textures=self.texture();c=self.candidate('<image width="10" height="10" href="'+href+'"/>',textures=textures)
        rows=c.walk_native(list(c.root)[0]);m=rows[0].find(N+'matrix/'+N+'Matrix')
        self.assertEqual([float(m.get(k)) for k in ('a','d','tx','ty')],[2.5,2.5,0,2.5])

    def test_image_slice_is_native_clipped(self):
        href,textures=self.texture();c=self.candidate('<image width="10" height="10" preserveAspectRatio="xMidYMid slice" href="'+href+'"/>',textures=textures)
        c.walk_native(list(c.root)[0]);scripts=[n.text for tree in c.symbols.values() for n in tree.iter() if n.tag==N+'script']
        self.assertIn('stop();content.setMask(maskShape);',scripts)

    def test_srgb_matrix_and_blur_are_ordered_native_filters(self):
        c=self.candidate('<defs><filter id="f" color-interpolation-filters="sRGB"><feColorMatrix values="1 0 0 0 .1 0 1 0 0 0 0 0 1 0 0 0 0 0 1 0"/><feGaussianBlur stdDeviation=".28"/></filter></defs><rect width="10" height="10" filter="url(#f)"/>',allow_filters=True)
        c.walk_native(list(c.root)[1]);report=c.filter_reports[0]['operations']
        self.assertEqual(report[0]['matrix'][4],25.5);self.assertEqual(report[1]['blur'],[.56,.56]);self.assertEqual(report[1]['quality'],3)

    def test_procedural_filter_is_not_silently_dropped(self):
        c=self.candidate('<defs><filter id="f"><feTurbulence/></filter></defs><rect width="10" height="10" filter="url(#f)"/>',allow_filters=True)
        with self.assertRaisesRegex(ValueError,'feTurbulence'):c.walk_native(list(c.root)[1])

    def test_zero_width_gradient_stroke_has_explicit_compatibility_record(self):
        c=self.candidate('<defs><linearGradient id="g"><stop stop-color="white"/><stop offset="1" stop-color="black"/></linearGradient></defs><path d="M5 0L5 10" fill="none" stroke="url(#g)" stroke-width=".8"/>')
        rows=c.walk_native(list(c.root)[1]);self.assertTrue(rows[0].findall('.//'+N+'SolidStroke'))
        self.assertEqual(c.gradient_fallbacks[0]['strokeWidth'],.8)

    def test_source_multiply_is_a_native_blend_not_normal(self):
        c=self.candidate('<g style="mix-blend-mode:multiply"><rect width="10" height="10" fill="#DDDDDD"/></g>')
        rows=c.walk_native(list(c.root)[0]);symbol=c.symbols[rows[0].get('libraryItemName')]
        self.assertIn('this.blendMode="multiply"',symbol.find('.//'+N+'script').text)
        self.assertEqual(c.blend_reports[0]['nativeMode'],'multiply')

    def test_unknown_blend_mode_is_not_silently_ignored(self):
        c=self.candidate('<rect width="10" height="10" style="mix-blend-mode:soft-light"/>')
        with self.assertRaisesRegex(ValueError,'mix-blend-mode'):c.walk_native(list(c.root)[0])


if __name__=='__main__':unittest.main()
