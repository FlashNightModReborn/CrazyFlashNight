from pathlib import Path
import datetime, hashlib, json, subprocess

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
load = lambda p: json.loads(p.read_text('utf-8-sig'))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
report = load(O / 'preliminary-staged-current-input-verification-r3.json')
assert report['ok'] and not report['mismatches'] and len(report['files']) == 1578
failed = load(O / 'preliminary-staged-current-input-verification-r2.json')
assert not failed['ok'] and len(failed['mismatches']) == 3
ignored = subprocess.check_output(['git', 'check-ignore', '-v', '--', 'scripts/TestLoader.as']).decode('utf8').strip()
assert 'scripts/TestLoader.as' in ignored
names = ['agentsDoc/testing-details.md', 'agentsDoc/game-design.md',
         'tools/cf6-zombie-assets/README.md', 'tools/cf7-balance-tool/data/monster-flag-ledger.json']
rows = []
for name in names:
    data = (R / name).read_bytes()
    assert b'\r\n' not in data
    rows.append({'path': name, 'sha256': sha(R / name), 'lineEnding': 'LF', 'contentChangedByThisRepair': False})
value = {'ok': True, 'recordedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
         'firstAttempt': {'reached': 'index-membership guard', 'rejectedPath': 'scripts/TestLoader.as',
                          'sourceIndexSha256': sha(O / 'preliminary-current-source-index.json'),
                          'reason': 'A restoration-only ignored scratch original was incorrectly included in the planned committed-source set.'},
         'secondAttempt': {'report': 'preliminary-staged-current-input-verification-r2.json',
                           'reportSha256': sha(O / 'preliminary-staged-current-input-verification-r2.json'),
                           'mismatchPaths': [row['path'] for row in failed['mismatches']]},
         'resolvedAttempt': {'report': 'preliminary-staged-current-input-verification-r3.json',
                             'reportSha256': sha(O / 'preliminary-staged-current-input-verification-r3.json'),
                             'verifiedFiles': 1578},
         'ignoredScratchRule': ignored,
         'scratchBoundary': 'The private original remains ignored and untouched. Its before/after hash and fresh cleanup receipts prove restoration. Public runner templates and actual test SWFs provide the reproducible test inputs.',
         'explicitLfAttributes': rows,
         'battleInputFilesChangedByRepair': 0,
         'boundary': 'This is a preflight before the final documentation edit and seal. The final committed-source set must be verified again after those authorized document changes.'}
with (O / 'preseal-binding-preflight.json').open('x', encoding='utf8') as f:
    json.dump(value, f, ensure_ascii=False, indent=2)
print(json.dumps({'ok': True, 'verifiedFiles': 1578, 'battleInputsChanged': 0}))
