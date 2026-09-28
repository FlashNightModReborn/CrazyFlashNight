"""离线反例与 shell 回归；不把 stub 视作真正 Proton。"""
from __future__ import annotations
import base64
import copy
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import replay

PROBE = Path(os.environ['CF7_LOCALE_PROBE']).resolve()
GUARD = ROOT / 'proton-locale-guard.sh'

class NlsTests(unittest.TestCase):
    def test_fixture_identity(self):
        self.assertEqual(len(replay.load_prefix()), 540)

    def test_real_table_all_256(self):
        table = replay.parse_sbcs_table(replay.load_prefix())
        self.assertEqual(table, tuple(x & 127 for x in range(256)))

    def test_original_replay(self):
        r = replay.replay()
        self.assertTrue(r['passed'])
        self.assertFalse(r['wine_executed'])
        self.assertFalse(r['deck_executed'])

    def test_wrong_historical_hex_is_caught(self):
        o = json.loads((ROOT/'fixtures/filename-observation.json').read_text(encoding='utf8'))
        o['filenameObservation']['hostFilesystemObservation']['nameUtf8Hex'] = '61'
        self.assertFalse(replay.replay(o)['passed'])

    def test_changed_historical_long_name_is_caught(self):
        o = json.loads((ROOT/'fixtures/filename-observation.json').read_text(encoding='utf8'))
        o['filenameObservation']['wineDirectoryEnumerationLine'] = o['filenameObservation']['wineDirectoryEnumerationLine'].replace('long L"e', 'long L"f')
        self.assertFalse(replay.replay(o)['passed'])

    def test_changed_mask_is_caught(self):
        o = json.loads((ROOT/'fixtures/filename-observation.json').read_text(encoding='utf8'))
        o['filenameObservation']['wineDirectoryEnumerationLine'] = o['filenameObservation']['wineDirectoryEnumerationLine'].replace('52a0','52a1')
        self.assertFalse(replay.replay(o)['passed'])

    def test_truncated_header_rejected(self):
        with self.assertRaises(ValueError): replay.parse_sbcs_table(b'\0'*20)

    def test_truncated_table_rejected(self):
        with self.assertRaises(ValueError): replay.parse_sbcs_table(replay.load_prefix()[:-1])

    def test_wrong_codepage_rejected(self):
        data=bytearray(replay.load_prefix()); struct.pack_into('<H',data,2,1252)
        with self.assertRaises(ValueError): replay.parse_sbcs_table(data)

    def test_dbcs_rejected(self):
        data=bytearray(replay.load_prefix()); struct.pack_into('<H',data,4,2)
        with self.assertRaises(ValueError): replay.parse_sbcs_table(data)

    def test_bad_header_offset_rejected(self):
        data=bytearray(replay.load_prefix()); struct.pack_into('<H',data,0,0)
        with self.assertRaises(ValueError): replay.parse_sbcs_table(data)

    def test_modified_prefix_rejected(self):
        data=bytearray(replay.load_prefix()); data[-1] ^= 1
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'mutated.b64';p.write_text(base64.b64encode(data).decode('ascii'))
            with self.assertRaises(ValueError): replay.load_prefix(p)

    def test_wine_escapes(self):
        self.assertEqual(replay.decode_wine_string(r'e\n h\0003\000cf\0019/'), 'e\n h\x03\x0cf\x19/')
        self.assertEqual(replay.decode_wine_string(r'\52a0\8f7d'), '加载')

    def test_unknown_escape_rejected(self):
        with self.assertRaises(ValueError): replay.decode_wine_string(r'\q')

    def test_trailing_escape_rejected(self):
        with self.assertRaises(ValueError): replay.decode_wine_string('x\\')

    def test_missing_field_rejected(self):
        with self.assertRaises(ValueError): replay.extract_wine_field('no field', 'long')

