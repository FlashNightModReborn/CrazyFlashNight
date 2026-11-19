import json
import unittest
from pathlib import Path
from unittest.mock import patch

import asloader_overlay_experiment as overlay
import asloader_incremental_inputs as inputs
import test_asloader_incremental_inputs as source_fixture


def sample():
    catalog = {m: {'classes': [m + '.Owner']} for m in overlay.ORDER}
    visible = ['resident/Owner.as', 'shared/Owner.as', 'boot/Owner.as', 'test/Only.as']
    files = {overlay.CATALOG: json.dumps(catalog).encode(), overlay.MIRRORS + 'manifest.json': b'{}'}
    modules = {}
    for name in visible:
        files[overlay.CLASSES + name] = ('implementation ' + name).encode()
    for module in overlay.ORDER:
        xfl = f'scripts/{module}/main.xfl'
        modules[module] = {'xfl': xfl, 'compileDigest': module, 'buildKey': module}
        prefix = overlay.MIRRORS + module + '/types/'
        files[f'scripts/{module}/PublishSettings.xml'] = (
            f'<settings><PackagePaths>../{prefix[:-1]};类定义;</PackagePaths></settings>').encode()
        for name in visible:
            owner = name.split('/')[0]
            files[prefix + name] = (('declaration ' + name).encode() if owner in overlay.ORDER and owner != module
                                    else files[overlay.CLASSES + name])
    return {'sourceSnapshotId': 'sample', 'modules': modules}, files


class OverlayComparison(unittest.TestCase):
    def plan(self, layout, fixture=None):
        def capture(*args, records_by_module=None, **kwargs):
            plan, files = fixture or sample()
            if records_by_module is not None:
                for module, row in plan['modules'].items():
                    prefix = overlay.MIRRORS + module + '/types/'
                    profile = str(Path(row['xfl']).parent.as_posix()) + '/PublishSettings.xml'
                    records_by_module[module] = {p: inputs.sha(data) for p, data in files.items()
                                                 if p.startswith(prefix) or p == profile}
            return plan, files
        with patch.object(overlay, 'collect', side_effect=capture):
            return overlay.comparison_plan(Path('.'), Path('workspace'), 'tool', 'validator', layout)

    def test_same_effective_source_separate_key_and_physical_projection(self):
        mirror, mirror_files = self.plan('mirror')
        tested, files = self.plan('overlay')
        self.assertEqual(mirror['comparison']['sourceId'], tested['comparison']['sourceId'])
        self.assertNotEqual(mirror['sourceSnapshotId'], tested['sourceSnapshotId'])
        for module in overlay.ORDER:
            old = overlay.MIRRORS + module + '/types/'
            new = 'tmp/asloader-overlay/' + module + '/stubs/'
            self.assertNotEqual(mirror['modules'][module]['buildKey'], tested['modules'][module]['buildKey'])
            for p in mirror_files:
                if p.startswith(old):
                    name = p[len(old):]
                    self.assertNotIn(p, files)
                    self.assertEqual(mirror_files[p], files.get(new + name, files[overlay.CLASSES + name]))
            self.assertEqual(tested['comparison']['modules'][module]['projectedTypeFiles'], 2)
            self.assertNotIn(new + module + '/Owner.as', files)
            self.assertNotIn(new + 'test/Only.as', files)

    def test_changed_fallback_or_nonstandard_classpath_rejected(self):
        result, files = sample()
        files[overlay.CLASSES + 'resident/Owner.as'] = b'stale source'
        with self.assertRaisesRegex(ValueError, 'effective source'):
            self.plan('overlay', (result, files))
        result, files = sample()
        files['scripts/resident/PublishSettings.xml'] = b'<settings><PackagePaths>.</PackagePaths></settings>'
        with self.assertRaisesRegex(ValueError, 'classpath'):
            self.plan('overlay', (result, files))

    def test_real_overlay_explain_sync_and_project_retirement(self):
        fixture = source_fixture.InputTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        adjacent = 'scripts/类定义/app/PeerMacro.as'
        directive = '#include "PeerMacro.as"\n'
        fixture.source(adjacent, '// class-relative macro')
        fixture.source(fixture.shared, directive + fixture.shared_body())
        def plan(previous=None):
            details, projects = {}, {}
            result, files = overlay.comparison_plan(
                fixture.root, fixture.snapshot, 'tool', 'validator', 'overlay',
                records_by_module=details, project_report=projects, previous_projects=previous)
            return result, files, details, projects

        result, shadow, records, projects = plan()
        provider = 'scripts/asLoaderShared/PublishSettings.xml'
        header = 'tmp/asloader-overlay/boot/stubs/app/Shared.as'
        self.assertIn(b'asloader-overlay/shared/stubs', shadow[provider])
        self.assertEqual(records['shared'][provider], inputs.sha(shadow[provider]))
        self.assertEqual(records['shared'][fixture.shared], inputs.sha(shadow[fixture.shared]))
        self.assertEqual(records['boot'][header], inputs.sha(shadow[header]))
        self.assertIn(directive.strip().encode(), shadow[header])
        self.assertEqual(records['boot'][adjacent], inputs.sha(shadow[adjacent]))
        self.assertIsNone(records['boot']['tmp/asloader-overlay/boot/stubs/app/PeerMacro.as'])
        self.assertIn(fixture.macro, records['shared'])
        for detail in records.values():
            self.assertFalse(any(p.startswith(overlay.MIRRORS) for p in detail))
        self.assertTrue(any(value is None for value in records['shared'].values()))
        self.assertIn(b'asloader-modules/shared/types', projects['canonicalWrites'][provider])
        self.assertNotEqual(shadow[provider], projects['canonicalWrites'][provider])
        inputs.sync_projects(fixture.root, projects, projects['canonicalWrites'])
        self.assertEqual(inputs.sha((fixture.root/provider).read_bytes()), projects['ownership']['outputs'][provider])
        self.assertFalse((fixture.root/'tmp/asloader-overlay').exists())
        baseline, _, before, settled = plan(projects['ownership'])
        self.assertEqual(settled['changes'], [])
        self.assertEqual(settled['canonicalWrites'], {})
        without_explain, _ = overlay.comparison_plan(
            fixture.root, fixture.snapshot, 'tool', 'validator', 'overlay',
            project_report={}, previous_projects=settled['ownership'])
        self.assertEqual(baseline, without_explain)
        fixture.source(fixture.shared, directive + fixture.shared_body(2))
        body, _, after, _ = plan(settled['ownership'])
        self.assertEqual(fixture.changed(baseline, body), {'shared'})
        self.assertNotEqual(before['shared'][fixture.shared], after['shared'][fixture.shared])
        self.assertEqual(before['boot'][header], after['boot'][header])
        cat = json.loads((fixture.root/inputs.CATALOG).read_bytes())
        cat['shared']['xfl'] = 'scripts/movedShared/asLoaderShared.xfl'
        fixture.put(inputs.CATALOG, json.dumps(cat).encode())
        _, _, _, moved = plan(settled['ownership'])
        self.assertIn(provider, {c['path'] for c in moved['changes'] if c['after'] is None})
        self.assertNotIn(provider, moved['canonicalWrites'])
        inputs.sync_projects(fixture.root, moved, moved['canonicalWrites'])
        self.assertFalse((fixture.root/provider).exists())
        self.assertIn(b'asloader-modules/shared/types', (fixture.root/'scripts/movedShared/PublishSettings.xml').read_bytes())


if __name__ == '__main__':
    unittest.main()
