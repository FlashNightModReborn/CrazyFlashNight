"""Refresh only the sheriff dressup/icon exports after a fresh CS6 publication."""
from pathlib import Path
import json, subprocess, sys

ROOT=Path(__file__).resolve().parents[2]

def run(args):
    subprocess.run([sys.executable,'-X','utf8',*args],cwd=ROOT,check=True)

if __name__=='__main__':
    run(['tools/former-sheriff-assets/verify.py'])
    report=json.loads((ROOT/'tmp/former-sheriff-integration/build-report.json').read_text('utf8'))
    args=['tools/bake-dressup-offline.py','--export-assets','--skip-basic-assets',
          '--ffdec','tools/ffdec/ffdec.jar','--tmp-dir','tmp/former-sheriff-dressup']
    for name in report['exports']:
        if not name.startswith('图标-'):
            args+=['--name',name]
    run(args)
    args=['tools/bake-icons-offline.py','--scope','items','--ffdec','tools/ffdec/ffdec.bat',
          '--tmp-dir','tmp/former-sheriff-icons','--report','tmp/former-sheriff-integration/icon-bake-report.json']
    for name in report['exports']:
        if name.startswith('图标-'):
            args+=['--name',name[3:]]
    run(args)
    run(['tools/test-dressup-manifest-integrity.py'])
