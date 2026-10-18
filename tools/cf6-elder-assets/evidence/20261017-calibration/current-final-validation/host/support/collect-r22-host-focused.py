"""Bind selected current-source tests to their actual produced assemblies."""
from pathlib import Path
import datetime, importlib.util, io, json, zipfile
import xml.etree.ElementTree as ET

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
H = O / 'host-r22-final'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
assert not (P / 'integrity.json').exists()
run = u.js(H / 'result.json')
assert run['exitCode'] == 0 and run['sourceUnchanged'] and run['serialPolicyMarkerCount'] == 1
assert run['sdk'] == u.js(R / 'global.json')['sdk']['version']
sources = u.js(H / 'source-before.json')['files']
assert sources == u.js(H / 'source-after.json')['files']
for row in sources:
    assert u.sha(R / row['path']) == row['sha256'], row['path']
tree = ET.fromstring(u.read(H / 'focused.trx'))
ns = {'t': 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010'}
counters = {k: int(v) for k, v in tree.find('t:ResultSummary/t:Counters', ns).attrib.items()}
assert counters['total'] == counters['passed'] > 480
assert counters['failed'] == counters['notExecuted'] == 0
tests = tree.findall('t:TestDefinitions/t:UnitTest', ns)
assert len(tests) == counters['total']
family_counts = dict.fromkeys(run['families'], 0)
for test in tests:
    method = test.find('t:TestMethod', ns)
    family = method.attrib['className'].split(',')[0].rsplit('.', 1)[-1]
    assert family in family_counts, family
    family_counts[family] += 1
assert all(family_counts.values()), family_counts
test_folder = R / 'launcher/tests/bin/Release'
policy = test_folder / 'xunit.runner.json'
assert u.read(policy) == u.read(R / 'launcher/tests/xunit.runner.json')
archive = io.BytesIO()
binary_rows = []
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for name in ['Launcher.Tests.dll', 'CRAZYFLASHER7MercenaryEmpire.Core.dll', 'xunit.runner.json']:
        path = test_folder / name
        binary_rows.append({'path': name, 'bytes': path.stat().st_size, 'sha256': u.sha(path)})
        z.writestr(name, u.read(path))
u.put(H / 'actual-test-binaries.zip', archive.getvalue())
u.jput(H / 'actual-test-binaries.json', {'files': binary_rows, 'boundTrx': 'focused.trx'})
report = {'ok': True, 'passed': counters['passed'], 'failed': 0, 'skipped': 0,
          'families': family_counts, 'sourceBindings': len(sources), 'sdk': run['sdk'],
          'sourceUnchanged': True, 'serialPolicyObserved': True,
          'trxSha256': u.sha(H / 'focused.trx'), 'assemblies': binary_rows,
          'wholeHostSuitePassed': False,
          'boundary': 'Fresh selected nine-family regression against the merged current source, with actual test assemblies preserved. The historical full-suite result remains 7367 passed, 120 prerequisite failures, 30 skipped out of 7517; it is not replaced by this focused success. No candidate rebuild, formal promotion, or runtime deployment is implied.'}
u.jput(H / 'assessment.json', report)
state = u.js(O / 'evidence-history-assembly.json')
package = u.Package(P)
package.mapping = state['mapping']
package.tree(H, 'current-final-validation/host')
for name in ['run-r22-host-focused.ps1', 'snapshot-r22-host-inputs.py', 'collect-r22-host-focused.py']:
    package.copy(O / name, 'current-final-validation/host/support/' + name)
package.copy(P / 'summary.json', 'progress-snapshots/20261018-before-final-host-focused.json')
summary = u.js(P / 'summary.json')
summary['currentHostFocused'] = {'report': 'current-final-validation/host/assessment.json',
                                 'passed': counters['passed'], 'failed': 0, 'families': family_counts,
                                 'wholeHostSuitePassed': False, 'formalPromotion': False}
summary['updatedAtUtc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
(P / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf8')
state['mapping'] = package.mapping
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'ok': True, 'passed': counters['passed'], 'familyCounts': family_counts, 'sealed': False}))
