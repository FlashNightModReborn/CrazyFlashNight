"""Recheck the allowlist without rehashing unchanged historical archives."""
from pathlib import Path
import importlib.util, json

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
spec = importlib.util.spec_from_file_location('scope', O / 'inspect-final-scope.py')
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)
assert not scope.unknown, scope.unknown
paths = [name for name in scope.pending if name not in scope.excluded]
assert all(scope.allowed(name) for name in paths)
rows = [{'path': name, 'bytes': scope.lp(R / name).stat().st_size} for name in paths]
(O / 'stage-pathspec-final.nul').write_bytes(('\0'.join(paths) + '\0').encode('utf8'))
report = {'paths': rows, 'excluded': sorted(scope.excluded), 'unknown': [],
          'boundary': 'Allowlist and file sizes only. Exact bytes are checked separately by the final staged-source verification, immutable evidence verification and Git objects; this list does not claim a second hash audit of unchanged historical archives.'}
(O / 'stage-pathspec-final-scope.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'files': len(rows), 'logicalBytes': sum(row['bytes'] for row in rows),
                  'excluded': report['excluded']}))
