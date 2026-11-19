import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import publish_asloader_incremental as publisher


class CompileOriginTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.lab = Path(self.scratch.name).resolve()
        self.patch = patch.object(publisher, 'LAB', self.lab)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.run_id = '20261119T120000Z-' + 'e' * 32
        self.run = self.lab/'runs'/self.run_id
        (self.run/'boot').mkdir(parents=True)
        self.logs = {'compilerSha256':self.run/'boot/compiler_errors.txt',
                     'outputSha256':self.run/'boot/compile_output.txt', 'consoleSha256':self.run/'boot.log'}
        proof = {'run':self.run_id,'module':'boot','buildKey':'key','sha256':'bytes',
                 'compilerErrors':0,'compilerWarnings':0,'retry32K':0}
        content = {'compilerSha256':'0 个错误, 0 个警告', 'outputSha256':'[compile] done\n', 'consoleSha256':'native child log'}
        for field, path in self.logs.items():
            path.write_text(content[field], encoding='utf-8')
            proof[field] = publisher.file_hash(path)
        self.row = {'buildKey':'key', 'sha256':'bytes',
                    'origin':{'proof':proof,'proofHash':publisher.identity(proof)}}

    def valid(self):
        return publisher.origin_valid(self.row, 'boot', 'key', 'bytes')

    def test_reuse_requires_original_compile_evidence(self):
        self.assertTrue(self.valid())
        self.logs['compilerSha256'].write_text('different diagnostics', encoding='utf-8')
        self.assertFalse(self.valid())
        self.logs['compilerSha256'].unlink()
        self.assertFalse(self.valid())

    def test_unbounded_origin_path_is_rejected(self):
        proof = self.row['origin']['proof']
        proof['run'] = '../elsewhere'
        self.row['origin']['proofHash'] = publisher.identity(proof)
        self.assertFalse(self.valid())

    def test_matching_digests_do_not_revalidate_unhealthy_native_evidence(self):
        for field, content in (('compilerSha256','0 errors, 1 warning'), ('outputSha256','no terminal line'),
                ('outputSha256','[compile] done\n[compile] FATAL'), ('consoleSha256',''),
                ('outputSha256','[compile] ASO 32K branch detected; retry\n[compile] done')):
            with self.subTest(field=field, content=content):
                path = self.logs[field]
                original = path.read_bytes()
                try:
                    path.write_text(content,encoding='utf-8')
                    proof = self.row['origin']['proof']
                    proof[field] = publisher.file_hash(path)
                    self.row['origin']['proofHash'] = publisher.identity(proof)
                    with self.assertRaises(ValueError):
                        publisher.compile_evidence(self.run, 'boot')
                    self.assertFalse(self.valid())
                finally:
                    path.write_bytes(original)
                    proof[field] = publisher.file_hash(path)
                    self.row['origin']['proofHash'] = publisher.identity(proof)
        self.assertTrue(self.valid())

    def test_module_bom_scope_checks_production_sources_and_excludes_local_runner(self):
        checker = Path(__file__).with_name('check-bom.js')
        root = self.lab / 'fixture'
        xml = root/'scripts/asLoader/LIBRARY/asLoader.xml'
        xml.parent.mkdir(parents=True)
        xml.write_text('<DOMSymbolItem/>',encoding='utf-8')
        source = root/'scripts/类定义/org/flashNight/arki/scene/Owned.as'
        source.parent.mkdir(parents=True)
        source.write_text('class Owned {}',encoding='utf-8')
        runner = root/'scripts/TestLoader.as'
        runner.write_text('// local runner',encoding='utf-8')
        def check(scope):
            return subprocess.run(['node',str(checker),'--root',str(root),scope],capture_output=True).returncode
        self.assertEqual(check('--module-scope'),1)
        source.write_text('class Owned {}',encoding='utf-8-sig')
        self.assertEqual(check('--module-scope'),0)
        self.assertEqual(check('--compile-scope'),1)

    def test_explain_distinguishes_absent_candidate_and_unlisted_name(self):
        (self.run/'effective-inputs.json').write_text(
            json.dumps({'boot':{'missing.as':None,'removed.as':'old','identical.as':'same'}}))
        changes = publisher.explain_records(self.row,'boot',{'missing.as':'new','added.as':None,'identical.as':'same'})
        self.assertEqual(changes,[
            {'path':'added.as','before':'unlisted','after':None},
            {'path':'missing.as','before':None,'after':'new'},
            {'path':'removed.as','before':'old','after':'unlisted'}])


class LayoutSelectionTests(unittest.TestCase):
    def test_standard_default_and_explicit_fallback(self):
        self.assertEqual(publisher.select_layout(None, None), ('overlay', 'default'))
        self.assertEqual(publisher.select_layout(None, 'mirror'), ('mirror', 'explicit'))
        self.assertEqual(publisher.select_layout(None, 'overlay'), ('overlay', 'explicit'))

    def test_comparison_is_an_explicit_separate_selection(self):
        self.assertEqual(publisher.select_layout('mirror', None), ('mirror', 'experiment'))
        self.assertEqual(publisher.select_layout('overlay', None), ('overlay', 'experiment'))
        with self.assertRaises(ValueError):
            publisher.select_layout('overlay', 'mirror')


if __name__ == '__main__':
    unittest.main()
