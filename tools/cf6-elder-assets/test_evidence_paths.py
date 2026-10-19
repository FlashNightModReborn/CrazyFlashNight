import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('evidence_paths', HERE / 'evidence_paths.py')
p = importlib.util.module_from_spec(spec); spec.loader.exec_module(p)


class EvidencePathsTests(unittest.TestCase):
    def test_utf16(self):
        self.assertEqual(p.utf16('中😀'), 3)

    def test_relative_boundary(self):
        root = Path('/r').resolve(); prefix = 'tools/cf6-elder-assets/e/x/'
        accepted = p.new_path('x', 'a' * (179 - len(prefix)), root)
        self.assertEqual(p.utf16(accepted.relative_to(root)), 179)
        with self.assertRaises(ValueError): p.new_path('x', 'a' * (180 - len(prefix)), root)

    def test_actual_full_root_boundary(self):
        anchor = Path.cwd().anchor
        root = Path(anchor + 'r' * (60 - p.utf16(anchor))).resolve()
        prefix = 'tools/cf6-elder-assets/e/x/'
        good = p.new_path('x', 'a' * (179 - len(prefix)), root)
        self.assertEqual(p.utf16(good), 240)
        with self.assertRaises(ValueError): p.new_path('x', 'a' * (179 - len(prefix)), Path(str(root) + 'r'))

    def test_nonbmp_boundary(self):
        root = Path('/r').resolve(); prefix = 'tools/cf6-elder-assets/e/x/'
        length = 179 - len(prefix)
        p.new_path('x', 'a' * (length - 2) + '😀', root)
        with self.assertRaises(ValueError): p.new_path('x', 'a' * (length - 1) + '😀', root)

    def test_retired_roots_never_created(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for prefix in p.OLD_PREFIXES:
                with self.assertRaises(ValueError): p.validate_output(root / prefix / 'new.json', root)
                self.assertFalse((root / prefix).exists())
                with self.assertRaises(ValueError): p.validate_output(root / prefix.upper() / 'new.json', root)

    def test_safe_member_and_campaign(self):
        for member in ('../x', '/x', 'a/../x', 'a//x', 'a\\x', '.', '', 'C:/x', 'a/b:ads', 'CON.txt', 'a/NUL', 'x.', 'x '):
            with self.assertRaises(ValueError): p.new_path('x', member, '/r')
        for campaign in ('UPPER', '../a', 'a' * 13, ''):
            with self.assertRaises(ValueError): p.new_path(campaign, 'x', '/r')

    def test_symlink_escape(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'r'; root.mkdir()
            outside = Path(folder) / 'outside'; outside.mkdir()
            base = root / 'tools/cf6-elder-assets/e/x'; base.mkdir(parents=True)
            try:
                (base / 'link').symlink_to(outside, target_is_directory=True)
            except OSError as error:
                self.skipTest('Symbolic links unavailable: ' + str(error))
            with self.assertRaises(ValueError): p.new_path('x', 'link/new.json', root)
            self.assertFalse((outside / 'new.json').exists())

    def test_map_every_old_and_new_path_without_receipt_rewrite(self):
        mapping = json.loads((HERE / 'evidence-path-map.json').read_text())
        for row in mapping['files']:
            self.assertEqual(p.resolve_archived(row['old'], '/r'), Path('/r') / row['new'])
            self.assertEqual(p.resolve_archived(row['new'], '/r'), Path('/r') / row['new'])
        self.assertEqual(len(mapping['files']), 5083)
        with self.assertRaises(ValueError): p.resolve_archived('unmapped', '/r')

    def test_analyzer_validates_before_write(self):
        text = (HERE / 'analyze-arena.py').read_text()
        self.assertLess(text.index('validate_output(args.output)'), text.index('args.output.parent.mkdir'))
        self.assertLess(text.index('validate_output(args.output)'), text.index("args.output.open('x'"))


if __name__ == '__main__': unittest.main()