class ModelTests(unittest.TestCase):
    def test_native_matrix_all_cases(self):
        result=replay.matrix(PROBE)
        self.assertEqual(result['case_count'],16)
        self.assertTrue(result['passed'])

    def test_model_does_not_mutate_input(self):
        env={'LANG':'C','LC_ALL':'C.UTF-8'}; old=env.copy()
        actual=replay.proton_locale_environment(env)
        self.assertEqual(env,old);self.assertNotIn('LC_ALL',actual)

    def test_nonempty_host_overrides(self):
        self.assertEqual(replay.proton_locale_environment({'HOST_LC_ALL':'POSIX','LC_ALL':'C.UTF-8'})['LC_ALL'],'POSIX')

    def test_empty_host_removes_all(self):
        self.assertNotIn('LC_ALL',replay.proton_locale_environment({'HOST_LC_ALL':'','LC_ALL':'C.UTF-8'}))

    def test_setlocale_failure_is_utf8_fallback_not_20127(self):
        self.assertEqual(replay.source_model_codepage({'setlocale_ok':False,'libc_codeset':'ANSI_X3.4-1968'}),65001)

    def test_missing_nls_keeps_default_utf8(self):
        self.assertEqual(replay.source_model_codepage({'setlocale_ok':True,'libc_codeset':'ANSI_X3.4-1968'},False),65001)

    def test_unknown_codeset_is_not_guessed(self):
        self.assertIsNone(replay.source_model_codepage({'setlocale_ok':True,'libc_codeset':'GB18030'}))

    def test_native_environment_bytes_are_escaped(self):
        env={'LANG':'C.UTF-8','LANGUAGE':'quote"slash\\\n中文'}
        out=replay.native_probe(PROBE,env,'stage"\n')
        self.assertEqual(out['stage'],'stage"\n')
        self.assertEqual(out['environment_bytes']['LANGUAGE'].encode('latin1'),env['LANGUAGE'].encode('utf8'))

    def test_python_utf8_false_positive(self):
        env={'PATH':os.defpath,'LANG':'C','LC_CTYPE':'C','LC_ALL':'C','PYTHONUTF8':'1'}
        r=subprocess.run([sys.executable,'-c','import sys;print(sys.getfilesystemencoding())'],env=env,capture_output=True,check=True)
        self.assertEqual(r.stdout.strip(),b'utf-8')
        self.assertEqual(replay.native_probe(PROBE,env,'same-explicit-env')['exit_code'],20)

class GuardTests(unittest.TestCase):
    def run_guard(self,*args,extra=None):
        env={'PATH':os.defpath,'LANG':'C.UTF-8','LC_CTYPE':'C','CF7_LOCALE_PROBE':str(PROBE)}
        if extra:env.update(extra)
        return subprocess.run(['/bin/sh',str(GUARD),*args],env=env,capture_output=True,timeout=10)

    def test_bad_effective_locale_rejected(self):
        r=self.run_guard('--check');self.assertEqual(r.returncode,20)
        self.assertIn(b'GATE_REJECT',r.stderr)

    def test_outer_all_alone_is_not_accepted(self):
        self.assertEqual(self.run_guard('--check',extra={'LC_ALL':'C.UTF-8'}).returncode,20)

    def test_explicit_utf8_locale_passes(self):
        self.assertEqual(self.run_guard('--locale','C.UTF-8','--check').returncode,0)

    def test_invalid_locale_rejected_even_wine_fallback(self):
        self.assertEqual(self.run_guard('--locale','CF7_MISSING_LOCALE.UTF-8','--check').returncode,21)

    def test_c_locale_rejected(self):
        self.assertEqual(self.run_guard('--locale','C','--check').returncode,20)

    def test_empty_locale_rejected(self):
        self.assertEqual(self.run_guard('--locale','','--check').returncode,2)

    def test_missing_locale_argument_rejected(self):
        self.assertEqual(self.run_guard('--locale').returncode,2)

    def test_missing_command_rejected(self):
        self.assertEqual(self.run_guard('--').returncode,2)

    def test_extra_argument_after_check_rejected(self):
        self.assertEqual(self.run_guard('--check','oops').returncode,2)

    def test_bad_probe_rejected(self):
        self.assertEqual(self.run_guard('--check',extra={'CF7_LOCALE_PROBE':'/nonexistent/cf7-probe'}).returncode,2)

    def test_guard_argv_and_child_exit_preserved(self):
        code='import json,os,sys;print(json.dumps([sys.argv[1:],os.getenv("HOST_LC_ALL"),os.getenv("LC_ALL")]));sys.exit(37)'
        args=['中文 spaced','$(never-evaluate)','a"b',"x'y",'']
        r=self.run_guard('--locale','C.UTF-8','--',sys.executable,'-c',code,*args)
        self.assertEqual(r.returncode,37)
        self.assertEqual(json.loads(r.stdout),[args,'C.UTF-8','C.UTF-8'])

    def test_rejected_gate_does_not_launch_command(self):
        with tempfile.TemporaryDirectory() as d:
            marker=Path(d)/'must-not-exist'
            r=self.run_guard('--',sys.executable,'-c','import pathlib,sys;pathlib.Path(sys.argv[1]).touch()',str(marker))
            self.assertEqual(r.returncode,20);self.assertFalse(marker.exists())

class FixtureTests(unittest.TestCase):
    def test_pair_content_identical(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'new-fixture';r=replay.prepare_fixture(p)
            self.assertEqual((p/'ascii.bin').read_bytes(),(p/'加载背景.bin').read_bytes())
            self.assertEqual(r['bytes'],len(replay.PAYLOAD))

    def test_existing_directory_not_overwritten(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);sentinel=p/'ascii.bin';sentinel.write_bytes(b'keep')
            with self.assertRaises(FileExistsError):replay.prepare_fixture(p)
            self.assertEqual(sentinel.read_bytes(),b'keep')

    def test_existing_report_not_overwritten(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'result.json';p.write_text('keep')
            r=subprocess.run([sys.executable,str(ROOT/'replay.py'),'--output',str(p)],capture_output=True)
            self.assertEqual(r.returncode,2);self.assertEqual(p.read_text(),'keep')

if __name__=='__main__':unittest.main(verbosity=2)
