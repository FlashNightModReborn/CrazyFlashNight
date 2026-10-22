import copy
import unittest
import xml.etree.ElementTree as ET
from procedural_filter import vent_wear


class Contract(unittest.TestCase):
    def setUp(self):
        self.filter=ET.fromstring('<filter id="wear" color-interpolation-filters="sRGB"><feTurbulence baseFrequency=".8" numOctaves="2" seed="786" result="grain"/><feColorMatrix in="grain" type="matrix" values="0 0 0 0 .2 0 0 0 0 .2 0 0 0 0 .18 .9 0 0 0 -.32"/><feComposite in2="SourceGraphic" operator="in"/></filter>')
    def test_exact_local_scope_and_cleanup(self):
        script,report=vent_wear(self.filter)
        self.assertIn('perlinNoise(1.25,1.25,2,786,false,false,1,true',script)
        self.assertIn('width<=512 && height<=128',script);self.assertIn('this.__cf6NoiseBitmap.dispose()',script)
        self.assertNotIn('_root',script);self.assertEqual(report['nativeColorMatrix'][19],-81.60000000000001)
    def test_unknown_graph_rejected(self):
        self.filter.append(ET.Element('feGaussianBlur'))
        with self.assertRaises(ValueError):vent_wear(self.filter)
    def test_unknown_color_matrix_rejected(self):
        self.filter[1].set('values','1 0 0 0 0')
        with self.assertRaises(ValueError):vent_wear(self.filter)
    def test_wrong_wiring_rejected(self):
        self.filter[2].set('in2','other')
        with self.assertRaises(ValueError):vent_wear(self.filter)


if __name__=='__main__':unittest.main()
