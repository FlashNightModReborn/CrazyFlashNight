"""表示政策的结构检测及原画字节保持回归。"""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("team", Path(__file__).with_name("promote-team-portraits-v1.py"))
T = importlib.util.module_from_spec(spec)
spec.loader.exec_module(T)


class RuntimeSafetyTests(unittest.TestCase):
    def test_convolution_policy_is_structural_not_a_claimed_crash_threshold(self):
        for order in ("3", "20 20", "100 100"):
            for prefix in ("", "s:"):
                source = (f'<svg xmlns:s="http://www.w3.org/2000/svg"><filter>'
                          f'<{prefix}feConvolveMatrix order="{order}"/></filter></svg>').encode()
                evidence = T.svg_representation_evidence(source, b"png")
                self.assertFalse(evidence["svgRuntimeAllowed"])
                self.assertEqual(1, evidence["convolutionFilterCount"])
                self.assertEqual("png", evidence["preferredFormat"])

    def test_normal_vectors_stay_svg_and_comments_are_not_filters(self):
        result = T.svg_representation_evidence(b'<svg><!-- <feConvolveMatrix/> --><path d="M0 0"/></svg>', b'png')
        self.assertTrue(result["svgRuntimeAllowed"])
        self.assertEqual("svg", result["preferredFormat"])

    def test_invalid_xml_is_rejected(self):
        with self.assertRaises(T.PromotionError):
            T.svg_representation_evidence(b'<svg><filter>', b'png')


if __name__ == "__main__":
    unittest.main()
