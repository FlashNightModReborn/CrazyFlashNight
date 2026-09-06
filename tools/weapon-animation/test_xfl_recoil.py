"""用独立小型 XFL fixture 验证轨迹、注册点及拒绝不支持的输入。"""
from copy import deepcopy
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

import xfl_recoil as recoil


class RecoilTests(unittest.TestCase):
    def setUp(self):
        parent = recoil.ROOT / 'tmp/weapon-animation/tests'
        parent.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=parent)
        self.root = Path(self.tmp.name).resolve()
        assert self.root.is_relative_to(parent.resolve())
        self.lib = self.root / 'LIBRARY'
        self.lib.mkdir()
        self.ns = ' xmlns="http://ns.adobe.com/xfl/2008/"'
        (self.root / 'DOMDocument.xml').write_text('<DOMDocument' + self.ns + ' frameRate="30"><symbols>' + ''.join('<Include href="' + name + '.xml"/>' for name in ('rest', 'animation', 'barrel', 'stock')) + '</symbols></DOMDocument>', encoding='utf-8')
        for name in ('barrel', 'stock'):
            (self.lib / (name + '.xml')).write_text('<DOMSymbolItem' + self.ns + ' name="' + name + '" symbolType="graphic"/>', encoding='utf-8')
        (self.lib / 'rest.xml').write_text('<DOMSymbolItem' + self.ns + ' name="rest" symbolType="graphic"><timeline><DOMTimeline name="总装"><layers>' + ''.join('<DOMLayer name="' + name + '"><frames><DOMFrame index="0" keyMode="9728"><elements><DOMSymbolInstance libraryItemName="' + name + '" symbolType="graphic"><matrix><Matrix a="0" b="1" c="-1" d="0" tx="10.25" ty="-3.5"/></matrix><transformationPoint><Point x="2" y="3"/></transformationPoint></DOMSymbolInstance></elements></DOMFrame></frames></DOMLayer>' for name in ('barrel', 'stock')) + '</layers></DOMTimeline></timeline></DOMSymbolItem>', encoding='utf-8')
        (self.lib / 'animation.xml').write_text('<DOMSymbolItem' + self.ns + ' name="animation" itemID="12345678-12345678"><timeline/></DOMSymbolItem>', encoding='utf-8')
        self.profile = {'schema': 1, 'xfl': self.root.relative_to(recoil.ROOT).as_posix(), 'sourceSymbol': 'rest',
                        'animationSymbol': 'animation', 'fps': 30, 'frameCount': 5, 'fireStartFrame': 2,
                        'tracks': [{'symbols': ['barrel'], 'offsets': [[0, 0], [0, 0], [1.5, -0.25], [0.5, 0], [0, 0]]}]}

    def tearDown(self):
        assert self.root.is_relative_to((recoil.ROOT / 'tmp/weapon-animation/tests').resolve())
        self.tmp.cleanup()

    def test_absolute_offsets_and_registration(self):
        _, root, report = recoil.build(self.profile)
        frames = root.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', recoil.NS)[1].findall('./x:frames/x:DOMFrame', recoil.NS)
        positions = [f.find('.//x:Matrix', recoil.NS).attrib for f in frames]
        self.assertEqual([float(p['tx']) for p in positions], [10.25, 10.25, 11.75, 10.75, 10.25])
        self.assertEqual([float(p['ty']) for p in positions], [-3.5, -3.5, -3.75, -3.5, -3.5])
        self.assertTrue(all(tuple(float(p[k]) for k in ('a', 'b', 'c', 'd')) == (0, 1, -1, 0) for p in positions))
        self.assertTrue(all(f.find('.//x:Point', recoil.NS).attrib == {'x': '2', 'y': '3'} for f in frames))
        self.assertEqual(report['staticPartCount'], 1)

    def test_static_layer_and_control_stops(self):
        _, root, _ = recoil.build(self.profile)
        layers = root.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', recoil.NS)
        frames = layers[2].findall('./x:frames/x:DOMFrame', recoil.NS)
        self.assertEqual(len(frames), 1)
        self.assertEqual(frames[0].get('duration'), '5')
        self.assertEqual([f.get('index') for f in layers[0].findall('./x:frames/x:DOMFrame', recoil.NS)], ['0', '4'])
        self.assertEqual([s.text for s in root.findall('.//x:script', recoil.NS)], ['stop();', 'stop();'])

    def test_idempotent_and_source_preserved(self):
        original = (self.lib / 'rest.xml').read_bytes()
        target, first, _ = recoil.build(self.profile)
        target.write_bytes(recoil.serialize(first))
        _, second, _ = recoil.build(self.profile)
        self.assertEqual(recoil.canonical(first), recoil.canonical(second))
        self.assertEqual((self.lib / 'rest.xml').read_bytes(), original)

    def test_unknown_and_duplicate_part_rejected(self):
        for symbols in (['absent'], ['barrel', 'barrel']):
            profile = deepcopy(self.profile)
            profile['tracks'][0]['symbols'] = symbols
            with self.assertRaises(ValueError): recoil.build(profile)

    def test_bad_trajectory_rejected(self):
        for offsets in ([[0, 0]], [[0, 0], [1, 0], [1.5, 0], [0, 0], [0, 0]],
                        [[0, 0], [0, 0], [float('nan'), 0], [0, 0], [0, 0]],
                        [[0, 0], [0, 0], [0.013, 0], [0, 0], [0, 0]],
                        [[0, 0], [0, 0], [1.5, 0], [0, 0], [1, 0]]):
            profile = deepcopy(self.profile)
            profile['tracks'][0]['offsets'] = offsets
            with self.assertRaises(ValueError): recoil.build(profile)

    def test_wrong_clock_and_graphic_target_rejected(self):
        profile = deepcopy(self.profile)
        profile['fps'] = 24
        with self.assertRaises(ValueError): recoil.build(profile)
        path = self.lib / 'animation.xml'
        root = ET.parse(path).getroot()
        root.set('symbolType', 'graphic')
        path.write_bytes(recoil.serialize(root))
        with self.assertRaises(ValueError): recoil.build(self.profile)

    def test_missing_include_rejected(self):
        path = self.root / 'DOMDocument.xml'
        path.write_text(path.read_text('utf-8').replace('<Include href="barrel.xml"/>', ''), encoding='utf-8')
        with self.assertRaises(ValueError): recoil.build(self.profile)

    def test_animated_masked_or_scripted_source_rejected(self):
        path = self.lib / 'rest.xml'
        original = path.read_bytes()
        for change in ('mask', 'tween', 'script'):
            root = ET.fromstring(original)
            layer = root.find('.//x:DOMLayer', recoil.NS)
            frame = layer.find('./x:frames/x:DOMFrame', recoil.NS)
            if change == 'mask': layer.set('layerType', 'mask')
            elif change == 'tween': frame.set('tweenType', 'motion')
            else: ET.SubElement(frame, recoil.N + 'Actionscript')
            path.write_bytes(recoil.serialize(root))
            with self.assertRaises(ValueError): recoil.build(self.profile)

    def test_runtime_frame_binding_cannot_drift(self):
        item_file = self.root / 'items.xml'
        item_file.write_text('<items><item><name>样例</name><use>长枪</use><data><dressup>枪-样例</dressup></data><lifecycle><attr_0><init><initRoutines>初始化</initRoutines><initParam><fireStart>2</fireStart><fireEnd>5</fireEnd></initParam></init><cycle><cycleRoutines>周期</cycleRoutines></cycle></attr_0></lifecycle></item></items>', encoding='utf-8')
        self.profile['runtime'] = {'item': '样例', 'itemSource': item_file.relative_to(recoil.ROOT).as_posix(), 'linkage': '枪-样例',
                                   'weaponType': '长枪', 'initRoutine': '初始化', 'cycleRoutine': '周期',
                                   'instanceContainer': '长枪_引用', 'animationTarget': '动画'}
        recoil.build(self.profile)
        item_file.write_text(item_file.read_text('utf-8').replace('<fireEnd>5</fireEnd>', '<fireEnd>4</fireEnd>'), encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'fireStart/fireEnd'): recoil.build(self.profile)


if __name__ == '__main__':
    unittest.main()
