"""Negative safety cases for shortened generated clip identities and exact retirement."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('traversal_art', Path(__file__).with_name('build_traversal_art.py'))
producer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(producer)


class TraversalPathSafetyTest(unittest.TestCase):
    def test_prefix_collision_is_rejected(self):
        identities = {}
        first = 'a' * 24 + '1' * 40
        second = 'a' * 24 + '2' * 40
        name = producer.clip_name(first, identities)
        self.assertEqual(producer.clip_name(first, identities), name)
        with self.assertRaisesRegex(ValueError, 'collision'):
            producer.clip_name(second, identities)
        self.assertEqual(identities[name], first)

    def test_legacy_residual_rejected_by_check(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            old = self.legacy(root)
            with self.assertRaisesRegex(ValueError, 'residual'):
                producer.require_legacy_inventory(root, set())
            self.assertEqual(old.read_bytes(), b'owned')

    def test_unregistered_legacy_file_blocks_all_retirement(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            old = self.legacy(root)
            extra = old.parent/'unregistered.xml'
            extra.write_bytes(b'preserve')
            previous = {old.relative_to(root).as_posix(): {'sha256': producer.digest(b'owned')}}
            with self.assertRaisesRegex(ValueError, 'unregistered'):
                producer.preflight_retirement(root, previous, {})
            self.assertEqual(old.read_bytes(), b'owned')
            self.assertEqual(extra.read_bytes(), b'preserve')

    def test_edited_owned_file_blocks_retirement(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            old = self.legacy(root)
            previous = {old.relative_to(root).as_posix(): {'sha256': producer.digest(b'before-edit')}}
            with self.assertRaisesRegex(ValueError, 'edited'):
                producer.preflight_retirement(root, previous, {})
            self.assertEqual(old.read_bytes(), b'owned')

    def test_exact_verified_retirement_is_read_only_preflight(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            old = self.legacy(root)
            relative = old.relative_to(root).as_posix()
            previous = {relative: {'sha256': producer.digest(b'owned')}}
            self.assertEqual(producer.preflight_retirement(root, previous, {}), [relative])
            self.assertTrue(old.is_file())

    @staticmethod
    def legacy(root):
        path = root/'flashswf/backgrounds/cf6/preparation/CF6_Traversal1720_Back/LIBRARY/CF6SourceClip'/('a'*64+'.xml')
        path.parent.mkdir(parents=True)
        path.write_bytes(b'owned')
        return path


if __name__ == '__main__':
    unittest.main()
