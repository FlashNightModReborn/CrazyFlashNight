"""Verify the final package without modifying its immutable contents."""
from pathlib import Path
import argparse, gzip, hashlib, io, json, re, subprocess, zipfile
import xml.etree.ElementTree as ET

args = argparse.ArgumentParser()
args.add_argument('--output', type=Path, required=True)
a = args.parse_args()
R = Path.cwd()
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'

def lp(p):
    value = str(Path(p).resolve())
    return Path(value if value.startswith('\\\\?\\') else '\\\\?\\' + value)

def read(p): return lp(p).read_bytes()
def digest(data): return hashlib.sha256(data).hexdigest()
def sha(p): return digest(read(p))
def load(p): return json.loads(read(p).decode('utf-8-sig'))

integrity = load(P / 'integrity.json')
indexed = {row['path']: row for row in integrity['files']}
assert len(indexed) == len(integrity['files']) == integrity['fileCount']
actual = {p.relative_to(lp(P)).as_posix() for p in lp(P).rglob('*') if p.is_file()}
assert actual == set(indexed) | {'integrity.json'}, (actual - set(indexed), set(indexed) - actual)
for name, row in indexed.items():
    data = read(P / name)
    assert len(data) == row['bytes'] and digest(data) == row['sha256'], name
assert sum(row['bytes'] for row in indexed.values()) == integrity['totalBytes']
maximum = max(lp(P / name).stat().st_size for name in actual)
assert maximum <= 8_000_000, maximum

mapping = load(P / 'lossless-mapping.json')['files']
restored = {}
for row in mapping:
    pieces = []
    for part in row['parts']:
        data = read(P / part['path'])
        assert len(data) == part['bytes'] and digest(data) == part['sha256'], part['path']
        pieces.append(data)
    data = b''.join(pieces)
    if row['encoding'] == 'gzip': data = gzip.decompress(data)
    else: assert row['encoding'] == 'identity', row['encoding']
    assert len(data) == row['originalBytes'] and digest(data) == row['originalSha256'], row['source']
    key = tuple(part['path'] for part in row['parts'])
    if key in restored: assert restored[key] == row['originalSha256']
    restored[key] = row['originalSha256']

closure = load(P / 'final-closure.json')
staged_sources = load(P / closure['sourceCheckoutPolicy']['report'])
assert staged_sources['ok']
staged_by_path = {row['path']: row for row in staged_sources['files']}
strict_rows = [row for row in staged_sources['files'] if row['sourceRole'] == 'strict_checkout_input']
assert len(strict_rows) == closure['sourceCheckoutPolicy']['strictCheckoutFiles']
assert all(row['matches'] and row['accepted'] for row in strict_rows)
assert len(staged_sources['hostCheckoutLineEndingDifferences']) == closure['sourceCheckoutPolicy']['explicitExistingHostLineEndingConversions']
for row in staged_sources['hostCheckoutLineEndingDifferences']:
    assert row['sourceRole'] == 'additional_frozen_host_source' and row['accepted'] and not row['matches']
    assert row['explicitCheckoutConversion'] == 'line_endings_only'
    assert row['workingSha256'] == row['expectedSha256']
    assert row['canonicalLfSha256'] == row['gitBlobCanonicalLfSha256'] == row['checkoutCanonicalLfSha256']
git_index = {}
for record in subprocess.check_output(['git', 'ls-files', '--stage', '-z']).split(b'\0'):
    if not record: continue
    meta, path = record.split(b'\t', 1)
    mode, oid, stage = meta.decode('ascii').split()
    assert stage == '0'
    git_index[path.decode('utf8')] = oid
for name, row in staged_by_path.items():
    assert git_index[name] == row['indexOid'], 'Committed source object changed: ' + name

def verify_working_source(name, expected_sha):
    current_sha = sha(R / name)
    if current_sha == expected_sha: return
    row = staged_by_path[name]
    assert row['sourceRole'] == 'additional_frozen_host_source' and row['explicitCheckoutConversion'] == 'line_endings_only'
    assert row['expectedSha256'] == expected_sha
    assert current_sha == row['checkoutSha256'], 'Source changed beyond its recorded checkout conversion: ' + name

source_name = closure['frozenSourceArchive']
matches = [row for row in mapping if row['parts'][0]['path'] in (source_name, source_name + '.gz') or row['parts'][0]['path'].startswith(source_name + '.gz.part') or row['parts'][0]['path'].startswith(source_name + '.part')]
assert len(matches) == 1, len(matches)
source_row = matches[0]
source_data = b''.join(read(P / part['path']) for part in source_row['parts'])
if source_row['encoding'] == 'gzip': source_data = gzip.decompress(source_data)
source_index = load(P / (source_name + '.index.json'))['files']
with zipfile.ZipFile(io.BytesIO(source_data)) as z:
    assert z.namelist() == [row['path'] for row in source_index]
    for row in source_index:
        data = z.read(row['path'])
        assert len(data) == row['bytes'] and digest(data) == row['sha256'], row['path']
        verify_working_source(row['path'], row['sha256'])

for row in closure['currentSwfs']:
    assert sha(R / row['source']) == sha(P / row['copy']) == row['sha256'], row['source']

