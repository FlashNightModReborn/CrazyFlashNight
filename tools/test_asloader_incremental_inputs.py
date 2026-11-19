"""Exercise the real generator and the isolated file collector on small AS2 projects."""
import json
import os
import tempfile
import unittest
from pathlib import Path

import asloader_incremental_inputs as inc


class InputTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name) / 'repo'
        self.snapshot = Path(tmp.name) / 'workspace'
        self.live = inc.builder.ROOT
        self.shared = 'scripts/类定义/app/Shared.as'
        self.loose = 'scripts/类定义/app/Loose.as'
        self.macro = 'scripts/macros/example.as'
        for rel in (*inc.RECIPES, *inc.VALIDATORS, inc.MAIN,
                    'scripts/compile_test.ps1', 'scripts/publish-asloader-modules.ps1',
                    'data/rewards/choice-rewards.runtime.json', 'scripts/asLoader/MobileSettings.xml',
                    'scripts/asLoader/asLoader.xfl', 'scripts/asLoader/DOMDocument.xml',
                    'scripts/asLoader/PublishSettings.xml'):
            self.put(rel, (self.live / rel).read_bytes())
        catalog = json.loads((self.live / inc.CATALOG).read_bytes())
        catalog['shared']['classes'] = ['app.Shared']
        catalog['boot']['classes'] = ['app.Boot']
        self.put(inc.CATALOG, json.dumps(catalog).encode())
        self.source(inc.CLASSES + 'org/flashNight/neur/Server/SaveManager.as',
                    'class org.flashNight.neur.Server.SaveManager {}')
        self.source(self.shared, self.shared_body())
        self.source(inc.CLASSES + 'app/Boot.as', 'class app.Boot {}')
        self.source(self.loose, 'class app.Loose {}')
        self.source(self.macro, 'var value = 1;')
        self.source('scripts/asLoaderBootstrap.as', 'this.stop();')
        self.source('scripts/frames/level1.as', '#include "../frames/level2.as"')
        self.source('scripts/frames/level2.as', 'this.stop();')
        self.put('scripts/asLoader/LIBRARY/asLoader.xml',
                 b'<DOMSymbolItem><script><![CDATA[#include "../frames/level1.as"]]></script></DOMSymbolItem>')

    def shared_body(self, number=1, arg='v:Number'):
        return (f'class app.Shared {{\n public function value({arg}):Number {{\n'
                f'#include "../macros/example.as"\n return {number};\n }}\n}}')

    def put(self, rel, data):
        target = self.root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)

    def source(self, rel, text):
        self.put(rel, inc.builder.BOM + text.encode())

    def plan(self, toolchain='sdk', validation='validators'):
        return inc.collect(self.root, self.snapshot, toolchain, validation)

    def changed(self, before, after):
        return {m for m in inc.ORDER if before['modules'][m]['buildKey'] !=
                after['modules'][m]['buildKey']}

    def project_plan(self, previous=None):
        report = {}
        _, files = inc.collect(self.root, self.snapshot, 'sdk', 'validators',
                               project_report=report, previous_projects=previous)
        return report, files

    def test_project_only_catalog_add_remove_and_stale_edit(self):
        initial, files = self.project_plan()
        inc.sync_projects(self.root, initial, files)
        old = initial['ownership']
        unrelated = 'scripts/asLoaderShared/LIBRARY/authored.xml'
        self.put(unrelated, b'<DOMSymbolItem/>')
        cat = json.loads((self.root/inc.CATALOG).read_bytes())
        cat['shared']['classes'].append('app.Loose')
        self.put(inc.CATALOG, json.dumps(cat).encode())
        report, files = self.project_plan(old)
        paths = {r['path'] for r in report['changes']}
        expected = {'scripts/asLoaderModuleRoots/shared.as', 'scripts/asLoader/asLoader_exclude.xml',
                    'scripts/asLoaderBootstrap/asLoaderBootstrap_exclude.xml'}
        self.assertEqual(paths, expected)
        untouched = self.root/'scripts/asLoaderShared/DOMDocument.xml'
        timestamp = untouched.stat().st_mtime_ns
        first, last = sorted(paths)[0], sorted(paths)[-1]
        originals = {p: (self.root/p).read_bytes() for p in paths}
        self.put(last, b'concurrent edit')
        with self.assertRaisesRegex(ValueError, 'changed after capture'):
            inc.sync_projects(self.root, report, files)
        self.assertEqual((self.root/first).read_bytes(), originals[first])
        self.assertEqual((self.root/last).read_bytes(), b'concurrent edit')
        self.put(last, originals[last])
        inc.sync_projects(self.root, report, files)
        self.assertEqual(self.project_plan(report['ownership'])[0]['changes'], [])
        self.assertEqual(untouched.stat().st_mtime_ns, timestamp)
        self.assertEqual((self.root/unrelated).read_bytes(), b'<DOMSymbolItem/>')
        self.assertFalse((self.root/'tmp/asloader-modules').exists())
        cat['shared']['classes'].remove('app.Loose')
        self.put(inc.CATALOG, json.dumps(cat).encode())
        removed, files = self.project_plan(report['ownership'])
        self.assertEqual({r['path'] for r in removed['changes']}, expected)
        inc.sync_projects(self.root, removed, files)
        self.assertEqual(removed['ownership'], old)

    def test_retire_only_previously_owned_unchanged_paths(self):
        initial, files = self.project_plan()
        inc.sync_projects(self.root, initial, files)
        old = initial['ownership']
        stale = 'scripts/asLoaderShared/DOMDocument.xml'
        old_bytes = (self.root/stale).read_bytes()
        own_asset = 'scripts/asLoaderShared/LIBRARY/manual.xml'
        self.put(own_asset, b'hand authored')
        cat = json.loads((self.root/inc.CATALOG).read_bytes())
        cat['shared']['xfl'] = 'scripts/asLoaderSharedMoved/asLoaderShared.xfl'
        self.put(inc.CATALOG, json.dumps(cat).encode())
        self.put(stale, b'changed since last publication')
        with self.assertRaisesRegex(ValueError, 'Retired project file has unrecognized bytes'):
            self.project_plan(old)
        self.put(stale, old_bytes)
        moved, files = self.project_plan(old)
        self.assertIn(stale, {r['path'] for r in moved['changes'] if r['after'] is None})
        self.assertTrue(all(r['after'] is not None for r in self.project_plan()[0]['changes']))
        inc.sync_projects(self.root, moved, files)
        self.assertFalse((self.root/stale).exists())
        self.assertEqual((self.root/own_asset).read_bytes(), b'hand authored')
        self.assertTrue((self.root/'scripts/asLoaderSharedMoved/DOMDocument.xml').is_file())

    def test_method_implementation_signature_and_loose_source(self):
        base, _ = self.plan()
        self.source(self.shared, self.shared_body(2))
        body, _ = self.plan()
        self.assertEqual(self.changed(base, body), {'shared'})
        self.source(self.shared, self.shared_body(2, 'v:String'))
        signature, _ = self.plan()
        self.assertEqual(self.changed(body, signature), set(inc.ORDER))
        self.source(self.loose, 'class app.Loose { var x; }')
        loose, _ = self.plan()
        self.assertEqual(self.changed(signature, loose), set(inc.ORDER))
        self.assertFalse(self.snapshot.exists())

    def test_includes_nested_frames_and_new_resolution_candidate(self):
        original, _ = self.plan()
        self.source(self.macro, 'var value = 2;')
        macro, _ = self.plan()
        self.assertEqual(self.changed(original, macro), {'shared'})
        self.source('scripts/frames/level2.as', 'this.play();')
        frame, _ = self.plan()
        self.assertEqual(self.changed(macro, frame), {'boot'})
        # This higher priority candidate is outside the original class namespace.
        self.source('scripts/asLoaderShared/macros/raw.as', '#include "../macros/example.as"')
        with_asset, _ = self.plan()
        self.assertEqual(self.changed(frame, with_asset), {'shared'})
        self.source(inc.CLASSES + 'macros/example.as', 'var value = 3;')
        shadowed, _ = self.plan()
        self.assertIn('shared', self.changed(with_asset, shadowed))
        self.source('scripts/frames/level2.as', '#include "../frames/level1.as"')
        with self.assertRaisesRegex(ValueError, 'Recursive'):
            self.plan()

    def test_policy_toolchain_and_raw_main(self):
        base, _ = self.plan()
        policy, _ = self.plan(validation='other')
        self.assertEqual(self.changed(base, policy), set())
        self.assertNotEqual(base['validationKey'], policy['validationKey'])
        self.put(inc.MAIN, b'other main')
        main, _ = self.plan()
        self.assertEqual(self.changed(base, main), set())
        self.assertNotEqual(base['validationKey'], main['validationKey'])
        compiler, _ = self.plan(toolchain='sdk2')
        self.assertEqual(self.changed(main, compiler), set(inc.ORDER))
        self.assertEqual(main['sourceSnapshotId'], compiler['sourceSnapshotId'])

    def test_prepare_verify_remove_deleted_and_detect_drift(self):
        original, files = self.plan()
        inc.materialize(self.root, self.snapshot, original, files)
        isolated = self.snapshot / self.shared
        self.assertNotEqual(isolated.stat().st_ino, (self.root / self.shared).stat().st_ino)
        inc.materialize(self.root, self.snapshot, original, files, verify=True)
        self.source(self.shared, self.shared_body(2))
        (self.root / self.loose).unlink()
        updated, files = self.plan()
        with self.assertRaisesRegex(ValueError, 'changed since prepare'):
            inc.materialize(self.root, self.snapshot, updated, files, verify=True)
        inc.materialize(self.root, self.snapshot, updated, files)
        for module in inc.ORDER:
            self.assertFalse((self.snapshot / f'{inc.MIRRORS}{module}/types/app/Loose.as').exists())
        self.assertFalse((self.snapshot / self.loose).exists())
        isolated.write_bytes(b'unexpected')
        with self.assertRaisesRegex(ValueError, 'Frozen input differs'):
            inc.materialize(self.root, self.snapshot, updated, files, verify=True)

    def test_unowned_directory_and_alias_refused(self):
        plan, files = self.plan()
        self.snapshot.mkdir()
        unexpected = self.snapshot / 'unrelated'
        unexpected.write_text('keep')
        with self.assertRaisesRegex(ValueError, 'empty or owned'):
            inc.materialize(self.root, self.snapshot, plan, files)
        self.assertEqual(unexpected.read_text(), 'keep')
        unexpected.unlink()
        inc.materialize(self.root, self.snapshot, plan, files)
        isolated = self.snapshot / self.shared
        isolated.unlink()
        os.link(self.root / self.shared, isolated)
        with self.assertRaisesRegex(ValueError, 'hard-linked'):
            inc.materialize(self.root, self.snapshot, plan, files)

    def test_verify_reads_equal_length_file_with_restored_timestamp(self):
        plan, files = self.plan()
        inc.materialize(self.root, self.snapshot, plan, files)
        changed = self.snapshot / self.macro
        before = changed.stat()
        original = changed.read_bytes()
        changed.write_bytes(original.replace(b'1', b'2'))
        os.utime(changed, ns=(before.st_atime_ns, before.st_mtime_ns))
        with self.assertRaisesRegex(ValueError, 'Frozen input differs'):
            inc.materialize(self.root, self.snapshot, plan, files, verify=True)
        inc.materialize(self.root, self.snapshot, plan, files)
        self.assertEqual(changed.read_bytes(), original)
        self.assertGreater(changed.stat().st_mtime_ns, before.st_mtime_ns)

    def test_unsafe_paths_missing_bom_unmanaged_package_path(self):
        self.source('scripts/frames/level2.as', '#include "C:/live/file.as"')
        with self.assertRaisesRegex(ValueError, 'Unsupported source path'):
            self.plan()
        self.put('scripts/frames/level2.as', b'this.play();')
        with self.assertRaisesRegex(ValueError, 'BOM'):
            self.plan()
        self.source('scripts/frames/level2.as', 'this.play();')
        profile = self.root / 'scripts/asLoader/PublishSettings.xml'
        profile.write_bytes(profile.read_bytes().replace(b'<PackagePaths>', b'<PackagePaths>C:/outside;'))
        with self.assertRaisesRegex(ValueError, 'Unmanaged'):
            self.plan()


if __name__ == '__main__':
    unittest.main()
