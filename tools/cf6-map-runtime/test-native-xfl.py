"""Reject incomplete/tampered native bitmap closures; no Flash process control."""
from pathlib import Path
import tempfile
import unittest
from PIL import Image
from native_xfl import audit,finalize,parse,fingerprint


class NativeClosureTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        (self.root/'LIBRARY').mkdir();(self.root/'bin').mkdir()
        self.source=self.root/'fixture.xfl';self.source.write_bytes(b'PROXY-CS5')
        self.png=self.root/'LIBRARY/floor.png';Image.new('RGBA',(4,3),(10,20,30,255)).save(self.png)
        (self.root/'bin/native.dat').write_bytes(b'opaque-native-cache-fixture')
        (self.root/'DOMDocument.xml').write_text('''<DOMDocument xmlns="http://ns.adobe.com/xfl/2008/"><media><DOMBitmapItem name="floor.png" href="floor.png" bitmapDataHRef="native.dat" frameRight="80" frameBottom="60"/></media><timelines><DOMTimeline><DOMBitmapInstance libraryItemName="floor.png"/><Actionscript><script><![CDATA[stop();_root.贴背景图();]]></script></Actionscript></DOMTimeline></timelines></DOMDocument>''',encoding='utf-8')
        keys=['flashFileName','defaultNames','flashDefaultName','flash','html','projectorWin','projectorMac','gif','jpeg','png','swc']
        (self.root/'PublishSettings.xml').write_text('<flash_profiles><PublishFormatProperties>'+''.join('<'+k+'>old</'+k+'>' for k in keys)+'</PublishFormatProperties></flash_profiles>',encoding='utf-8')
        self.inputs=[{'path':'source/floor.png',**fingerprint(self.png)}]
    def tearDown(self):self.tmp.cleanup()
    def rewrite(self,old,new):
        p=self.root/'DOMDocument.xml';p.write_text(p.read_text(encoding='utf-8').replace(old,new),encoding='utf-8')
    def test_finalize_preserves_png_and_cdata_and_exact_publish(self):
        report=finalize(self.source,'fixture.swf',self.inputs)
        self.assertEqual(report['bitmapItems'],1);self.assertEqual(report['libraryReferences'],1)
        self.assertEqual(parse(self.root/'PublishSettings.xml').find('.//flashFileName').text,'fixture.swf')
        self.assertIn('<![CDATA[stop();_root.贴背景图();]]>',(self.root/'DOMDocument.xml').read_text(encoding='utf-8'))
        finalize(self.source,'fixture.swf',self.inputs,check=True)
    def test_missing_native_cache_rejected_before_mutation(self):
        original=(self.root/'DOMDocument.xml').read_bytes();(self.root/'bin/native.dat').unlink()
        with self.assertRaisesRegex(ValueError,'closure file'):finalize(self.source,'fixture.swf',self.inputs)
        self.assertEqual((self.root/'DOMDocument.xml').read_bytes(),original)
    def test_changed_source_png_rejected(self):
        Image.new('RGBA',(4,3),(90,20,30,255)).save(self.png)
        with self.assertRaisesRegex(ValueError,'pinned runtime input'):audit(self.source,self.inputs,False)
    def test_bitmap_reference_must_resolve_to_media(self):
        self.rewrite('libraryItemName="floor.png"','libraryItemName="missing.png"')
        with self.assertRaisesRegex(ValueError,'Unresolved'):audit(self.source,self.inputs,False)
    def test_implicit_compression_is_not_pass(self):
        with self.assertRaisesRegex(ValueError,'compressionType'):audit(self.source,self.inputs)
    def test_wrong_dimensions_rejected(self):
        self.rewrite('frameRight="80"','frameRight="100"')
        with self.assertRaisesRegex(ValueError,'dimensions'):audit(self.source,self.inputs,False)
    def test_cache_escape_rejected(self):
        self.rewrite('bitmapDataHRef="native.dat"','bitmapDataHRef="../fixture.xfl"')
        with self.assertRaisesRegex(ValueError,'closure file'):audit(self.source,self.inputs,False)


if __name__=='__main__':unittest.main()
