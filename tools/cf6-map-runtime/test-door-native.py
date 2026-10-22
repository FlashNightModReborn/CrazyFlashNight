"""Offline isolated timeline assembly contract, not CS6/AVM1 evidence."""
import importlib.util
from pathlib import Path
import unittest
from lxml import etree as E
from native_xfl import NS

spec=importlib.util.spec_from_file_location('cf6_door_finalize',Path(__file__).with_name('finalize-door-native.py'))
door=importlib.util.module_from_spec(spec);spec.loader.exec_module(door)


class DoorTests(unittest.TestCase):
    def setUp(self):
        self.doc=E.ElementTree(E.fromstring('''<DOMDocument xmlns="http://ns.adobe.com/xfl/2008/"><media><DOMBitmapItem name="f1.png" href="f1.png"/><DOMBitmapItem name="f2.png" href="f2.png"/></media><timelines><DOMTimeline><DOMBitmapInstance libraryItemName="f2.png"><matrix><Matrix a="0.5" d="0.5"/></matrix></DOMBitmapInstance><DOMBitmapInstance libraryItemName="f1.png"/><Actionscript><script>unwanted();</script></Actionscript></DOMTimeline></timelines></DOMDocument>'''))
        self.row={'name':'fixture','inputs':[{'path':'src/f1.png'},{'path':'src/f2.png'}]}
    def test_frame_order_and_only_stop_action(self):
        tree=door.timeline(self.doc,self.row)
        self.assertEqual([node.get('libraryItemName') for node in tree.findall('.//x:DOMBitmapInstance',NS)],['f1.png','f2.png'])
        self.assertEqual([node.text for node in tree.findall('.//x:script',NS)],['stop();'])
        self.assertEqual([node.get('index') for node in tree.findall('.//x:DOMFrame',NS)],['0','1'])
        self.assertEqual(tree.find('.//x:Matrix',NS).get('a'),'0.5')
    def test_idempotent_after_native_namespace_serialization(self):
        tree=door.timeline(self.doc,self.row);self.doc.getroot().replace(self.doc.find('./x:timelines',NS),tree)
        roundtrip=E.ElementTree(E.fromstring(E.tostring(self.doc)))
        self.assertEqual(door.signature(roundtrip.find('./x:timelines',NS)),door.signature(door.timeline(roundtrip,self.row)))
    def test_missing_frame_rejected(self):
        self.row['inputs'].append({'path':'src/missing.png'})
        with self.assertRaises(KeyError):door.timeline(self.doc,self.row)


if __name__=='__main__':unittest.main()
