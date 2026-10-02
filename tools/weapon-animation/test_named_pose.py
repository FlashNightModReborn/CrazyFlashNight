"""生成入口拒绝不能由 AS2 播放的配置；纯内存，不写现役派生物。"""
import copy
import json
import unittest

import build_named_pose as pose


class NamedPoseGenerationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec, cls.source = pose.read_inputs()

    def test_current_output_is_reproducible(self):
        actual, _ = pose.generate_runtime(self.spec, self.source)
        self.assertEqual(actual, (pose.ROOT / self.spec["runtimeData"]).read_bytes())

    def test_invalid_source_frame_rejected_before_emitting_data(self):
        for value in (8.5, True, -1, 43, None, "8"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                spec = copy.deepcopy(self.spec)
                spec["normalFireEntry0"] = value
                pose.generate_runtime(spec, self.source)

    def test_invalid_duration_or_geometry_rejected(self):
        for key, value in (("prepareTicks", 1), ("transformTicks", 2.5),
                           ("chargeCountMax", 0), ("transformTicks", 65534),
                           ("bladeX", float("nan")), ("bladeRotation", float("inf")),
                           ("bladeFaceHalfHeight", 0)):
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                spec = copy.deepcopy(self.spec)
                spec[key] = value
                pose.generate_runtime(spec, self.source)

    def test_full_stroke_frames_reject_under_extended_or_invalid_samples(self):
        for branch, value in (("N1", 0), ("S1", 0), ("N0", 0), ("N1", 1.5), ("S1", -1), ("N1", 57), ("S1", True)):
            with self.subTest(branch=branch, value=value), self.assertRaises(ValueError):
                spec = copy.deepcopy(self.spec)
                spec["strikeFrames0"][branch] = value
                pose.generate_runtime(spec, self.source)
        spec = copy.deepcopy(self.spec)
        del spec["strikeFrames0"]["S1"]
        with self.assertRaises(ValueError):
            pose.generate_runtime(spec, self.source)

    def test_valid_tuning_preserves_complete_animation_tables(self):
        spec = copy.deepcopy(self.spec)
        spec.update(normalFireEntry0=0, prepareTicks=20, transformTicks=12)
        tuned, _ = pose.generate_runtime(spec, self.source)
        baseline, _ = pose.generate_runtime(self.spec, self.source)
        tuned, baseline = json.loads(tuned), json.loads(baseline)
        for key in ("tables", "counts", "numbers", "clips", "targets"):
            self.assertEqual(tuned[key], baseline[key])


if __name__ == "__main__":
    unittest.main()
