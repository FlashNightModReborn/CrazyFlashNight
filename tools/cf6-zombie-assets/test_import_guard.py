"""Regression tests for lossless refusal of CF6 native-workspace reimports."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location('cf6_asset_build', Path(__file__).with_name('build.py'))
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)


class ImportGuardTests(unittest.TestCase):
    def setUp(self):
        scratch = BUILD.ROOT / 'tmp/cf6-zombie-assets-tests'
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='guard-', dir=scratch)
        self.root = Path(self.temp.name).resolve()
        assert self.root.parent == scratch.resolve()
        self.addCleanup(self.temp.cleanup)
        self.owner = self.root / 'native'
        self.here = self.root / 'tool'
        self.here.mkdir()
        self.symbol = 'LIBRARY/Antigravity/test.xml'
        for rel in (*BUILD.PROJECT_FILES, self.symbol):
            path = self.owner / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('baseline: ' + rel, encoding='utf-8')
        identity = lambda rel: {
            'path': rel,
            'sha256': hashlib.sha256((self.owner / rel).read_bytes()).hexdigest(),
            'bytes': (self.owner / rel).stat().st_size,
        }
        self.manifest = {
            'schema': BUILD.MANIFEST_SCHEMA,
            'nativeSymbolCount': 1,
            'outputs': [identity(self.symbol)],
            'projectFiles': [identity(rel) for rel in BUILD.PROJECT_FILES],
        }
        self.save_manifest()
        for name, value in [('OWNER', self.owner), ('HERE', self.here)]:
            self.enterContext(patch.object(BUILD, name, value))

    def save_manifest(self):
        (self.here / 'native-manifest.json').write_text(json.dumps(self.manifest), encoding='utf-8')

    def snapshot(self):
        return {p.relative_to(self.root).as_posix(): p.read_bytes()
                for p in self.root.rglob('*') if p.is_file()}

    def assert_refused_without_writes(self, message):
        before = self.snapshot()
        with patch.object(BUILD, 'write_workspace', side_effect=AssertionError('unexpected write')):
            with self.assertRaisesRegex(RuntimeError, message):
                BUILD.import_assets()
        self.assertEqual(before, self.snapshot())

    def test_unchanged_workspace_can_be_reimported(self):
        BUILD.guard_overwrite_allowed()

    def test_document_timeline_or_include_edit_is_protected(self):
        (self.owner / 'DOMDocument.xml').write_text('manual timeline and Include', encoding='utf-8')
        self.assert_refused_without_writes('DOMDocument.xml')

    def test_publish_settings_edit_is_protected(self):
        (self.owner / 'PublishSettings.xml').write_text('manual output path', encoding='utf-8')
        self.assert_refused_without_writes('PublishSettings.xml')

    def test_xfl_entry_edit_is_protected(self):
        (self.owner / 'Antigravity专用素材.xfl').write_text('manual entry', encoding='utf-8')
        self.assert_refused_without_writes('Antigravity专用素材.xfl')

    def test_mobile_settings_edit_is_protected(self):
        (self.owner / 'MobileSettings.xml').write_text('manual settings', encoding='utf-8')
        self.assert_refused_without_writes('MobileSettings.xml')

    def test_existing_symbol_edit_is_protected(self):
        (self.owner / self.symbol).write_text('manual art', encoding='utf-8')
        self.assert_refused_without_writes('test.xml')

    def test_added_symbol_is_protected_even_before_include_update(self):
        (self.owner / 'LIBRARY/manual.xml').write_text('new artwork', encoding='utf-8')
        self.assert_refused_without_writes('added library file')

    def test_added_binary_art_is_protected(self):
        (self.owner / 'LIBRARY/manual.dat').write_bytes(b'new art')
        self.assert_refused_without_writes('added library file')

    def test_removed_symbol_is_not_silently_recreated(self):
        (self.owner / self.symbol).unlink()
        self.assert_refused_without_writes('missing file')

    def test_removed_project_file_is_not_silently_recreated(self):
        (self.owner / 'PublishSettings.xml').unlink()
        self.assert_refused_without_writes('missing file')

    def test_missing_manifest_does_not_authorize_overwrite(self):
        (self.here / 'native-manifest.json').unlink()
        self.assert_refused_without_writes('no baseline')

    def test_old_manifest_does_not_authorize_overwrite(self):
        self.manifest['schema'] = 'cf6-zombie-redraw.native-import.v1'
        self.manifest.pop('projectFiles')
        self.save_manifest()
        self.assert_refused_without_writes('missing v2')

    def test_incomplete_project_baseline_is_rejected(self):
        self.manifest['projectFiles'].pop()
        self.save_manifest()
        self.assert_refused_without_writes('incomplete project')

    def test_empty_new_workspace_needs_no_manifest(self):
        with patch.object(BUILD, 'OWNER', self.root / 'new-native'), \
                patch.object(BUILD, 'HERE', self.root / 'new-tool'):
            BUILD.guard_overwrite_allowed()

    def test_force_is_an_explicit_override(self):
        (self.owner / 'DOMDocument.xml').write_text('manual edit', encoding='utf-8')
        BUILD.guard_overwrite_allowed(force=True)

    def test_edit_during_generation_is_rechecked_before_write(self):
        def changed_while_generating():
            (self.owner / 'DOMDocument.xml').write_text('late manual edit', encoding='utf-8')
            return {}, {}
        with patch.object(BUILD, 'clone_shared_helpers', return_value={}), \
                patch.object(BUILD, 'generate_male_zombie', return_value=({}, {})), \
                patch.object(BUILD, 'generate_female_zombie', side_effect=changed_while_generating), \
                patch.object(BUILD, 'write_workspace', side_effect=AssertionError('unexpected write')):
            with self.assertRaisesRegex(RuntimeError, 'DOMDocument.xml'):
                BUILD.import_assets()
        self.assertEqual((self.owner / 'DOMDocument.xml').read_text(encoding='utf-8'), 'late manual edit')

    def test_read_only_check_also_rejects_project_drift(self):
        (self.owner / 'PublishSettings.xml').write_text('manual settings', encoding='utf-8')
        # A valid empty symbol isolates project integrity from art validation.
        (self.owner / self.symbol).write_text('<DOMSymbolItem/>', encoding='utf-8')
        self.manifest['outputs'][0]['sha256'] = BUILD.sha(self.owner / self.symbol)
        self.save_manifest()
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(ValueError, 'PublishSettings.xml'):
                BUILD.check()


if __name__ == '__main__':
    unittest.main()
