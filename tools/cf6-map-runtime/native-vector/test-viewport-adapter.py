import unittest
import xml.etree.ElementTree as E
from viewport_adapter import viewport_matrix


class Contract(unittest.TestCase):
    def test_actual_white_flower_viewport(self):
        n=E.fromstring('<svg width="13.9" height="10.8" viewBox="0 0 244 190" preserveAspectRatio="none" overflow="visible"/>')
        a,b,c,d,x,y=viewport_matrix(n)
        self.assertAlmostEqual(244*a,13.9);self.assertAlmostEqual(190*d,10.8)
        self.assertEqual((b,c,x,y),(0,0,0,0))
    def test_viewbox_origin_and_viewport_offset(self):
        n=E.fromstring('<svg x="5" y="7" width="20" height="30" viewBox="-10 -20 100 60" preserveAspectRatio="none" overflow="visible"/>')
        self.assertEqual(viewport_matrix(n),(.2,0,0,.5,7,17))
    def test_unknown_overflow_rejected(self):
        n=E.fromstring('<svg width="20" height="30" viewBox="0 0 100 60" preserveAspectRatio="none"/>')
        with self.assertRaises(ValueError):viewport_matrix(n)
    def test_zero_dimension_rejected(self):
        n=E.fromstring('<svg width="20" height="30" viewBox="0 0 0 60" preserveAspectRatio="none" overflow="visible"/>')
        with self.assertRaises(ValueError):viewport_matrix(n)


if __name__=='__main__':unittest.main()