selected = closure['selectedArena']
assert {entry['unit'] for entry in selected} == {'headbot', 'elder'}
head_full = None
elder_bindings = None
for entry in selected:
    rows = load(P / entry['path'] / 'all-results.json')
    assert len(rows) == entry['expectedRows'] and all(not row['errors'] for row in rows)
    assert load(P / entry['path'] / 'display-assessment.json')['qualified']
    identity = load(P / entry['path'] / 'plan/input-identity.json')
    assert all(row['authorityContext']['sourceBindings'] == identity['sourceBindings'] for row in rows)
    for binding in identity['sourceBindings']:
        assert sha(R / binding['path']) == binding['sha256'], 'Current selected binding changed: ' + binding['path']
    if entry['unit'] == 'elder':
        analysis = load(P / entry['path'] / 'acceptance-summary.json')
        assert analysis['profile'] == 'high-level-beast-near-death-exusiai-net-hp-minority-wins-v2'
        assert len(rows) == 36 and analysis['strengthPassed'] and len(analysis['groups']) == 6
        assert analysis['expectedLevels'] == [60, 80, 100]
        assert all(row['authorityContext']['candidateUnitId'] == 473 and row['authorityContext']['successorUnitId'] == 474 for row in rows)
        elder_bindings = identity['sourceBindings']
    else:
        analysis = load(P / entry['path'] / 'strength-summary.json')
        assert len(rows) == 18 and analysis['strengthPassed'] and analysis['wins'] == 18 and analysis['timeouts'] == 0
        assert all(row['authorityContext']['candidateUnitId'] == 472 for row in rows)
        head_full = analysis

assert head_full is not None and elder_bindings is not None
for row in head_full['sourceBindings']:
    assert sha(R / row['path']) == row['sha256'], 'Current full-matrix Head binding changed: ' + row['path']
loader_scope = load(P / closure['mergedLoaderClassScopePath'])
assert loader_scope['qualified'] and not loader_scope['removedClasses']
assert loader_scope['afterSha256'] == sha(R / 'scripts/asLoader.swf')
assert set(loader_scope['changedExistingClasses']) <= {'org.flashNight.arki.scene.StageManager', 'org.flashNight.arki.scene.WaveSpawner'}
assert set(loader_scope['addedClasses']) <= {'org.flashNight.arki.scene.BaseSiegeController', 'org.flashNight.arki.scene.BaseSiegeRules'}

summary = load(P / 'summary.json')
assert summary['sealed'] and summary['allGoalsMet']
assert not summary['formalRuntimePromoted']
assert not summary['headbot']['subsequentMergedLoaderIntegrationPending']
native = load(P / closure['nativeReport'])
restoration_only = {row['path']: row for row in closure['restorationOnlyBindings']}
assert set(restoration_only) == {'scripts/TestLoader.as'}
assert restoration_only['scripts/TestLoader.as']['sha256'] == native['cleanup']['originalRunnerSha256'].lower()
assert native['ok'] and native['passed'] == 2671 and native['failed'] == 0
assert len(native['freshSuites']) == 4 and native['selectedNativeImages'] == 12
for suite in native['freshSuites']:
    folder = P / 'current-final-validation/native/four-suites' / suite['suite']
    before = load(folder / 'bindings-before.json')
    assert before == load(folder / 'bindings-after.json') and len(before) == 148
    assert sha(folder / 'flashlog.txt') == suite['traceSha256']
    assert sha(folder / 'TestLoader.swf') == suite['testSwfSha256']
    for row in before:
        if row['path'] in restoration_only:
            assert row['sha256'].lower() == restoration_only[row['path']]['sha256']
        else:
            assert sha(R / row['path']) == row['sha256'].lower(), row['path']
host = load(P / closure['hostReport'])
assert host['ok'] and host['failed'] == host['skipped'] == 0
assert host['serialPolicyObserved'] and not host['wholeHostSuitePassed']
host_sources = load(P / 'current-final-validation/host/source-before.json')
assert host_sources == load(P / 'current-final-validation/host/source-after.json')
for row in host_sources['files']:
    verify_working_source(row['path'], row['sha256'])
display = load(P / closure['displayClosure'])
assert display['ok'] and not display['displayHoldActive'] and not display['persistentPowerPlanChanged']
prior = load(P / closure['priorIntegrityReport'])
assert prior['ok'] and prior['integrityRecords'] == 25 and prior['indexedPackages'] == 24 and prior['summaryOnlyRecords'] == 1
for original in prior['packages']:
    assert sha(R / original['path']) == original['sha256'], original['path']
result = {'ok': True, 'indexedFiles': len(indexed), 'totalBytes': integrity['totalBytes'],
          'maximumFileBytes': maximum, 'losslessMappingsVerified': len(mapping),
          'frozenCurrentSourceFiles': len(source_index), 'currentSwfsVerified': len(closure['currentSwfs']),
          'selectedArenaRows': sum(entry['expectedRows'] for entry in selected),
          'currentHeadFullMatrixBindingsVerified': len(head_full['sourceBindings']),
          'currentElderFullMatrixBindingsVerified': len(elder_bindings),
          'currentRegistrationIds': [472, 473, 474],
          'mergedLoaderClassScopeQualified': True,
          'compiledSharedClassActionsCompared': len(loader_scope['classes']),
          'freshNativeChecksPassed': native['passed'], 'freshHostFocusedPassed': host['passed'],
          'nativeReproducibleBindingsPerSuite': 147, 'nativeScratchRestorationBindings': 1,
          'strictCheckoutFiles': len(strict_rows),
          'explicitExistingHostCheckoutConversions': len(staged_sources['hostCheckoutLineEndingDifferences']),
          'displayHoldReleased': True, 'priorIntegrityRecordsRetained': prior['integrityRecords'],
          'priorIndexedPackagesRetained': prior['indexedPackages'],
          'primaryIntegritySha256': sha(P / 'integrity.json'),
          'formalRuntimePromoted': False, 'standardEntryVerified': False,
          'humanPlayerAcceptance': False}
with lp(a.output).open('x', encoding='utf8') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
    f.write('\n')
print(json.dumps(result))
